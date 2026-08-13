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
%   AREA FORM — NASA TM-106943 (Chambers) Eq. 63 AS PRINTED:
%
%       As = 5·pi·Le·D_minor,int / 8
%
%   TM-106943 p18: "The thread shear area of the bolt is the cylindrical
%   area formed by the MINOR DIAMETER OF THE MATING INTERNAL THREADS and
%   the length of thread engagement (ref. 8)."
%
%   D_minor,int is the BASIC minor diameter of the mating INTERNAL thread —
%   the hole the bolt's threads must shear across — computed per ASME B1.1
%   UN thread geometry from the nominal diameter and pitch:
%
%       D_minor,int = D - 2·(5/8)·H = D - 1.08253·p,   H = 0.86602540·p
%
%   Basic is also the MINIMUM for an internal thread (the minor diameter
%   carries a plus tolerance from basic), so this is the conservative pick
%   of the tolerance band, and it is computed rather than catalogued for
%   the same reason Bolt.MinorDiameter is (see +data/library.json's bolt
%   `source` note). NOTE it is NOT joint.Bolt.MinorDiameter: that is the
%   BOLT's own minor (D - 1.299·p, the external thread root), a smaller
%   cylinder that is not the surface Eq. 63 describes.
%
%   Le = engagement length, resolved by the private helper
%   resolveEngagementLength: joint.ThreadedMember.EngagementRatio x
%   Bolt.NominalDiameter when the ratio is set (OVERRIDING EngagementLength
%   — Detail says which), else the unchanged joint.ThreadedMember.
%   EngagementLength.
%
%   ⚠️ THIS ROW USED TO BE ~29% UNCONSERVATIVE, and the reason is worth
%   keeping. It computed As = 0.75·pi·E·Le on the PITCH diameter — TM
%   Eq. 76's INTERNAL-thread coefficient and a larger diameter — and
%   justified it as applying "the SAME form to BOTH sides of the
%   engagement, so the bolt-external and internal-thread rows are compared
%   on one consistent area basis."
%
%   That rationale does not survive: the substitution runs in OPPOSITE
%   directions on the two sides. On the internal side, Eq. 76 wants 3/4 on
%   the MAJOR diameter of the mating external thread, so using the pitch
%   diameter is CONSERVATIVE. On this, the external side, Eq. 63 wants 5/8
%   on the MINOR diameter of the mating internal thread, so 3/4 on the
%   pitch diameter was UNCONSERVATIVE — by ×(0.75/0.625)·(E/D_minor,int)
%   = ×1.27 on a 3/8-24 (and still ~18% high against the exact
%   FED-STD-H28 external-thread form). The "consistency" was cosmetic
%   while the bias was real, and it made analyze()'s worst-margin pick
%   systematically under-report bolt thread shear as the governing mode.
%   Found by the 2026-08-13 equation audit; corrected here to the printed
%   equation. The internal side is unchanged and stays on Eq. 76 — see
%   memberTensileUltAllowable.
%
%   NASA-STD-5020B prints no thread-shear-area equation of its own (full
%   Eq. 1-87 inventory; Eq. 12/13 are the fastener CROSS-SECTION shear
%   allowable, a different failure mode), so citing the supplement here is
%   legitimate per CLAUDE.md's document-hierarchy rule.
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
%       As      thread-shear area 5·pi·Le·D_minor,int/8, in^2 (NaN if missing)
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

method = "TM-106943 Eq. 63 (bolt thread shear) AS PRINTED — As = 5·pi·Le·D_minor,int/8 on the minor diameter of the mating INTERNAL thread (basic, per ASME B1.1: D_minor,int = D - 1.08253·p) + Eq. 64/65 MS; Pb per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, Pb = FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";

D   = joint.Bolt.NominalDiameter;             % nominal thread diameter, in
tpi = joint.Bolt.ThreadsPerInch;              % threads per inch
% Le: ratio-or-absolute, single resolution — see resolveEngagementLength
% (EngagementRatio, when set, OVERRIDES EngagementLength; Note says which).
rle = resolveEngagementLength(joint);
Le  = rle.Le;                                 % thread engagement, in
Fsu = joint.BoltMaterial.Fsu;                 % bolt-material ultimate shear strength, psi
if isnan(D) || isnan(tpi) || tpi <= 0 || isnan(Le) || isnan(Fsu)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: needs Bolt.NominalDiameter, Bolt.ThreadsPerInch, ThreadedMember.EngagementLength or EngagementRatio x Bolt.NominalDiameter, and BoltMaterial.Fsu (one or more NaN or non-positive).", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

p = 1 / tpi;                                  % thread pitch, in
% ASME B1.1 UN thread geometry — D_minor,int = D - 2·(5/8)·H with
% H = 0.86602540·p, i.e. D_minor,int = D - 1.08253·p. The BASIC (= minimum)
% minor diameter of the mating INTERNAL thread; see the header for why this
% is not Bolt.MinorDiameter.
Dminor = D - 1.08253 * p;                     % internal-thread minor dia, in
% TM-106943 Eq. 63 — As = 5·pi·Le·D_minor,int / 8
As = (5/8) * pi * Le * Dminor;                % external-thread shear area, in^2
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

detail = string(sprintf( ...
    "D_minor,int %.4f in (= D %.4f - 1.08253·p, p %.5f in), As %.4f in^2, Pult %.0f lbf, Pb %.0f lbf; %s", ...
    Dminor, D, p, As, Pult, d.Pb, rle.Note));
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end
r = struct("MS", MS, "Method", method, "Detail", detail + ".", ...
    "As", As, "Pult", Pult, "Pb", d.Pb);
end
