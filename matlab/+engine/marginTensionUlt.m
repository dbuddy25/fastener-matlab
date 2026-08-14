function r = marginTensionUlt(joint, preload, designLoads)
%MARGINTENSIONULT  Ultimate-tension margin with separation-before-rupture gate.
%   r = engine.marginTensionUlt(joint, preload, designLoads) evaluates the
%   NASA-STD-5020B Figure 8 (DABJ Fig. 9-9) separation-before-rupture
%   decision tree, then computes the bolt ultimate-tension margin of
%   safety. preload is the struct from engine.preload; designLoads is the
%   struct from engine.designLoads. All loads in lbf (see UNITS.md).
%
%   Returned struct fields:
%       MS                      margin of safety (double; NaN only if the
%                               rupture path needs stiffness geometry the
%                               joint does not carry — see below)
%       SeparationBeforeRupture logical: gate result
%       Decision                string trace of the gate evaluation + the
%                               system-allowable trace (governing mode;
%                               incomplete-assessment warning when a mode
%                               could not be assessed)
%       Method                  string: governing equation
%       SystemAllowable         the engine.systemTensileAllowable struct
%                               actually used (PtuAllow, GoverningMode,
%                               Modes, Unassessed, Complete, Note)
%
%   Separation-before-rupture is ASSURED when ALL of (Fig. 8 / Fig. 9-9):
%     1. Ec > Eb/3 — the softest clamped-member modulus (min E over the
%        FlangeStack, conservative) exceeds one third of the bolt modulus.
%     2. PpMax <= 0.75*Ptu_allow — max in-service preload is at or below
%        the low end of the intermediate band (figure prints "<=",
%        inclusive). Preloads in (0.75, 0.85]*Ptu_allow (and above)
%        conservatively assume rupture (gate NOT assured).
%     3. LoadingPlaneFactor n <= 0.9.
%     4. Edge distance e/D >= 1.5 (min FlangeLayer.EdgeDistance over the
%        stack, over the bolt diameter) — a precondition on the Fig. 8
%        conclusion (NASA-STD-5020B Appendix A.5), not a separate
%        requirement. ASSUMED satisfied when no layer records
%        EdgeDistance; tested (and can FAIL) when at least one layer does.
%        Decision always says which — see separationBeforeRuptureGate.
%
%   If assured:  MS = Ptu_allow / designLoads.Ptu - 1   (NASA-STD-5020B Eq. 6 —
%   the bolt only sees the external design load). If NOT assured, rupture
%   governs: the bolt carries the max preload PLUS its share of the applied
%   load, so the margin uses the joint-stiffness factor phi from
%   engine.stiffness (NASA-STD-5020B Eq. 9) and the loading-plane factor n:
%       P'tu = (Ptu_allow - Pp_max)/(n·phi)          (Eq. 10)
%       MS   = P'tu/(FF·FSu·PtL) - 1                  (Eq. 7)
%   TWO EQUATIONS, AND THE MARGIN IS Eq. 7. This branch was labelled
%   "Eq. 10" throughout until the 2026-08-13 audit. Eq. 10 supplies P'tu;
%   the margin itself is Eq. 7, and Appendix A.6 p65 says so in as many
%   words: "If separation would occur before rupture, Eq. 10 does not
%   apply and the margin of safety is given by Eq. 6... If rupture would
%   occur before separation, the margin of safety is given by Eq. 7." The
%   Method string is user-visible — it reaches the Results grid, the PDF
%   and every export — so it now names both, margin first. The yield side
%   already had this right (Eq. 17 for P'ty, Eq. 16 for the MS).
%
%   If engine.stiffness cannot run (threaded-in configuration or missing
%   frustum geometry), the check reports MS = NaN with the reason in
%   Decision rather than crashing the analysis.
%
%   NASA-STD-5020B Eq. 11 is NOT a yield-side form — this header used to
%   say it was. Eq. 11 is P'sep = Pp_max/(1 - n·phi), the ULTIMATE-side
%   linear projection of the load that causes separation (p28), which the
%   standard pairs with Eq. 10 to decide the branch: "If P'sep is less
%   than P'tu, linear theory predicts that separation would occur before
%   rupture." The tool takes that decision from the Fig. 8 gate instead
%   and does not compute P'sep. The mislabel most likely came from
%   Figure 8's own outcome boxes, which read "Perform analysis per
%   Eq. 11" on the rupture path. The yield-side rupture form is Eq. 17 —
%   see engine.marginTensionYield.
%
%   Ptu_allow is the FASTENING SYSTEM's allowable ultimate tensile load
%   (NASA-STD-5020B §4.4.1: "Ptu-allow is the allowable ultimate load for
%   the fastening system"), from engine.systemTensileAllowable — the
%   minimum over bolt tension and the internal-thread member's mode (nut
%   thread shear / rating, insert pull-out, or tapped-hole parent thread).
%   It feeds the Fig. 8 preload gate AND both margin equations, so a
%   threaded member weaker than the bolt correctly (a) lowers the
%   0.75·Ptu_allow gate threshold and (b) lowers P'tu on the rupture
%   branch. When a member mode cannot be assessed (missing engagement /
%   strength data), the system minimum is taken over an INCOMPLETE set and
%   is optimistic — Decision says so plainly. The bolt-tension mode itself
%   uses joint.BoltRatedUltimateLoad when set, else a derived
%   Ptu_allow = At*Ftu (a derived convention, not a numbered 5020B
%   equation — see the private helper boltTensileAllowable, shared with
%   engine.marginTensionYield and engine.marginInteraction); Decision/the
%   system Note name which basis was used. This function is NotEvaluated
%   (MS = NaN, no throw) only if NEITHER the bolt mode NOR any
%   internal-thread mode can be assessed at all.
%
%   The Fig. 8 gate itself is computed by the private helper
%   separationBeforeRuptureGate(joint, preload) — the SINGLE
%   implementation, shared with engine.boltDesignLoad, which uses the same
%   gate to choose the Phase 3.3 thread-check (bolt-thread shear, nut
%   strength, insert pull-out, tapped-hole parent thread) design-load form.
%   One evaluation means this row and those four rows can never disagree
%   about which branch applies.
%
%   Call graph:
%       Precedents (calls)      engine.stiffness (wrapped in try/catch,
%                               rupture branch only), separationBeforeRuptureGate
%                               (private helper, +engine/private/).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tDabjCase.m — tensionUltMarginMatchesDABJ
%                               (assured branch, Eq. 6, DABJ §9 answer key);
%                               tests/tStiffness.m — tensionRuptureBranch
%                               (rupture branch, Eq. 7 via Eq. 10, hand-derived);
%                               tests/tSystemAllowable.m — weakNutFlipsFig8Gate
%                               (system-vs-bolt Ptu_allow flips the gate
%                               branch), incompleteAssessmentFlagged
%                               (INCOMPLETE system minimum surfaces in Decision).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, rows 1, 1r, 12).

