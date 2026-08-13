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
%   The criterion (NASA-STD-5020B Eq. 20 body / Eq. 22 threads):
%       R = Rs^es + (Rt + Rb)^et,     Pass iff R <= 1
%   with Rb = fbu/Ftu, the BENDING ratio, added to Rt INSIDE the tension
%   bracket before the exponent — not as a separate term. Rb = 0 exactly
%   when no bending moment is supplied, so the criterion collapses to the
%   historical R = Rt^et + Rs^es form bit for bit (see BENDING below)
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
%   BENDING (NASA-STD-5020B Eq. 20/22, §4.4.4). The bending term is
%   computed. It was absent end to end until this was built — the model
%   carried no moment, engine.loadCaseFromForces discarded the one
%   engine.resolveForces derived from the FE moments, and every criterion
%   collapsed to its fbu = 0 form.
%
%       fbu = 32*Mbu/(pi*d^3)      engine/private/boltBendingStress
%       Rb  = fbu / Ftu            Ftu = joint.BoltMaterial.Ftu
%
%   fbu is 5020B's "design ultimate bending stress based on linear-elastic
%   theory" — M*c/I on a circular section with c = d/2, I = pi*d^4/64 —
%   built from designLoads.Mbu (FSU*FFU*LoadCase.BoltBendingLimitMoment,
%   in-lbf). WHICH d is a DERIVED CONVENTION, not a 5020B relation: the
%   section follows the SHEAR PLANE, body diameter for BodyInShear and
%   minor diameter for ThreadsInShear, mirroring Eq. 12 vs Eq. 13 for the
%   shear allowable in these same criteria. See boltBendingStress's header
%   for why nominal D throughout would be unconservative exactly where
%   5020B says the tensile and shear stresses peak together.
%
%   ONLY Eq. 20 AND Eq. 22 ARE IMPLEMENTED. Eq. 21/23 add a separate
%   fbu/Fbu term crediting PLASTIC bending; Fbu (allowable flexural
%   stress) is not a field on model.Material, and 5020B states that
%   including the bending term in Eq. 20/22 "is considered to be
%   conservative" — so the reachable option is also the conservative one.
%   While fbu = 0 the two coincide and the Method string says "Eq. 20/21"
%   or "Eq. 22/23"; once bending is included it names the single equation
%   that actually ran.
%
%   NASA-STD-5020B §4.4.4 makes the fbu = 0 omission CONDITIONAL, not an
%   unconditional simplification: "if shear is not transferred across
%   gaps or non load carrying spacers, or if interference or close
%   tolerance fits are used, then typically there is no need to account
%   for bolt bending caused by the shear loading. However, if the shear
%   is transferred across gaps or non load carrying spacers, or if there
%   are clearances between the bolt and joint, interaction of loads,
%   including non-negligible bending, should be considered." That term
%   is now computed (see BENDING above), and joint.ShearTransferCondition
%   (model.ShearTransferCondition) turns the exemption from a silent,
%   unconditional assumption into an explicit, recorded determination:
%       NotDeclared                  — default. R computed exactly as the
%                                      fbu=0 form above; Method/Detail say
%                                      the §4.4.4 exemption is ASSUMED, not
%                                      verified, and name the property.
%       CloseToleranceOrInterference — analyst has confirmed §4.4.4's
%                                      exemption condition holds. R
%                                      computed identically to NotDeclared
%                                      (same numeric result); Method/Detail
%                                      say the exemption is VERIFIED.
%       ClearanceOrGapped            — analyst has confirmed §4.4.4's
%                                      exemption does NOT apply, so bending
%                                      MUST be accounted for. With a moment
%                                      supplied the criterion is evaluated
%                                      with the Rb term (this is the case
%                                      the enum was created to make
%                                      reachable). With NO moment it stays
%                                      R = NaN, Pass = false, NO throw —
%                                      the analyst has said bending matters
%                                      and given nothing to compute it
%                                      from, so there is still no honest
%                                      answer.
%
%   WHAT A SUPPLIED MOMENT DOES, by determination — a bulk run resolves
%   one from the FE moments for EVERY element, so this matters:
%       NotDeclared   — USED, conservatively. Nobody assessed the joint
%                       and the model reports a moment; dropping it
%                       silently is the quiet non-conservatism this enum
%                       exists to prevent.
%       CloseTolerance— IGNORED, and said so. The analyst has stated
%                       §4.4.4 does not require bending here. FE moments
%                       on a stiff connection are frequently an artefact
%                       of the idealisation rather than real bolt
%                       bending, and "exempt" is how that is recorded —
%                       using it anyway would make the determination a
%                       label rather than a setting. Bending.MomentIgnored
%                       flags it and the Detail names the value dropped.
%       ClearanceOrGapped — USED. That is the point of the declaration.
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
%               evaluated — either the bolt ultimate allowable is
%               unavailable, or joint.ShearTransferCondition is
%               ClearanceOrGapped, see the §4.4.4 note above)
%       Pass    logical — R <= 1 (the Eq. 20-23 criterion). Only meaningful
%               when R is not NaN — check isnan(R) first to distinguish
%               "not evaluated" from a genuine fail.
%       a       double — SECONDARY, informational load-scale factor (see
%               above). NOT a margin of safety; NaN if not evaluated.
%       Bending struct — the bending story as DATA, not prose: Included
%               (logical), Fbu (psi), Rb, Diameter (in), Basis
%               ("body"/"minor"/"none"), Condition (the §4.4.4
%               determination). Reaches the GUI as Result.Bending; a view
%               that had to parse Detail to find out whether bending was
%               included would eventually parse it wrong.
%       Method  string: governing equation + exponents, plus the §4.4.4
%               bolt-bending exemption's ASSUMED/VERIFIED/INCLUDED/
%               not-evaluated status
%       Detail  string: R's value and pass/fail, the bolt ultimate
%               allowable's basis (rated/derived) and arithmetic, the
%               §4.4.4 exemption determination (and which property to set
%               to change it), or the not-evaluated reason
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
%                               threadsInShearUsesMinorAreaForShearAllowable,
%                               shearTransferNotDeclaredReproducesTodayR,
%                               shearTransferVerifiedGivesSameRWithVerifiedWording,
%                               shearTransferClearanceOrGappedIsNotEvaluated,
%                               shearTransferClearanceOrGappedAnalyzeCompletes
%                               (the §4.4.4 ASSUMED/VERIFIED/not-evaluated
%                               trio, mirroring the Fig. 8 e/D trio in
%                               tests/tStiffness.m);
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
%   Validation status/coverage: see VALIDATION.md (Margin checks, rows 13,
%   13t, and 13g).

