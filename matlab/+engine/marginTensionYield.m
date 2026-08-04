function r = marginTensionYield(joint, preload, designLoads)
%MARGINTENSIONYIELD  Bolt yield-tension margin with separation-before-rupture gate.
%   r = engine.marginTensionYield(joint, preload, designLoads) evaluates the
%   SAME NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) separation-before-rupture
%   decision tree as engine.marginTensionUlt (via the shared private helper
%   separationBeforeRuptureGate — one evaluation, so the yield row can
%   never disagree with the Tension-Ultimate row about which branch
%   applies), then computes the bolt yield-tension margin of safety.
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
%   Pty_allow resolution (shared with engine.systemTensileAllowable /
%   engine.marginTensionUlt / engine.marginInteraction via the private
%   helper boltTensileAllowable, so all four sites agree):
%     "rated"   — joint.BoltRatedYieldLoad, when set (not NaN).
%     "derived" — NASA-STD-5020B Eq. 18, applied when the rating is unset:
%           Pty_allow = (Fty / Ftu) * Ptu_allow
%       introduced by: "The allowable yield tensile load can be estimated
%       using the equation below when a value is not explicitly defined in
%       the corresponding fastener specification or relevant test data is
%       unavailable" — exactly this situation. Ptu_allow here is the BOLT's
%       own ultimate allowable ACTUALLY IN USE — joint.BoltRatedUltimateLoad
%       when set, else the derived Ptu_allow = At*Ftu (a derived
%       convention per NASA-STD-5020B §4.4.2, NOT At*Fty directly — see
%       boltTensileAllowable's header for why the two forms coincide only
%       when the ultimate itself is At*Ftu).
%
%   NotEvaluated (MS = NaN) when NEITHER basis can be formed for the yield
%   allowable — no rating AND the Eq. 18 fallback is missing an input
%   (Ptu_allow itself unassessable, or BoltMaterial.Fty / Ftu is NaN) — or,
%   on the not-assured branch only, when Eq. 17 needs phi from
%   engine.stiffness and it cannot run. Reason names the specific missing
%   input in Detail; never throws.
%
%   Returned struct fields:
%       MS      margin of safety (double; NaN = not evaluated)
%       SeparationBeforeYield logical: gate result (mirrors
%               marginTensionUlt.SeparationBeforeRupture; the SAME gate)
%       Method  string: governing equation + basis
%       Detail  string: the gate trace, the allowable used, its basis, and
%               the arithmetic (or the not-evaluated reason)
%
%   Call graph:
%       Precedents (calls)      boltTensileAllowable (private helper,
%                               +engine/private/ — a leaf, model only),
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
%                               all on gate-ASSURED fixtures, Eq. 15).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 2, 2r).

arguments
    joint       (1,1) model.Joint
    preload     (1,1) struct
    designLoads (1,1) struct
end

bt = boltTensileAllowable(joint);   % shared bolt-allowable resolution

if ~bt.Yld.Assessed
    r = struct( ...
        "MS",                    NaN, ...
        "SeparationBeforeYield", false, ...
        "Method",                "NASA-STD-5020B Eq. 15/Eq. 16 (bolt yield) — not evaluated", ...
        "Detail",                "Not evaluated: " + bt.Yld.Reason + ".");
    return
end

PtyAllow = bt.Yld.Value;

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
        "Method",                "NASA-STD-5020B Eq. 15/Eq. 16 (bolt yield) — not evaluated", ...
        "Detail",                gate.Trace);
    return
end
assured = gate.Assured;
n       = joint.LoadingPlaneFactor;

if assured
    % NASA-STD-5020B Eq. 15 — MS = Pty_allow / (FF*FSy*PtL) - 1
    MS = PtyAllow / designLoads.Pty - 1;
    Method = "NASA-STD-5020B Eq. 15 (bolt yield, separation before yield)";
    Detail = gate.Trace + " -> Eq. 15.";
else
    try
        s   = engine.stiffness(joint);   % errors for threaded-in / missing geometry
        phi = s.Phi;                     % NASA-STD-5020B Eq. 9 — phi = kb/(kb + kc)
        % NASA-STD-5020B Eq. 17 — P'ty = (1/(n*phi))*(Pty_allow - Pp_max)
        Pprime = (PtyAllow - preload.PpMax) / (n * phi);
        % NASA-STD-5020B Eq. 16 — MS = P'ty / (FF*FSy*PtL) - 1
        MS = Pprime / designLoads.Pty - 1;
        Method = "NASA-STD-5020B Eq. 16 (bolt yield, yield before separation)";
        Detail = gate.Trace + string(sprintf( ...
            ". -> Eq. 17 (P'ty = (1/(n*phi))*(Pty_allow - Pp_max)) then Eq. 16, with phi = %.4g (NASA-STD-5020B Eq. 9), n = %.2f.", ...
            phi, n));
    catch stiffErr
        % Stiffness unavailable (threaded-in configuration or missing
        % frustum geometry) — report NotEvaluated, do not crash analyze
        % (matches engine.marginTensionUlt's identical handling).
        MS = NaN;
        Method = "NASA-STD-5020B Eq. 16 (bolt yield, yield before separation) — stiffness geometry required";
        Detail = gate.Trace + ...
            ". Eq. 17 needs phi from engine.stiffness, which could not run: " + ...
            string(stiffErr.message);
    end
end

r = struct( ...
    "MS",                    MS, ...
    "SeparationBeforeYield", assured, ...
    "Method",                Method, ...
    "Detail",                Detail + " " + bt.Yld.Note + ".");
end
