function r = marginShearTearout(joint, loadCase, factors)
%MARGINSHEARTEAROUT  Flange shear tear-out margin (NASA TM-106943 Eq. 69-71).
%   r = engine.marginShearTearout(joint, loadCase, factors) computes the
%   shear tear-out margin — the bolt shearing out the material between the
%   hole and the free edge — for one joint. All loads in lbf, lengths in
%   inches, strengths in psi (see UNITS.md).
%
%   NASA-STD-5020B REQUIRES margins for the clamped parts (tear-out among
%   them) but prints no member-strength equations. BOTH criteria are
%   required, and by two different sections:
%     §4.4.1 p26 (ultimate) — "Assessment for ultimate design loads
%       addresses potential rupture in all elements of the threaded
%       fastening system, including the fastener, the internally threaded
%       part such as a nut or an insert, AND THE CLAMPED PARTS."
%     §4.4.2 p29 [TFSR 9] (yield) — "The assessment for yield design loads
%       will address all elements of the threaded fastening system,
%       including the fastener, the internally threaded part such as a nut
%       or an insert, AND THE CLAMPED PARTS."
%   The working equations are NASA TM-106943 (Chambers) Eq. 69-71:
%       As   = 2 * t * (e - D/2)      (two shear planes hole -> edge, Eq. 70)
%       Pult = Fsu * As               (tear-out allowable, Eq. 69)
%   (These two were labelled the other way round until the 2026-08-13
%   audit read TM-106943 p19: Eq. 69 is the allowable, Eq. 70 the area.)
%       MS   = Pult / (FFU*FSU*V) - 1 (Eq. 71)
%   evaluated for each flange layer that has CheckShearTearout = true AND
%   a configured EdgeDistance. The reported margin is the WORST (minimum)
%   over the checked layers AND both criteria.
%
%   THE YIELD CRITERION IS 5020B'S, NOT TM'S. TM-106943 works tear-out at
%   ultimate only — Eq. 69 is Pult = Fsu·As throughout, and unlike the
%   bearing section (Eq. 72-74, "These equations should be checked for
%   both yield and ultimate conditions") it never mentions yield. But
%   §4.4.2 p29 requires the yield assessment to address the clamped parts,
%   and 5020B governs where the two differ (see CLAUDE.md's document
%   hierarchy). So the same TM Eq. 70 area is taken against the member's
%   SHEAR YIELD strength with the yield factors:
%       Pyld = Fsy * As
%       MS   = Pyld / (FFY*FSY*V) - 1
%   Fsy comes from engine.shearYieldStrength — the material's supplied Fsy
%   when it has one, else NASA-STD-5020B Eq. 63 (p66, A.8) Fsy = Fty/sqrt(3)
%   — the SAME helper the nut and insert rows use, so every site agrees on
%   the basis, and a derived Fsy stays visible in Detail rather than
%   passing as test data.
%
%   WHY THIS ROW AND NOT THE THREAD ROWS. The thread-shear rows are
%   ultimate-only because TM Eq. 80 scopes them that way AND their yield
%   obligation is discharged elsewhere — engine.systemTensileYieldAllowable
%   folds each member's As·Fsy into Tension-Yield. That covers TENSILE
%   modes. Tear-out is shear-driven and falls through it entirely, so
%   nothing else in the engine was assessing the clamped parts for yield
%   under shear. Found by the 2026-08-14 margin review.
%
%   V = loadCase.BoltShearLimitLoad (most-loaded bolt), D =
%   joint.Bolt.NominalDiameter, e = layer EdgeDistance (hole center to
%   free edge), t = layer Thickness, Fsu = layer material ultimate shear
%   strength. As is clamped at >= 0 (e <= D/2 means no material between
%   hole and edge). The Eq. 69-71 form is valid for e/D >= 1.5; a
%   governing layer with e/D < 1.5 gets a caution appended to Detail
%   (a Bruhn-type analysis is needed there).
%
%   Guards: V = NaN -> MS = NaN (NotEvaluated); V = 0 -> MS = Inf (no
%   applied shear — falls out of the arithmetic); no layer checkable
%   (no EdgeDistance set / tear-out disabled / Fsu unset) -> MS = NaN.
%
%   Returned struct fields:
%       MS      worst margin of safety (double; NaN = not evaluated)
%       Method  string: governing equation citation
%       Detail  string: governing layer + its e/D (or the not-evaluated
%               reason), with the e/D < 1.5 caution when applicable
%
%   Call graph:
%       Precedents (calls)      engine.shearYieldStrength (for the §4.4.2
%                               yield criterion — the same helper the nut
%                               and insert rows use). Otherwise joint/model
%                               getters, loadCase.BoltShearLimitLoad and
%                               factors.
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tBearing.m —
%                               shearTearoutHandDerived (two-layer
%                               hand-derived MS pin);
%                               tearoutCautionBelowValidity (e/D < 1.5
%                               caution-flag pin);
%                               tearoutYieldCriterionCanGovern,
%                               tearoutYieldUsesDerivedFsyAndSaysSo,
%                               tearoutSkipsYieldWithNoYieldData
%                               (the §4.4.2 p29 yield criterion).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 4).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