arguments
    joint       (1,1) model.Joint
    designLoads (1,1) struct
end

% NASA-STD-5020B §4.4.4 — "if the shear is transferred across gaps or non
% load carrying spacers, or if there are clearances between the bolt and
% joint, interaction of loads, including non-negligible bending, should be
% considered." This tool has no fbu term anywhere (see the NO-BENDING-TERM
% / §4.4.4 note above), so when the analyst has recorded that this
% configuration is exactly the one §4.4.4 flags, the Eq. 20-23 criterion
% cannot be evaluated conservatively -- NotEvaluated, no throw, checked
% BEFORE the bolt-allowable lookup below so the reason is never masked by
% an unrelated "allowable unavailable" message.
% Mbu READ DEFENSIVELY. engine.designLoads always emits it, but a bare
% designLoads struct is a legitimate and widely-used way to drive this
% function directly -- several tests build one to isolate the interaction
% envelope from the FS*FF chain. A struct written before bending existed
% has no Mbu field, and that means "no moment", not an error.
if isfield(designLoads, "Mbu")
    Mbu = designLoads.Mbu;
else
    Mbu = NaN;
end
bend = boltBendingStress(joint, Mbu);

% DOES THE DETERMINATION LET US USE THE MOMENT?
%   Exempt        — the analyst has stated §4.4.4 does not require bending
%                   here. A moment may still arrive (a bulk run resolves
%                   one from the FE moments for EVERY element, whatever
%                   the joint is), and it is deliberately NOT used: FE
%                   moments on a stiff connection are frequently an
%                   artefact of the idealisation rather than real bolt
%                   bending, and "exempt" is exactly how an analyst says
%                   so. Including it anyway would make the determination a
%                   label rather than a setting.
%   Required      — use it (that is the whole point of the declaration).
%   Not determined — USE IT, conservatively. Nobody has assessed the
%                   joint and the model is reporting a moment; silently
%                   dropping it there is precisely the quiet
%                   non-conservatism ShearTransferCondition exists to
%                   prevent. It is included and the Detail says it was
%                   included because nothing said otherwise.
exempt     = joint.ShearTransferCondition == ...
             model.ShearTransferCondition.CloseToleranceOrInterference;
