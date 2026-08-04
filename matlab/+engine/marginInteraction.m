function r = marginInteraction(joint, designLoads)
%MARGININTERACTION  Combined tension-shear interaction check (NASA-STD-5020B Eq. 20-23).
%   r = engine.marginInteraction(joint, designLoads) evaluates the
%   tension-shear interaction CRITERION for one joint at the design loads.
%   designLoads is the struct from engine.designLoads. All loads in lbf
%   (see UNITS.md).
%
%   NASA-STD-5020B states Eq. 20-23 as a PASS/FAIL CRITERION, not a margin
%   equation — the standard's own wording is that satisfying either of a
%   pair of these equations "is acceptable"; it never defines a margin of
%   safety for this check. This function therefore reports the interaction
%   RATIO R (the left-hand side of the criterion, evaluated at the design
%   loads) and Pass = (R <= 1) — NOT a margin of safety. (An earlier
%   version of this function solved for a load-scale factor a and reported
%   MS = a - 1; that "solve-for-a" reading is a derived convention layered
%   on top of the standard, not what 5020B itself defines, so it is no
%   longer the reported result — see the SECONDARY FIELD "a" note below
%   for why it is kept at all.)
%
%   Load ratios at the design loads:
%       Rt = Ptu / Ptu_allow          (Ptu_allow = the BOLT's own ultimate
%                                      allowable — joint.BoltRatedUltimateLoad
%                                      when set, else a derived Ptu_allow =
%                                      At*Ftu; see boltTensileAllowable)
%       Rs = Psu / Psu_allow          (Psu_allow from engine.marginShearUlt,
%                                      reused so both checks share one allowable)
%
%   The criterion (fbu = 0 — no bending term modeled, see the
%   NO-BENDING-TERM note below):
%       R = Rt^et + Rs^es,     Pass iff R <= 1
%   with exponents by shear-plane condition:
%       BodyInShear    — et = 1.5, es = 2.5 (NASA-STD-5020B Eq. 20/21;
%                        validated against DABJ §9)
%       ThreadsInShear — et = 2.0, es = 1.2 (NASA-STD-5020B Eq. 22/23;
%                        hand-derived, tests/tDabjCase.m — DABJ §9 has no
%                        threads-in-shear example). Exponents SWAPPED
%                        relative to BodyInShear (tension goes UP, shear
%                        goes DOWN) per NASA-STD-5020B's own explanation:
%                        "Tensile and shear stresses peak at the same
%                        cross section when the threads are in the shear
%                        plane; when the full diameter body is in the
%                        shear plane, the tensile and shear stresses do
%                        not peak at the same cross section."
%   R is evaluated DIRECTLY — Rt, Rs >= 0 always (loads and allowables are
%   both nonnegative), so Rt^et and Rs^es are ordinary real powers with no
%   root-find, no bracket, and no monotonicity argument needed for R
%   itself (unlike the secondary field "a" below).
%
%   NO BENDING TERM: this function computes only Rt (axial) and Rs (shear)
%   — there is no bolt-bending contribution (fbu) anywhere in R, for
%   either shear-plane condition. This is not an oversight local to this
%   file: engine.resolveForces computes a per-element Bending moment (RSS
%   of the transverse moments) but documents it as "informational — the
%   LoadCase carries no bending field", and engine.loadCaseFromForces
%   discards that value when building the model.LoadCase that ultimately
%   feeds designLoads. model.LoadCase and engine.designLoads carry no
%   bending field/design-load at all. So Eq. 20/22 and Eq. 21/23 all
%   reduce to their fbu = 0 form: R = Rt^et + Rs^es exactly — Eq. 20 and
%   Eq. 21 already coincide at fbu = 0 (both reduce to Rt^1.5 + Rs^2.5,
%   which is why the BodyInShear Method string below cites "Eq. 20/21" as
%   one pair), and Eq. 22/Eq. 23 coincide the same way for ThreadsInShear.
%   This is a documented model gap, not something this function invents a
%   number for — see the module header of engine.resolveForces /
%   engine.Contents for the fuller account.
%
%   SECONDARY, INFORMATIONAL field "a": the load-scale factor solving
%   (a*Rt)^et + (a*Rs)^es = 1 — "how far could BOTH design loads scale,
%   together, before the envelope is reached." It is NOT a margin of
%   safety and NOT this check's result (R and Pass are); it is kept only
%   because it answers a genuinely different, useful question than R
%   does. a >= 1 iff R <= 1 (both encode the same pass/fail direction:
%   g(1) = R - 1, and g is strictly increasing for a > 0 for ANY positive
%   exponent pair with Rt, Rs >= 0 not both zero — g'(a) =
%   et*Rt*(a*Rt)^(et-1) + es*Rs*(a*Rs)^(es-1), a sum of nonnegative terms
%   strictly positive whenever a > 0 and at least one of Rt, Rs is
%   nonzero — so g(1) <= 0 iff the unique root a* >= 1, i.e. Pass iff
%   a >= 1). fzero solves it on a positive bracket [0, hi] so it never
%   evaluates a < 0, where a non-integer power of a negative base is
%   complex and aborts the search; Rt = Rs = 0 (no applied load at all) is
%   special-cased directly to a = Inf, since g(a) = -1 for every finite a
%   in that case (R is unaffected — R = 0 there regardless, needing no
%   special case).
%
%   Returned struct fields:
%       R       double — the interaction ratio, Rt^et + Rs^es (NaN = not
%               evaluated)
%       Pass    logical — R <= 1 (the Eq. 20-23 criterion). Only meaningful
%               when R is not NaN — check isnan(R) first to distinguish
%               "not evaluated" from a genuine fail.
%       a       double — SECONDARY, informational load-scale factor (see
%               above). NOT a margin of safety; NaN if not evaluated.
%       Method  string: governing equation + exponents
%       Detail  string: R's value and pass/fail, the bolt ultimate
%               allowable's basis (rated/derived) and arithmetic, or the
%               not-evaluated reason
%
%   Call graph:
%       Precedents (calls)      engine.marginShearUlt (reused
%                               ShearAllowable — see the cross-file note
%                               above), boltTensileAllowable (private).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tDabjCase.m —
%                               interactionMarginMatchesDABJ (DABJ §9
%                               body-in-shear R/a pin),
%                               threadsInShearInteractionHandDerived,
%                               interactionExponentsDifferFromBodyInShear,
%                               threadsInShearUsesMinorAreaForShearAllowable;
%                               tests/tBoltAllowable.m —
%                               ratedOnlyUsesSpecRatingEverywhere,
%                               derivedOnlyUsesAtFtuAndEq18,
%                               mixedBasisYieldUsesRatedUltimateNotAtFty,
%                               unavailableAtNaNIsNotEvaluatedNotThrown,
%                               unavailableFtuNaNIsNotEvaluatedNotThrown,
%                               unavailableFtyNaNLeavesYieldNotEvaluatedButUltimateFine;
%                               tests/tBulk.m —
%                               bulkRunsTemplateJointWithoutCrashing,
%                               bulkPatternIdSplitsAndNfCheck,
%                               bulkFailingInteractionVisibleButNeverGoverns
%                               (direct cross-checks against the bulk
%                               table's InteractionR column);
%                               tests/tWorkbook.m —
%                               workbookRunsFreshTemplateWithoutCrashing
%                               (direct cross-check); tests/tExport.m —
%                               runBulkEndToEnd (structural only — asserts
%                               the InteractionR column exists, does not
%                               pin a value against this function
%                               directly).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, rows 13
%   and 13t).

