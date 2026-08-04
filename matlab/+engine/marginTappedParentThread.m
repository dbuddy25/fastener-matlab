function r = marginTappedParentThread(joint, loadCase, factors, preload)
%MARGINTAPPEDPARENTTHREAD  Tapped-hole parent-material thread shear margin.
%   r = engine.marginTappedParentThread(joint, loadCase, factors, preload)
%   checks shear failure (stripping) of the PARENT material's internal
%   threads in a tapped-hole joint — the check that governs when a strong
%   bolt threads into a soft parent (e.g. A-286 into aluminum). Only
%   evaluated when joint.ThreadedMember.Type == TappedHole; otherwise
%   MS = NaN (NotEvaluated). preload is the struct from engine.preload.
%   Loads in lbf, lengths in inches, strengths in psi (see UNITS.md).
%
%   AREA BASIS (deliberate): internal-thread shear area in the
%   pitch-diameter form,
%       As = 0.75·pi·E·Le
%   with E = thread pitch diameter (joint.Bolt.PitchDiameter) and
%   Le = engagement length (the tapped thread depth), resolved by the
%   private helper resolveEngagementLength: joint.ThreadedMember.
%   EngagementRatio x Bolt.NominalDiameter when the ratio is set
%   (OVERRIDING EngagementLength — Detail says which), else the unchanged
%   joint.ThreadedMember.EngagementLength. NASA-STD-5020B prints no thread-shear-area
%   equation; the working reference is NASA TM-106943 (Chambers), whose
%   Eq. 79 gives the tapped-parent pull-out strength Pult = Fsu·As (this
%   tool supplies the 0.75·pi·E·Le area; TM's own Eq. 78/79 area uses a
%   5/8 coefficient, and DABJ §6 uses the H28 tolerance form with a
%   judgment knockdown — see the validation note below). The 0.75
%   coefficient on the pitch diameter is used consistently across every
%   internal-thread shear area in this engine, so the nut, insert and
%   tapped-hole rows are formed on one basis. Then:
%       Pult = Fsu·As            (TM-106943 Eq. 79)
%       MS   = Pult/Pb - 1       (TM-106943 Eq. 65 MS form)
%   with Fsu = joint.ThreadedMember.Material.Fsu (the PARENT material) and
%   the design bolt load Pb from engine.boltDesignLoad (phi COMPUTED for
%   this threaded-in configuration, falling back to the conservative bound
%   phi = 1 only when the frustum geometry is incomplete), which branches on
%   the NASA-STD-5020B Fig. 8 separation-before-rupture gate (shared with
%   engine.marginTensionUlt, so this row and the tension row can never
%   disagree about which branch applies):
%       clamped (gate not assured / not assessable, unchanged):
%           Pb = PpMax + FFU·FSU·n·phi·PtL     (NASA-STD-5020B Eq. 8 form)
%       separated (gate assured — members carry no load once separated):
%           Pb = FFU·FSU·PtL                   (NASA-STD-5020B Eq. 6
%                                               principle, no preload/n·phi)
%   Detail names which branch produced Pb (via engine.boltDesignLoad's Note).
%
%   Validated against DABJ Example 6-a (#10-32 A-286 in 0.250-in
%   6061-T651); see VALIDATION.md (Margin checks, row 14) for the
%   area/allowable agreement and the un-knocked-vs-DABJ's-knockdown note.
%
%   ULTIMATE-ONLY (deliberate gap, not an oversight): unlike the insert
%   pull-out check (engine.marginInsert), which carries a parent-material
%   ultimate/yield pair per NASA-STD-5020B §4.4.1, this tapped-hole check
%   has NO yield counterpart — whether a yield criterion belongs on tapped
%   parent threads at all is an open decision that has been deliberately
%   deferred. Do not add one without that decision.
%
%   NotEvaluated (MS = NaN) when the configuration is not a tapped hole,
%   when PitchDiameter / the resolved Le (EngagementLength or
%   EngagementRatio x NominalDiameter) / parent Fsu is NaN, or when Pb
%   cannot be computed — reason in Detail; never crashes.
%
%   Returned struct fields:
%       MS      margin of safety (NaN = not evaluated)
%       Method  string: governing equation citation
%       Detail  string: the numbers used (or the not-evaluated reason)
%       As      thread-shear area 0.75·pi·E·Le, in^2 (NaN if not evaluated)
%       Pult    parent thread-shear allowable Fsu·As, lbf (NaN if not evaluated)
%       Pb      design bolt load, lbf (NaN if not computable)
%
%   Call graph:
%       Precedents (calls)      engine.boltDesignLoad,
%                               memberTensileUltAllowable (private),
%                               resolveEngagementLength (private).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tThreadShear.m —
%                               tappedParentMatchesDABJ6a (DABJ Ex 6-a
%                               area/allowable cross-check + hand-derived
%                               MS); tappedParentGateAssuredSeparatedLoad,
%                               tappedParentGateNotAssuredClampedLoad (Fig.
%                               8 gate SEPARATED/CLAMPED branch pins);
%                               dabjSection9RegressionUnchanged (§9 answer
%                               key unchanged, row NotEvaluated, via
%                               engine.analyze).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 14).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "TM-106943 Eq. 79 (tapped-hole parent thread shear) via the As = 0.75·pi·E·Le pitch-diameter form + Eq. 65 MS; Pb per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, Pb = FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";

if joint.ThreadedMember.Type ~= model.ThreadedMemberType.TappedHole
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: threaded member is not a tapped hole (" + ...
                  string(joint.ThreadedMember.Type) + ").", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

E   = joint.Bolt.PitchDiameter;               % thread pitch diameter, in
% Le: ratio-or-absolute, single resolution — see resolveEngagementLength
% (EngagementRatio, when set, OVERRIDES EngagementLength; Note says which).
rle = resolveEngagementLength(joint);
Le  = rle.Le;                                 % tapped thread engagement (depth), in
Fsu = joint.ThreadedMember.Material.Fsu;      % PARENT-material ultimate shear strength, psi
if isnan(E) || isnan(Le) || isnan(Fsu)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: needs Bolt.PitchDiameter, ThreadedMember.EngagementLength or EngagementRatio x Bolt.NominalDiameter, and the parent Material.Fsu (one or more NaN).", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

% Pitch-diameter thread-shear area — As = 0.75·pi·E·Le — and the
% TM-106943 Eq. 79 allowable Pult = Fsu·As (parent pull-out strength),
% both computed in memberTensileUltAllowable, SHARED with
% engine.systemTensileAllowable (5020B §4.4.1 system minimum) so this row
% and the system allowable can never disagree.
ua   = memberTensileUltAllowable(joint);
As   = ua.As;                                 % parent internal-thread shear area, in^2
Pult = ua.EffUlt;                             % Fsu·As, lbf (no rating for a tapped hole)

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

% TM-106943 Eq. 65 MS form — MS = Pult/Pb - 1
MS = Pult / d.Pb - 1;

detail = string(sprintf("E %.4f in, As %.4f in^2, Pult %.0f lbf, Pb %.0f lbf; %s", ...
    E, As, Pult, d.Pb, rle.Note));
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end
r = struct("MS", MS, "Method", method, "Detail", detail + ".", ...
    "As", As, "Pult", Pult, "Pb", d.Pb);
end