useBending = bend.HasMoment && ~exempt;

% A ClearanceOrGapped joint is one the analyst has declared §4.4.4's
% exemption does NOT cover, so bending has to be accounted for. It now can
% be -- but only if a moment was actually supplied. With none, this is
% still the honest not-evaluated case it has always been: the analyst has
% said bending matters and given nothing to compute it from.
if joint.ShearTransferCondition == model.ShearTransferCondition.ClearanceOrGapped ...
        && ~bend.HasMoment
    r = bendingNotEvaluated( ...
        "Not evaluated: NASA-STD-5020B §4.4.4 requires bolt bending to be " + ...
        "considered for this configuration " + ...
        "(Joint.ShearTransferCondition = ClearanceOrGapped " + ...
        "-- shear transferred across a gap/non-load-carrying spacer, or " + ...
        "clearance between the bolt and joint), and no bending moment was " + ...
        "supplied. Set LoadCase.BoltBendingLimitMoment to evaluate the " + ...
        "criterion, or set Joint.ShearTransferCondition to " + ...
        "CloseToleranceOrInterference if the §4.4.4 exemption is verified true.", ...
        bend, joint.ShearTransferCondition);
    return
end

% A moment was supplied but the section it needs is not defined. Only
% fatal when the moment is actually going to be used -- an exempt joint
% does not need a section for a stress it will not compute.
if useBending && ~bend.Assessed
    r = bendingNotEvaluated("Not evaluated: " + bend.Reason + ".", bend, ...
        joint.ShearTransferCondition);
    return
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
% equations.
%
% NO LONGER DEFERRED — RULED 2026-08-13 (equation audit). This used to end
% "the substitution is DEFERRED pending a governing interpretation." The
% interpretation was taken, across all four sites where 5020B uses
% Ptu/Pty-allow, and this one lands on the BOLT. Three grounds, in
% increasing strength:
%
%   (1) §4.4.4 frames itself around the fastener — "When assessing the
%       strength OF THE FASTENER due to combined loading...", "For
%       FASTENERS under simultaneously applied tensile and shear loads..."
%       (p33) — and never re-invokes the fastening system or
%       cross-references §4.4.1's definition.
%   (2) The empirical basis is fastener rupture: "these criteria... are
%       based on tests of A-286 3/8-24 (NAS1956C14) FASTENERS performed at
%       NASA MSFC in 2010" (p33), and Psu_allow is unambiguously a bolt
%       cross-section quantity (Eq. 12/13).
%   (3) THE BRACKET STRUCTURE ITSELF, which is decisive. Eq. 20/22 sum the
%       tension and bending ratios inside ONE parenthesis:
%           (Ptu/Ptu_allow + fbu/Ftu)^k
%       fbu is a bending STRESS and Ftu an allowable STRESS on the bolt
%       cross-section. Adding Ptu/Ptu_allow to fbu/Ftu is mechanically
%       meaningful only if the first term is also an axial normal-stress
%       ratio at that same section — i.e. Ptu_allow ~ Ftu*A for the
%       governing bolt section, making the bracket (f_axial+f_bending)/Ftu
%       at one cross section. p34 confirms the cross-section frame:
%       "Tensile and shear stresses peak at the same cross section when
%       the threads are in the shear plane." A nut-strip or pull-out load
%       has no cross section; substituting it into that ratio is
%       dimensionally legal and mechanically meaningless.
%
% THE GAP THIS LEAVES IS REAL AND IS NOT A DEFECT IN THIS FUNCTION.
% 5020B provides NO interaction envelope for internally-threaded-part
% failure under combined load. When a nut or insert governs axially,
% Eq. 20-23 with bolt allowables genuinely does not check that member
% under simultaneous tension and shear — and neither does anything else in
% the standard. Substituting the system minimum into Rt would be
% conservative and cheap, but it is an ENGINEERING JUDGMENT, not a reading
% of 5020B, and doing it silently would redefine a cited equation's symbol
% — which this repo's traceability rule forbids. If that residual risk
% needs covering, add a SEPARATELY LABELLED supplementary check rather
% than changing this one.
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

