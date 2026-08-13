function r = marginTensionYield(joint, preload, designLoads)
%MARGINTENSIONYIELD  Yield-tension margin with separation-before-rupture gate.
%   r = engine.marginTensionYield(joint, preload, designLoads) evaluates the
%   SAME NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) separation-before-rupture
%   decision tree as engine.marginTensionUlt (via the shared private helper
%   separationBeforeRuptureGate — one evaluation, so the yield row can
%   never disagree with the Tension-Ultimate row about which branch
%   applies), then computes the yield-tension margin of safety.
%   preload is the struct from engine.preload; designLoads is the struct
%   from engine.designLoads. All loads in lbf (see UNITS.md).
%
%   If assured (separation occurs before yield): the bolt sees only the
%   external design load —
%       MS = Pty_allow / (FF*FSy*PtL) - 1                     (Eq. 15)
%   where Pty = designLoads.Pty (FSY*FFY*PtL) already carries FF*FSy*PtL.
%
%   If NOT assured (yield occurs before separation): the bolt carries the
%   max preload PLUS its share of the applied load, so the margin uses the
%   joint-stiffness factor phi from engine.stiffness (NASA-STD-5020B Eq. 9)
%   and the loading-plane factor n —
%       P'ty = (1/(n*phi))*(Pty_allow - Pp_max)                (Eq. 17)
%       MS   = P'ty / (FF*FSy*PtL) - 1                         (Eq. 16)
%   exactly the yield analogue of the ultimate side's Eq. 7/10 pair. If
%   engine.stiffness cannot run (threaded-in configuration or missing
%   frustum geometry), the check reports MS = NaN with the reason in
%   Detail rather than crashing the analysis — matching
%   engine.marginTensionUlt's handling exactly, not a new convention.
%
%   Pty_allow IS THE FASTENING SYSTEM'S, NOT THE BOLT'S ALONE. This row
%   used the bolt's own yield allowable in both equations until the
%   §4.4.2 read that produced engine.systemTensileYieldAllowable.
%   NASA-STD-5020B p30, introducing Eq. 17, says the term is "the applied
%   tensile load that causes the fastener load to exceed the fastening
%   SYSTEM'S allowable yield tensile load", and §4.4.2 p29 scopes the
%   assessment to "all elements of the threaded fastening system,
%   including the fastener, the internally threaded part such as a nut or
%   an insert, and the clamped parts". So Pty_allow here is
%       min( bolt yield, internal-thread member yield )
%   exactly as engine.marginTensionUlt takes Ptu_allow from
%   engine.systemTensileAllowable in Eq. 6 / Eq. 10. The bolt-only
%   resolution is unchanged — it is mode 1 of that minimum, still
%   boltTensileAllowable, still "rated" (joint.BoltRatedYieldLoad) or the
%   NASA-STD-5020B Eq. 18 estimate Pty_allow = (Fty/Ftu)*Ptu_allow applied
%   to whichever ultimate is actually in use. Mode 2 is
%   memberTensileYldAllowable's As*Fsy. See
%   engine.systemTensileYieldAllowable for both, and for why a spec-RATED
%   nut or insert contributes no yield mode at all.
%
%   THE MINIMUM IS NOT THE SAME AS THE MINIMUM OVER THE PER-MODE ROWS, and
%   that is the reason this had to move rather than being left to
%   Result.WorstMargin. The per-mode member yield rows (engine.marginInsert,
%   engine.marginNutStrength) divide by boltDesignLoad's Pb, which on the
%   not-assured branch is PpMax + FF*FS*n*phi*PtL; Eq. 17 SUBTRACTS PpMax
%   first and then divides by n*phi. The two forms are different functions
%   of the same allowable, so no min() over the rows can reproduce Eq. 17's
%   number. They do always agree in SIGN, which is why this correction
%   moves magnitudes and attribution, not pass/fail verdicts.
%
%   NotEvaluated (MS = NaN) when NO mode of the system can be assessed —
%   the bolt has neither a rating nor the Eq. 18 inputs (Ptu_allow itself
%   unassessable, or BoltMaterial.Fty / Ftu is NaN) AND the member has no
%   yield mode either — or, on the not-assured branch only, when Eq. 17
%   needs phi from engine.stiffness and it cannot run. Detail names every
%   mode's specific missing input; never throws.
%
%   INCOMPLETE ASSESSMENTS REACH DETAIL. When one mode assesses and the
%   other does not, the minimum is over an incomplete set and is therefore
%   OPTIMISTIC; systemTensileYieldAllowable's Note says so and this row
%   appends it verbatim. A rated nut or insert always lands here, because
%   a rating carries no yield information.
%
%   Returned struct fields:
%       MS      margin of safety (double; NaN = not evaluated)
%       SeparationBeforeYield logical: gate result (mirrors
%               marginTensionUlt.SeparationBeforeRupture; the SAME gate)
%       Method  string: governing equation + basis
%       Detail  string: the gate trace, the system allowable used, which
%               mode governed it, each mode's basis, and the arithmetic
%               (or the not-evaluated reason)
%       SystemAllowable  Pty_allow actually used, lbf (NaN when not
%               evaluated) — mirrors engine.marginTensionUlt's field of the
%               same purpose, so a caller can report the allowable without
%               re-deriving it
%
%   Call graph:
%       Precedents (calls)      engine.systemTensileYieldAllowable (which
%                               calls boltTensileAllowable and
%                               memberTensileYldAllowable),
%                               separationBeforeRuptureGate (private
%                               helper, +engine/private/ — SHARED with
%                               engine.marginTensionUlt / engine.boltDesignLoad
%                               / engine.marginBearingUnderHead),
%                               engine.stiffness (wrapped in try/catch,
%                               not-assured branch only).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tDabjCase.m — boltYieldMarginMatchesDABJ
%                               ("rated" basis, assured branch, DABJ §9
%                               answer key, Eq. 15);
%                               tests/tStiffness.m — boltYieldRuptureBranch
%                               (not-assured branch, Eq. 16/17, hand-derived);
%                               tests/tBoltAllowable.m —
%                               ratedOnlyUsesSpecRatingEverywhere,
%                               derivedOnlyUsesAtFtuAndEq18,
%                               mixedBasisYieldUsesRatedUltimateNotAtFty,
%                               unavailableFtyNaNLeavesYieldNotEvaluatedButUltimateFine
%                               (Eq. 18 fallback + NotEvaluated paths, via
%                               the shared boltTensileAllowable resolution;
%                               all on gate-ASSURED fixtures, Eq. 15;
%                               their Nut member carries neither a rating
%                               nor an engagement length, so the system
%                               minimum is bolt-only there by construction);
%                               tests/tSystemAllowable.m — the system
%                               allowable's own modes, and the hand-derived
%                               member-governed Eq. 16/17 pin.
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 2, 2r,
%   plus the hand-derived member-governed system-yield row).