%   WHY THIS ROW THROWS ON AN EMPTY FlangeStack, alone among the fifteen.
%   Every other margin degrades to NotEvaluated. Here the empty stack means
%   no grip, and grip is upstream of stiffness, preload and the Fig. 8 gate
%   alike — there is no partial answer to give, only a cascade of NaN that
%   would read as "not applicable" rather than "not configured".
%
%   Reviewed 2026-08-14 and left as a throw, because neither entry path can
%   reach it: gui2.JointConfigPage's Analyze gate (missingRequired) lists
%   "A flange layer thickness" among the selections Analyze cannot run
%   without, and engine.analyzeBulk catches per row and puts the message in
%   that row's Error column. Dan: "user will always fill the flange stack."
%   A single-joint caller driving the engine headless can still hit it, and
%   should — the error names the missing input.
%
arguments
    joint       (1,1) model.Joint
    preload     (1,1) struct
    designLoads (1,1) struct
end

% ---- Ptu_allow: the FASTENING SYSTEM's allowable (NASA-STD-5020B §4.4.1) --
% §4.4.1: "Ptu-allow is the allowable ultimate load for the fastening
% system" — Ptu_allow = min over the system's tensile failure modes (bolt
% tension; nut thread shear / rating; insert pull-out; tapped-hole parent
% thread), via engine.systemTensileAllowable. The bolt-tension mode uses
% joint.BoltRatedUltimateLoad when set, else falls back to a derived
% Ptu_allow = At*Ftu (boltTensileAllowable) — no throw for an unset rating
% as long as the derived path (or a member mode) is assessable.
if isempty(joint.FlangeStack)
    error("engine:marginTensionUlt:emptyFlangeStack", ...
        "Joint.FlangeStack is empty; the member modulus Ec is needed for the separation-before-rupture check.");
end