arguments
    joint       (1,1) model.Joint
    designLoads (1,1) struct
end

% DELIBERATELY the BOLT's own allowable, NOT the NASA-STD-5020B §4.4.1
% fastening-system allowable (engine.systemTensileAllowable) that
% engine.marginTensionUlt now uses. The Eq. 20-23 interaction envelope and
% its shear-plane-dependent exponents describe combined tension+shear
% failure OF THE FASTENER; 5020B gives no interaction envelope for
% nut-stripping / insert pull-out / parent-thread modes — those members
% carry the axial bolt load but not the joint shear, and each is checked
% on its own Margins row (marginNutStrength / marginInsert /
% marginTappedParentThread). Folding a member-governed system allowable
% into a bolt interaction envelope would mix failure modes across
% equations, so the substitution is DEFERRED pending a governing
% interpretation.
%
% Ptu_allow uses joint.BoltRatedUltimateLoad when set, else a derived
% Ptu_allow = At*Ftu (a derived convention per NASA-STD-5020B §4.4.2, not a
% numbered equation — boltTensileAllowable, shared with
% engine.systemTensileAllowable / engine.marginTensionUlt /
% engine.marginTensionYield so all four sites agree). NotEvaluated (R = NaN,
% no throw) only when neither basis is available.
bt = boltTensileAllowable(joint);
if ~bt.Ult.Assessed
    r = struct("R", NaN, "Pass", false, "a", NaN, ...
        "Method", "NASA-STD-5020B Eq. 20-23 — not evaluated", ...
        "Detail", "Not evaluated: " + bt.Ult.Reason + ".");
    return
