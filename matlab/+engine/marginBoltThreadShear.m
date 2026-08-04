function r = marginBoltThreadShear(joint, loadCase, factors, preload)
%MARGINBOLTTHREADSHEAR  Bolt external-thread shear (pull-out) margin.
%   r = engine.marginBoltThreadShear(joint, loadCase, factors, preload)
%   checks shear failure of the BOLT's external threads over the engaged
%   length — the bolt-side of the thread-stripping pair (the mating
%   internal-thread side is engine.marginNutStrength,
%   engine.marginInsert, or engine.marginTappedParentThread, per
%   configuration; the weaker side governs via analyze()'s worst-margin
%   pick). preload is the struct from
%   engine.preload. Loads in lbf, lengths in inches, strengths in psi
%   (see UNITS.md).
%
%   AREA FORM (deliberate): the thread-shear area is the pitch-diameter
%   form
%       As = 0.75·pi·E·Le
%   with E = thread pitch diameter (joint.Bolt.PitchDiameter) and
%   Le = engagement length, resolved by the private helper
%   resolveEngagementLength: joint.ThreadedMember.EngagementRatio x
%   Bolt.NominalDiameter when the ratio is set (OVERRIDING EngagementLength
%   — Detail says which), else the unchanged joint.ThreadedMember.
%   EngagementLength. This is NASA TM-106943 (Chambers) Eq. 63's external-thread shear area
%   with a 3/4 coefficient and pitch-diameter substitution (TM's
%   printed Eq. 63 uses 5/8·pi·d_minor,int·Le; the 3/4·pi coefficient is
%   TM Eq. 76's internal-thread form). This tool deliberately applies the
%   SAME 0.75·pi·E·Le form to BOTH sides of the engagement, so the
%   bolt-external and internal-thread rows are compared on one consistent
%   area basis. NASA-STD-5020B prints no thread-shear-area equation.
%   Then, per TM-106943 Eq. 64/65:
%       Pult = Fsu·As            (Eq. 64)
%       MS   = Pult/Pb - 1       (Eq. 65)
%   with Fsu = joint.BoltMaterial.Fsu and the design bolt load Pb from
%   engine.boltDesignLoad, which itself branches on the NASA-STD-5020B
%   Fig. 8 separation-before-rupture gate (shared with
%   engine.marginTensionUlt, so this row and the tension row can never
%   disagree about which branch applies — see engine.boltDesignLoad for the
%   phi handling and the full branch derivation):
%       clamped (gate not assured / not assessable, unchanged):
%           Pb = PpMax + FFU·FSU·n·phi·PtL     (NASA-STD-5020B Eq. 8 form)
%       separated (gate assured — members carry no load once separated):
%           Pb = FFU·FSU·PtL                   (NASA-STD-5020B Eq. 6
%                                               principle, no preload/n·phi)
%   Detail names which branch produced Pb (via engine.boltDesignLoad's Note).
%
%   NotEvaluated (MS = NaN) when PitchDiameter, the resolved Le
%   (EngagementLength or EngagementRatio x NominalDiameter), or the bolt
%   Fsu is NaN, or when Pb cannot be computed (missing stiffness geometry)
%   — the reason is in Detail; never crashes.
%
%   Returned struct fields:
%       MS      margin of safety (NaN = not evaluated)
%       Method  string: governing equation citation
%       Detail  string: the numbers used (or the not-evaluated reason)
%       As      thread-shear area 0.75·pi·E·Le, in^2 (NaN if inputs missing)
%       Pult    thread-shear allowable Fsu·As, lbf (NaN if inputs missing)
%       Pb      design bolt load, lbf (NaN if not computable)
%
%   Call graph:
%       Precedents (calls)      engine.boltDesignLoad,
%                               resolveEngagementLength (private).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tThreadShear.m —
%                               boltThreadShearHandDerived (hand-derived MS
%                               pin, Ex 8-b Nut fixture; the Fig. 8 gate is
%                               ASSURED on this fixture, so Pb takes the
%                               SEPARATED branch);
%                               dabjSection9RegressionUnchanged (guards the
%                               DABJ §9 answer key — this row stays
%                               NotEvaluated on that fixture, no
%                               EngagementLength).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 7).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "TM-106943 Eq. 63 (bolt thread shear) via the As = 0.75·pi·E·Le pitch-diameter form + Eq. 64/65 MS; Pb per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, Pb = FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";

E   = joint.Bolt.PitchDiameter;               % thread pitch diameter, in
% Le: ratio-or-absolute, single resolution — see resolveEngagementLength
% (EngagementRatio, when set, OVERRIDES EngagementLength; Note says which).
rle = resolveEngagementLength(joint);
Le  = rle.Le;                                 % thread engagement, in
Fsu = joint.BoltMaterial.Fsu;                 % bolt-material ultimate shear strength, psi
if isnan(E) || isnan(Le) || isnan(Fsu)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: needs Bolt.PitchDiameter, ThreadedMember.EngagementLength or EngagementRatio x Bolt.NominalDiameter, and BoltMaterial.Fsu (one or more NaN).", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

% TM-106943 Eq. 63, pitch-diameter form — As = 0.75·pi·E·Le
As = 0.75 * pi * E * Le;                      % external-thread shear area, in^2
% TM-106943 Eq. 64 — Pult = Fsu·As
Pult = Fsu * As;                              % thread-shear allowable, lbf

% Pb: NASA-STD-5020B Eq. 8 (clamped, PpMax+FFU·FSU·n·phi·PtL) or, when the
% Fig. 8 gate assures separation before rupture, Eq. 6 principle
% (FFU·FSU·PtL, no preload/n·phi) — engine.boltDesignLoad picks the branch;
% d.Note says which.
d = engine.boltDesignLoad(joint, loadCase, factors, preload);
if isnan(d.Pb)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: " + d.Note + ".", ...
        "As", As, "Pult", Pult, "Pb", NaN);
    return
end

% TM-106943 Eq. 65 — MS = Pult/Pb - 1
MS = Pult / d.Pb - 1;

detail = string(sprintf("E %.4f in, As %.4f in^2, Pult %.0f lbf, Pb %.0f lbf; %s", ...
    E, As, Pult, d.Pb, rle.Note));
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end
r = struct("MS", MS, "Method", method, "Detail", detail + ".", ...
    "As", As, "Pult", Pult, "Pb", d.Pb);
end