% NASA-STD-5020B Eq. 20/22 bending ratio — Rb = fbu / Ftu, the term that
% sits INSIDE the tension bracket. Ftu is the bolt material's allowable
% ultimate tensile stress; the standard pairs fbu with Ftu (not with the
% rated allowable behind Rt) in Eq. 20 and Eq. 22 as printed.
Ftu = joint.BoltMaterial.Ftu;
if useBending && (~isfinite(Ftu) || Ftu <= 0)
    % Only fatal WITH a moment: with none, Rb is 0 and Ftu never matters.
    r = bendingNotEvaluated("Not evaluated: a bending moment was supplied " + ...
        "but the bolt material has no Ftu, so the NASA-STD-5020B Eq. 20/22 " + ...
        "fbu/Ftu term cannot be formed.", bend, joint.ShearTransferCondition);
    return
end
% Rb is EXACTLY zero with no moment, so a joint that supplies none
% reproduces its pre-bending R bit for bit -- that is what keeps every
% existing DABJ and bulk pin intact.
if useBending
    Rb = bend.Value / Ftu;
else
    Rb = 0;
end

% NASA-STD-5020B Eq. 20 (body) / Eq. 22 (threads) criterion —
%   (Psu/Psu_allow)^es + (Ptu/Ptu_allow + fbu/Ftu)^et <= 1
% i.e. R = Rs^es + (Rt + Rb)^et, Pass iff R <= 1. The bending ratio is
% added to the tension ratio INSIDE the bracket, before the exponent — not
% as a separate term. (A separate fbu/Fbu term is Eq. 21/23, the plastic-
% bending variants; Fbu is not in model.Material, and 5020B calls including
% bending in Eq. 20/22 the conservative choice.)
% Direct evaluation: Rt, Rs, Rb >= 0 always, so no root-find is needed.
R = Rs^es + (Rt + Rb)^et;
Pass = R <= 1;

% ---- Secondary, informational load-scale factor "a" (NOT the result) ----
% (a*Rt)^et + (a*Rs)^es = 1. g(0) = -1 and g is strictly increasing for
% a > 0 (see the module-header argument), so the root is unique. Solve on
% a POSITIVE bracket [0, hi] so fzero never evaluates a < 0 (a
% non-integer power of a negative base is complex and aborts the search).
% Rb scales WITH the loads: fbu is linear in the applied moment, so
% scaling the load set scales the bending stress by the same factor. It
% therefore rides inside the bracket exactly as it does in R above.
g = @(a) (a*Rs)^es + (a*(Rt + Rb))^et - 1;
if Rt <= 0 && Rs <= 0 && Rb <= 0
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

% NASA-STD-5020B §4.4.4 bolt-bending exemption note (see the module-header
% §4.4.4 note above; ClearanceOrGapped already returned NotEvaluated above,
% so only the two "compute exactly as today" branches reach here). Both
% branches produce the IDENTICAL numeric R, a — only the ASSUMED/VERIFIED
% wording differs, mirroring engine.private.separationBeforeRuptureGate's
% own e/D ASSUMED-vs-VERIFIED distinction.
if useBending
    % BENDING IS IN THE NUMBER. Eq. 21/23 are the plastic-bending variants
    % (a separate fbu/Fbu term) and are NOT what ran, so the label drops to
    % the single equation that did -- the paired "Eq. 20/21" wording is
    % only honest while fbu = 0 makes the two coincide.
    methodLabel = replace(methodLabel, "Eq. 20/21", "Eq. 20");
    methodLabel = replace(methodLabel, "Eq. 22/23", "Eq. 22");
    methodLabel = methodLabel + " -- §4.4.4 bending INCLUDED";
    bendingNote = string(sprintf( ...
        "§4.4.4 bolt bending INCLUDED: %s, Rb = fbu/Ftu = %.6f, added to Rt inside the tension bracket (%s)", ...
        bend.Note, Rb, conditionName(joint.ShearTransferCondition)));
