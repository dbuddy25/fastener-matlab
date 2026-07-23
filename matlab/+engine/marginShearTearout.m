function r = marginShearTearout(joint, loadCase, factors)
%MARGINSHEARTEAROUT  Flange shear tear-out margin (NASA TM-106943 Eq. 69-71).
%   r = engine.marginShearTearout(joint, loadCase, factors) computes the
%   shear tear-out margin — the bolt shearing out the material between the
%   hole and the free edge — for one joint. All loads in lbf, lengths in
%   inches, strengths in psi (see UNITS.md).
%
%   NASA-STD-5020B §4.4.2 REQUIRES margins for the joint members (tear-out
%   among them) but prints no member-strength equations; the working
%   equations are NASA TM-106943 (Chambers) Eq. 69-71:
%       As   = 2 * t * (e - D/2)      (two shear planes hole -> edge, Eq. 69/70)
%       Pult = Fsu * As               (tear-out allowable, Eq. 70)
%       MS   = Pult / (FFU*FSU*V) - 1 (Eq. 71)
%   evaluated (ultimate only — the check uses the member Fsu) for each
%   flange layer that has CheckShearTearout = true AND a configured
%   EdgeDistance. The reported margin is the WORST (minimum) over the
%   checked layers.
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
%   No public worked example covers this check (DABJ works no member
%   tear-out margin); it is verified by HAND-DERIVED arithmetic in
%   tests/tBearing.m (shearTearoutHandDerived).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

method = "NASA TM-106943 Eq. 69-71 (shear tear-out); required by NASA-STD-5020B §4.4.2";

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
        "layer %d (%s), e = %.3f in, e/D = %.2f — Pult = %.0f lbf vs V = %.0f lbf", ...
        k, fl.Material.Name, e, e/D, Pult, V));                     %#ok<AGROW>
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