end
PtuAllow = bt.Ult.Value;

switch joint.ShearPlane
    case model.ShearPlaneCondition.BodyInShear
        % NASA-STD-5020B Eq. 20/21 (body in shear, fbu = 0 -- see the
        % NO-BENDING-TERM note above) -- criterion Rt^1.5 + Rs^2.5 <= 1
        et = 1.5;                               % tension exponent
        es = 2.5;                               % shear exponent
        methodLabel = "NASA-STD-5020B Eq. 20/21 (body in shear, exp 1.5/2.5), R <= 1";
    case model.ShearPlaneCondition.ThreadsInShear
        % NASA-STD-5020B Eq. 22/23 (threads in shear, fbu = 0 -- see the
        % NO-BENDING-TERM note above) -- criterion Rt^2.0 + Rs^1.2 <= 1.
        % Exponents SWAPPED from body-in-shear (tension 1.5->2.0, shear
        % 2.5->1.2) per NASA-STD-5020B's own explanation quoted above: the
        % tensile and shear stresses peak at the SAME cross section when
        % the threads are in the shear plane, unlike the body-in-shear case.
        et = 2.0;                               % tension exponent
        es = 1.2;                               % shear exponent
        methodLabel = "NASA-STD-5020B Eq. 22/23 (threads in shear, exp 2.0/1.2), R <= 1";
    otherwise
        error("engine:marginInteraction:unknownShearPlane", ...
            "Unsupported shear-plane condition: %s", string(joint.ShearPlane));
end

shearUlt = engine.marginShearUlt(joint, designLoads);   % reuse its allowable
% NASA-STD-5020B Eq. 20-23 load ratios — Rt = Ptu / Ptu_allow
Rt = designLoads.Ptu / PtuAllow;
% NASA-STD-5020B Eq. 20-23 load ratios — Rs = Psu / Psu_allow
Rs = designLoads.Psu / shearUlt.ShearAllowable;

% NASA-STD-5020B Eq. 20-23 criterion — R = Rt^et + Rs^es, Pass iff R <= 1.
% Direct evaluation: Rt, Rs >= 0 always, so no root-find is needed for R.
R = Rt^et + Rs^es;
Pass = R <= 1;

% ---- Secondary, informational load-scale factor "a" (NOT the result) ----
% (a*Rt)^et + (a*Rs)^es = 1. g(0) = -1 and g is strictly increasing for
% a > 0 (see the module-header argument), so the root is unique. Solve on
% a POSITIVE bracket [0, hi] so fzero never evaluates a < 0 (a
% non-integer power of a negative base is complex and aborts the search).
g = @(a) (a*Rt)^et + (a*Rs)^es - 1;
if Rt <= 0 && Rs <= 0
    a = Inf;                          % no applied load -> loads can scale forever
else
    hi = 1;
    while g(hi) < 0 && hi < 1e12
        hi = 2 * hi;                  % expand until g(hi) > 0 brackets the root
    end
    a = fzero(g, [0, hi]);
end

if Pass
    passText = "satisfies";
else
    passText = "does NOT satisfy";
end
detail = string(sprintf("R = %.6f %s the NASA-STD-5020B Eq. 20-23 criterion (R <= 1); a = %.6f (informational load-scale factor, not a margin); bolt %s.", ...
    R, passText, a, bt.Ult.Note));

r = struct( ...
    "R",      R, ...
    "Pass",   Pass, ...
    "a",      a, ...
    "Method", methodLabel, ...
    "Detail", detail);
end