else
    switch joint.ShearTransferCondition
        case model.ShearTransferCondition.CloseToleranceOrInterference
            bendingNote = "§4.4.4 bolt-bending exemption VERIFIED (fbu = 0; " + ...
                "Joint.ShearTransferCondition = CloseToleranceOrInterference)";
            if bend.HasMoment
                % Say it out loud. A supplied moment that vanishes without
                % comment is indistinguishable from one that was never read.
                bendingNote = bendingNote + string(sprintf( ...
                    " -- a bending moment WAS supplied (Mbu = %.4g in-lbf) and " + ...
                    "deliberately not used, because the exemption is recorded " + ...
                    "as verified", Mbu));
            end
            methodLabel = methodLabel + " -- §4.4.4 bending VERIFIED exempt";
        otherwise   % NotDeclared (the default)
            bendingNote = "§4.4.4 bolt-bending exemption ASSUMED, not confirmed " + ...
                "(fbu = 0; Joint.ShearTransferCondition = NotDeclared -- set it " + ...
                "to CloseToleranceOrInterference or ClearanceOrGapped to record " + ...
                "the determination, or supply LoadCase.BoltBendingLimitMoment " + ...
                "to include bending)";
            methodLabel = methodLabel + " -- §4.4.4 bending ASSUMED, not confirmed";
    end
end

detail = string(sprintf("R = %.6f %s the NASA-STD-5020B Eq. 20-23 criterion (R <= 1); a = %.6f (informational load-scale factor, not a margin); bolt %s. ", ...
    R, passText, a, bt.Ult.Note)) + bendingNote + ".";

r = struct( ...
    "R",       R, ...
    "Pass",    Pass, ...
    "a",       a, ...
    "Method",  methodLabel, ...
    "Detail",  detail, ...
    "Bending", bendingOut(bend, Rb, joint.ShearTransferCondition, useBending));
end

% ---- Local helpers --------------------------------------------------------
function r = bendingNotEvaluated(detail, bend, condition)
%BENDINGNOTEVALUATED  The NotEvaluated return, with the bending block intact.
%   One shape for all three bending-related not-evaluated exits, so a
%   caller never has to guess which fields a NaN result carries. The
%   condition is PASSED IN rather than assumed to be ClearanceOrGapped:
%   two of the three exits (no section, no Ftu) are reachable from any
%   determination, and a Bending block that misreported which one the
%   analyst recorded would be worse than none.
r = struct( ...
    "R",       NaN, ...
    "Pass",    false, ...
    "a",       NaN, ...
    "Method",  "NASA-STD-5020B Eq. 20-23 — not evaluated (§4.4.4 bending)", ...
    "Detail",  string(detail), ...
    "Bending", bendingOut(bend, NaN, condition, false));
end

function o = bendingOut(bend, Rb, condition, included)
%BENDINGOUT  The bending story as STRUCTURE, for a view to lay out.
%   Same reasoning as Result.Gate and Result.Allowables: a panel that has
%   to parse a sentence to find out whether bending was included is a panel
%   that will eventually parse it wrong.
o = struct( ...
    "Included",  included, ...
    "MomentIgnored", bend.HasMoment && ~included, ...
    "Fbu",       bend.Value, ...
    "Rb",        Rb, ...
    "Diameter",  bend.Diameter, ...
    "Basis",     string(bend.Basis), ...
    "Condition", conditionName(condition));
end

function s = conditionName(c)
%CONDITIONNAME  The §4.4.4 determination as a plain string for display.
switch c
    case model.ShearTransferCondition.CloseToleranceOrInterference
        s = "CloseToleranceOrInterference";
    case model.ShearTransferCondition.ClearanceOrGapped
        s = "ClearanceOrGapped";
    otherwise
        s = "NotDeclared";
end
end
