function r = boltDesignLoad(joint, loadCase, factors, preload)
%BOLTDESIGNLOAD  Bolt tensile design load Pb for the thread-strength checks.
%   r = engine.boltDesignLoad(joint, loadCase, factors, preload) computes
%   the design bolt load the Phase 3.3 thread checks (bolt-thread shear,
%   nut strength, insert pull-out, tapped-hole parent thread) compare their
%   allowables against. These four rows are a supplemental practice,
%   not a NASA-STD-5020B requirement (5020B handles thread
%   stripping by design rule, §4.7.4, not by a computed margin) — but the
%   tool reports them and they can GOVERN the analysis via analyze()'s
%   worst-margin pick, so the design load they are checked against must not
%   be non-conservative. Two branches, chosen by the SAME NASA-STD-5020B
%   Fig. 8 separation-before-rupture gate engine.marginTensionUlt reports
%   (via the shared private helper separationBeforeRuptureGate — one
%   evaluation, so this can never disagree with the Tension-Ultimate row):
%
%   CLAMPED branch (Fig. 8 gate NOT assured — rupture assumed, or the gate
%   could not be assessed; TODAY'S behavior, unchanged):
%       Pb      = PpMax + FFU·FSU·n·phi·PtL       (NASA-STD-5020B Eq. 8 form)
%       PbYield = PpMax + FFY·FSY·n·phi·PtL       (Eq. 8 form, yield factors)
%   where PpMax is the max in-service preload (engine.preload), n is
%   joint.LoadingPlaneFactor, phi = kb/(kb+kc) is the stiffness factor
%   (NASA-STD-5020B Eq. 9, from engine.stiffness), and PtL is
%   loadCase.BoltTensileLimitLoad. The FF·FS factors multiply only the
%   EXTERNAL-load term (preload is not factored) — this is the
%   thread-check design load used by all four thread rows; note
%   engine.marginBearingUnderHead deliberately uses the more conservative
%   whole-Pb-factored convention.
%
%   SEPARATED branch (Fig. 8 gate ASSURED — separation before rupture):
%   the n·phi split is the load-sharing fraction between the bolt and the
%   clamped members, valid only while the joint is still clamped. Once
%   separation is assured, the members carry no load at all, so the bolt
%   sees the WHOLE factored external load — no n·phi discount, no preload
%   term (the same physical statement NASA-STD-5020B Eq. 6 makes for the
%   Tension-Ultimate row: MS = Ptu_allow/Ptu - 1, full external load, no
%   phi):
%       Pb      = FFU·FSU·PtL          (NASA-STD-5020B Eq. 6 principle,
%                                       applied to the thread-check
%                                       design load)
%       PbYield = FFY·FSY·PtL
%   Skipping the n·phi discount here is not optional bookkeeping: with
%   phi ~ 0.34, n = 1, FF·FS = 1.61, PpMax = 500 lbf, PtL = 5000 lbf, the
%   CLAMPED form gives Pb = 3,205 lbf while the true post-separation load
%   is FF·FS·PtL = 8,050 lbf — a 2.5x understatement that would report a
%   passing margin where none exists. Using the clamped form whenever the
%   gate is actually assured is therefore the non-conservative bug this
%   branch fixes.
%
%   NO SILENT BRANCH PICK: when the gate cannot be assessed at all (an
%   empty FlangeStack, or no tensile failure mode of the fastening system
%   assessable at all — rare now that the bolt-tension mode falls back to
%   a derived allowable, boltTensileAllowable, when unrated — see
%   separationBeforeRuptureGate), the CLAMPED form is used (today's
%   behavior, unchanged) and Note says the gate was not assessed rather
%   than pretending a branch was chosen on evidence.
%
%   phi handling (the stiffness call is wrapped, never allowed to crash;
%   unchanged by the branch above — phi is resolved the SAME way regardless
%   of which branch's formula ends up using it, so "not evaluated when
%   joint geometry is unknown" stays a single, consistent rule for every
%   thread check):
%     - Through-bolt (Nut) configuration: phi from engine.stiffness. If the
%       frustum geometry is missing (HeadBearingDiameter, BodyLengthInGrip,
%       ...), Pb = NaN and Note carries the reason — the caller reports
%       NotEvaluated.
%     - Threaded-in configuration (Insert / TappedHole): engine.stiffness
%       now COMPUTES this frustum form (shortened grip L = t1 + D/2), so a
%       fully-defined insert or tapped-hole joint gets a REAL phi — typically
%       ~0.2-0.3, where the old blanket phi = 1 charged it roughly 4x its
%       true share of the external load. phi = 1 survives only as a FALLBACK
%       for a threaded-in joint whose frustum geometry is incomplete (no
%       FlangeStack, no HeadBearingDiameter, ...), where it remains a
%       CONSERVATIVE bound: phi = kb/(kb+kc) <= 1 always, and Pb is monotonic
%       increasing in phi, so assuming 1 can only overstate Pb and understate
%       the thread margins. Note names the assumption and the reason for it.
%       The fallback is DELIBERATELY NOT extended to nut joints: those have
%       always reported NotEvaluated on missing geometry, and widening a
%       bounding assumption to cover them would hide real data gaps.
%   Pb and PbYield share ONE phi resolution and ONE set of failure
%   reasons: they go NaN together, with the reason in Note.
%
%   Returned struct fields:
%       Pb      ULTIMATE design bolt load, lbf (NaN = not computable; see
%               Note) — what the thread checks compare ultimate allowables
%               against (existing callers read only this, unchanged)
%       PbYield YIELD design bolt load, lbf (NaN whenever Pb is NaN) —
%               consumed by the insert pull-out yield criterion
%       Phi     stiffness factor resolved (1 for the threaded-in
%               assumption; NaN when Pb is NaN); informational only on the
%               SEPARATED branch, where the formula does not use it
%       Note    string: ALWAYS non-empty — names which branch produced Pb
%               (separated / clamped / gate-not-assessed) plus the Fig. 8
%               gate trace, any phi = 1 assumption, or the reason Pb is NaN
%
%   All loads in lbf (see UNITS.md).
%
%   Call graph:
%       Precedents (calls)      engine.stiffness (wrapped in try/catch —
%                               never allowed to crash this function; see
%                               phi handling above), separationBeforeRuptureGate
%                               (private helper, +engine/private/).
%       Dependents (called by)  the four thread checks —
%                               engine.marginBoltThreadShear,
%                               engine.marginNutStrength, engine.marginInsert,
%                               engine.marginTappedParentThread.
%       Tests                   no dedicated tests/tBoltDesignLoad.m — exercised
%                               via tests/tThreadShear.m:
%                               tappedParentGateAssuredSeparatedLoad /
%                               tappedParentGateNotAssuredClampedLoad (branch
%                               selection, Pb arithmetic on both sides of the
%                               gate), nutStrengthHandDerived,
%                               boltThreadShearHandDerived.
%
%   Validation status/coverage: no dedicated VALIDATION.md row — Pb is
%   exercised as an input to Margin-checks rows 7/8/9/14 (each row's Pb
%   figure is this function's output on that fixture).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

PtL = loadCase.BoltTensileLimitLoad;   % most-loaded-bolt tensile limit load, lbf
if isnan(PtL)
    r = struct("Pb", NaN, "PbYield", NaN, "Phi", NaN, ...
        "Note", "bolt tensile limit load undefined (NaN)");
    return
end

% ---- Stiffness factor phi (NASA-STD-5020B Eq. 9) -------------------------
% Resolved unconditionally, same as before the separation branch existed:
% "not evaluated when joint geometry is unknown" stays one rule for every
% thread check, regardless of which branch's formula below uses phi.
try
    s    = engine.stiffness(joint);    % errors on missing/mixed frustum geometry
    phi  = s.Phi;
    phiNote = "";
catch stiffErr
    if joint.ThreadedMember.Type ~= model.ThreadedMemberType.Nut
        % Threaded-in joint whose frustum geometry is incomplete. engine.stiffness
        % CAN now compute this configuration (shortened grip L = t1 + D/2), so
        % this is no longer a deferred method — it is a missing-DATA fallback.
        % phi = 1 is a conservative BOUND, not an estimate: phi = kb/(kb+kc) <= 1
        % always, and Pb = PpMax + FF*FS*n*phi*PtL rises with phi, so assuming 1
        % can only overstate Pb and understate the thread margins. Supplying the
        % frustum geometry (FlangeStack, HeadBearingDiameter, BodyLengthInGrip)
        % replaces it with the real phi and RELAXES these margins.
        phi     = 1;
        phiNote = "phi = 1 ASSUMED — threaded-in joint, real stiffness unavailable (" + ...
                  string(stiffErr.message) + "). Conservative bound (phi <= 1); " + ...
                  "supply the frustum geometry for the computed phi";
    else
        r = struct("Pb", NaN, "PbYield", NaN, "Phi", NaN, ...
            "Note", "Pb needs phi from engine.stiffness, which could not run: " + ...
                    string(stiffErr.message));
        return
    end
end

% ---- Separation-before-rupture gate (NASA-STD-5020B Fig. 8) --------------
% SHARED with engine.marginTensionUlt via the private helper
% separationBeforeRuptureGate — one evaluation, so this design load and the
% Tension-Ultimate row can never disagree about which branch applies.
gate = separationBeforeRuptureGate(joint, preload);

if gate.Assessed && gate.Assured
    % NASA-STD-5020B Eq. 6 principle (separation before rupture assured):
    % once separated the clamped members carry no load, so the bolt takes
    % the WHOLE factored external load — no n·phi discount, no preload term.
    Pb      = factors.FFU * factors.FSU * PtL;
    PbYield = factors.FFY * factors.FSY * PtL;
    branchNote = "SEPARATED branch (Fig. 8 gate assured: " + gate.Trace + "): " + ...
        "Pb = FFU·FSU·PtL (no preload/n·phi — members carry no load once separated)";
else
    % NASA-STD-5020B Eq. 8 form — Pb = PpMax + FFU·FSU·n·phi·PtL (design bolt
    % load for the thread checks; ultimate factors on the external term only)
    Pb = preload.PpMax + factors.FFU * factors.FSU * joint.LoadingPlaneFactor * phi * PtL;
    % NASA-STD-5020B Eq. 8 form, yield factor pair — PbYield = PpMax +
    % FFY·FSY·n·phi·PtL (cf. engine.designLoads' Ptu = FSU·FFU·PtL vs
    % Pty = FSY·FFY·PtL relationship; consumed by the insert yield criterion)
    PbYield = preload.PpMax + factors.FFY * factors.FSY * joint.LoadingPlaneFactor * phi * PtL;
    if gate.Assessed
        branchNote = "CLAMPED branch (Fig. 8 gate not assured, rupture assumed: " + ...
            gate.Trace + "): Pb = PpMax + FF·FS·n·phi·PtL, unchanged";
    else
        branchNote = "CLAMPED branch (" + gate.Trace + "): " + ...
            "Pb = PpMax + FF·FS·n·phi·PtL, today's behavior unchanged (no branch silently picked)";
    end
end

note = branchNote;
if strlength(phiNote) > 0
    note = note + "; " + phiNote;
end

r = struct("Pb", Pb, "PbYield", PbYield, "Phi", phi, "Note", string(note));
end