method = "NASA TM-106943 Eq. 69-71 (shear tear-out) — Eq. 70 area 2t(e-D/2), Eq. 69 Pult = Fsu*As, Eq. 71 MS; yield counterpart Pyld = Fsy*As vs FFY*FSY*V with Fsy per NASA-STD-5020B Eq. 63; required for the clamped parts by NASA-STD-5020B §4.4.1 p26 (ultimate) and §4.4.2 p29 (yield)";

V = loadCase.BoltShearLimitLoad;   % PsL, most-loaded bolt, lbf
D = joint.Bolt.NominalDiameter;    % bolt major diameter, in

if isnan(V) || isnan(D)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: bolt shear limit load and/or bolt diameter undefined (NaN).");
    return
end

msList     = [];
eodList    = [];
detailList = strings(1, 0);
for k = 1:numel(joint.FlangeStack)
    fl = joint.FlangeStack(k);
    e  = fl.EdgeDistance;              % hole center -> free edge, in
    Fsu = fl.Material.Fsu;             % member ultimate shear strength, psi
    if ~fl.CheckShearTearout || isnan(e) || isnan(Fsu)
        continue                       % layer opted out or not configured
    end
    t = fl.Thickness;                  % layer thickness, in
    % NASA TM-106943 Eq. 69-71 — As = 2t(e − D/2) ; Pult = Fsu·As ;
    % MS = Pult/(FFU·FSU·V) − 1
    As   = max(2 * t * (e - D/2), 0);  % two shear planes, clamped >= 0, in^2
    Pult = Fsu * As;                   % tear-out allowable, lbf
    msList(end+1)     = Pult / (factors.FFU * factors.FSU * V) - 1; %#ok<AGROW>
    eodList(end+1)    = e / D;                                      %#ok<AGROW>
    detailList(end+1) = string(sprintf( ...
        "layer %d (%s), ultimate, e = %.3f in, e/D = %.2f — Pult = %.0f lbf vs V = %.0f lbf", ...
        k, fl.Material.Name, e, e/D, Pult, V));                     %#ok<AGROW>

    % NASA-STD-5020B §4.4.2 p29 yield counterpart on the SAME Eq. 70 area —
    % Pyld = Fsy·As ; MS = Pyld/(FFY·FSY·V) − 1. Skipped, not failed, when
    % the material offers neither Fsy nor the Fty that NASA-STD-5020B
    % Eq. 63 derives it from: a member with no yield data is unassessed for
    % yield, and inventing one would be worse than saying so.
    sy = engine.shearYieldStrength(fl.Material);
    if ~isnan(sy.Fsy) && sy.Fsy > 0
        Pyld = sy.Fsy * As;            % tear-out yield allowable, lbf
        msList(end+1)  = Pyld / (factors.FFY * factors.FSY * V) - 1; %#ok<AGROW>
        eodList(end+1) = e / D;                                      %#ok<AGROW>
        % Only the DERIVED case is annotated. shearYieldStrength always
        % returns a Basis string, including for a supplied Fsy, but the
        % repo convention is that an ESTIMATED Fsy must never pass as test
        % data -- so the note marks the estimate rather than restating the
        % obvious for a real one.
        fsyNote = "";
        if sy.Derived
            fsyNote = " [" + sy.Basis + "]";
        end
        detailList(end+1) = string(sprintf( ...
            "layer %d (%s), yield, e = %.3f in, e/D = %.2f — Pyld = %.0f lbf vs V = %.0f lbf", ...
            k, fl.Material.Name, e, e/D, Pyld, V)) + fsyNote;        %#ok<AGROW>
    end
end

if isempty(msList)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: no flange layer has tear-out enabled with an EdgeDistance and member Fsu set.");
    return
end

[MS, idx] = min(msList);   % worst layer governs
detail = "Governing: " + detailList(idx) + ".";
if eodList(idx) < 1.5
    % Eq. 69-71 assumes e/D >= 1.5; below that the simple two-plane form is
    % outside its validity range (Bruhn-type bearing/tear-out analysis needed).
    detail = detail + " CAUTION: e/D < 1.5 is outside the Eq. 69-71 validity range — a Bruhn-type analysis is needed.";
end
r = struct("MS", MS, "Method", method, "Detail", detail);
end