% ---- Separation-before-rupture gate (NASA-STD-5020B Fig. 8 / DABJ Fig. 9-9) -----
% The FlangeStack precondition above is satisfied, so the gate's own
% matching check always passes here; it may still come back NOT Assessed
% if NO tensile mode of the system (bolt included) can be assessed at all
% (e.g. no rating AND no At/Ftu to derive one, AND no member mode either).
gate = separationBeforeRuptureGate(joint, preload);
if ~gate.Assessed
    r = struct( ...
        "MS",                      NaN, ...
        "SeparationBeforeRupture", false, ...
        "Decision",                gate.Trace, ...
        "Method",                  "NASA-STD-5020B Eq. 6/Eq. 7 (separation before rupture) — not evaluated", ...
        "SystemAllowable",         gate.SystemAllowable, ...
        "Gate",                    gateOut(false, false, gate.Trace, ...
                                       "not evaluated", NaN, NaN));
    return
end
sys      = gate.SystemAllowable;
PtuAllow = gate.PtuAllow;   % system minimum (== the bolt's rated/derived load when the bolt governs)
assured  = gate.Assured;
n        = joint.LoadingPlaneFactor;

% ---- Margin ------------------------------------------------------------
% Phi and N are recorded ONLY on the Eq. 10 branch and stay NaN on the
% others -- they are the parameters of that equation, not of the check, and
% a consumer must be able to tell "Eq. 6 governed" from "Eq. 10 governed
% with these numbers" without parsing a sentence.
phiUsed = NaN;
nUsed   = NaN;

if assured
    % NASA-STD-5020B Eq. 6 — MS = Ptu_allow / Ptu - 1
    MS = PtuAllow / designLoads.Ptu - 1;
    Method = "NASA-STD-5020B Eq. 6 (separation before rupture)";
    Decision = gate.Trace + " -> Eq. 6.";
    eqRan = "NASA-STD-5020B Eq. 6";
else
    try
        s   = engine.stiffness(joint);   % errors for threaded-in / missing geometry
        phi = s.Phi;                     % NASA-STD-5020B Eq. 9 — phi = kb/(kb + kc)
        % NASA-STD-5020B Eq. 10 — P'tu = (Ptu_allow - Pp_max)/(n·phi);
        % MS = P'tu/Ptu - 1 (bolt carries the preload plus n·phi of the load)
        Pprime = (PtuAllow - preload.PpMax) / (n * phi);
        MS = Pprime / designLoads.Ptu - 1;
        Method = "NASA-STD-5020B Eq. 7 (rupture — bolt sees preload + n·phi·load), with P'tu per Eq. 10";
        Decision = gate.Trace + string(sprintf( ...
            ". -> Eq. 10 for P'tu then Eq. 7, with phi = %.4g (NASA-STD-5020B Eq. 9), n = %.2f.", phi, n));
        eqRan   = "NASA-STD-5020B Eq. 7 (P'tu per Eq. 10)";
        phiUsed = phi;
        nUsed   = n;
    catch stiffErr
        % Stiffness unavailable (threaded-in configuration or missing
        % frustum geometry) — report NotEvaluated, do not crash analyze.
        MS = NaN;
        Method = "NASA-STD-5020B Eq. 7 (rupture, P'tu per Eq. 10) — stiffness geometry required";
        Decision = gate.Trace + ...
            ". Eq. 10 needs phi from engine.stiffness, which could not run: " + ...
            string(stiffErr.message);
        eqRan = "NASA-STD-5020B Eq. 7 (P'tu per Eq. 10, could not run)";
    end
end

% Surface the system-allowable trace (NASA-STD-5020B §4.4.1): which mode
% set Ptu_allow, and — critically — whether any applicable mode could NOT
% be assessed (the minimum is then over an incomplete set and optimistic).
Decision = Decision + " Ptu_allow: " + sys.Note + ".";

r = struct( ...
    "MS",                      MS, ...
    "SeparationBeforeRupture", assured, ...
    "Decision",                Decision, ...
    "Method",                  Method, ...
    "SystemAllowable",         sys, ...
    "Gate",                    gateOut(true, assured, gate.Trace, eqRan, ...
                                   phiUsed, nUsed));
end

% ---- Local helpers --------------------------------------------------------
function g = gateOut(assessed, assured, trace, equation, phi, n)
%GATEOUT  The Fig. 8 outcome as SEPARATE FIELDS rather than one sentence.
%   Decision (above) remains the human sentence, and every existing
%   consumer keeps reading it. This is the same information unglued:
%   Decision concatenates the gate trace, the equation that won, and the
%   Ptu_allow basis, so a view that wants to lay those out on three lines
%   -- or put the equation where equations belong and the decision where
%   decisions belong -- has to unpick prose it should never have been
%   handed. The structure existed here and was destroyed on the way out.
g = struct( ...
    "Assessed", assessed, ...
    "Assured",  assured, ...
    "Trace",    string(trace), ...
    "Equation", string(equation), ...
    "Phi",      phi, ...
    "N",        n);
end