arguments
    joint       (1,1) model.Joint
    preload     (1,1) struct
    designLoads (1,1) struct
end

% THE FASTENING SYSTEM's yield allowable, not the bolt's alone —
% NASA-STD-5020B p30 defines Eq. 17's term as "the fastening SYSTEM'S
% allowable yield tensile load", and §4.4.2 p29 scopes the yield assessment
% to "all elements of the threaded fastening system". Exactly how
% engine.marginTensionUlt consumes engine.systemTensileAllowable in Eq. 6 /
% Eq. 10; the bolt-only resolution this row used before is still in there,
% as mode 1 of the minimum.
sys      = engine.systemTensileYieldAllowable(joint);
PtyAllow = sys.PtyAllow;

if isnan(PtyAllow)
    r = struct( ...
        "MS",                    NaN, ...
        "SeparationBeforeYield", false, ...
        "Method",                "NASA-STD-5020B Eq. 15/Eq. 16 (yield tension) — not evaluated", ...
        "Detail",                "Not evaluated: " + sys.Note + ".", ...
        "SystemAllowable",       PtyAllow);
    return
end

% ---- Separation-before-rupture/yield gate (NASA-STD-5020B Fig. 8) --------
% SHARED with engine.marginTensionUlt / engine.boltDesignLoad /
% engine.marginBearingUnderHead via the private helper
% separationBeforeRuptureGate — one evaluation, so this row can never
% disagree with the Tension-Ultimate row about which branch applies. The
% figure's decision tree is not itself specific to ultimate vs. yield (it
% is a statement about when the joint separates relative to the bolt
% carrying more than the applied load), so the same gate governs both.
gate = separationBeforeRuptureGate(joint, preload);
if ~gate.Assessed
    r = struct( ...
        "MS",                    NaN, ...
        "SeparationBeforeYield", false, ...
        "Method",                "NASA-STD-5020B Eq. 15/Eq. 16 (yield tension) — not evaluated", ...
        "Detail",                gate.Trace, ...
        "SystemAllowable",       PtyAllow);
    return
end
assured = gate.Assured;
n       = joint.LoadingPlaneFactor;

if assured
    % NASA-STD-5020B Eq. 15 — MS = Pty_allow / (FF*FSy*PtL) - 1
    MS = PtyAllow / designLoads.Pty - 1;
    Method = "NASA-STD-5020B Eq. 15 (yield tension, separation before yield)";
    Detail = gate.Trace + " -> Eq. 15.";
else
    try
        s   = engine.stiffness(joint);   % errors for threaded-in / missing geometry
        phi = s.Phi;                     % NASA-STD-5020B Eq. 9 — phi = kb/(kb + kc)
        % NASA-STD-5020B Eq. 17 — P'ty = (1/(n*phi))*(Pty_allow - Pp_max)
        Pprime = (PtyAllow - preload.PpMax) / (n * phi);
        % NASA-STD-5020B Eq. 16 — MS = P'ty / (FF*FSy*PtL) - 1
        MS = Pprime / designLoads.Pty - 1;
        Method = "NASA-STD-5020B Eq. 16 (yield tension, yield before separation)";
        Detail = gate.Trace + string(sprintf( ...
            ". -> Eq. 17 (P'ty = (1/(n*phi))*(Pty_allow - Pp_max)) then Eq. 16, with phi = %.4g (NASA-STD-5020B Eq. 9), n = %.2f.", ...
            phi, n));
    catch stiffErr
        % Stiffness unavailable (threaded-in configuration or missing
        % frustum geometry) — report NotEvaluated, do not crash analyze
        % (matches engine.marginTensionUlt's identical handling).
        MS = NaN;
        Method = "NASA-STD-5020B Eq. 16 (yield tension, yield before separation) — stiffness geometry required";
        Detail = gate.Trace + ...
            ". Eq. 17 needs phi from engine.stiffness, which could not run: " + ...
            string(stiffErr.message);
    end
end

r = struct( ...
    "MS",                    MS, ...
    "SeparationBeforeYield", assured, ...
    "Method",                Method, ...
    "Detail",                Detail + " " + sys.Note + ".", ...
    "SystemAllowable",       PtyAllow);
end
