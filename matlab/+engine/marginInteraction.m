function r = marginInteraction(joint, designLoads)
%MARGININTERACTION  Combined tension-shear interaction check (NASA-STD-5020B Eq. 20-23).
%   r = engine.marginInteraction(joint, designLoads) evaluates the
%   tension-shear interaction criterion for one joint at the design loads.
%   designLoads is the struct from engine.designLoads. All loads in lbf
%   (see UNITS.md).
%
%   NASA-STD-5020B states Eq. 20-23 as a pass/fail criterion, not a margin
%   equation — the standard's own wording is that satisfying either of a
%   pair of these equations "is acceptable"; it never defines a margin of
%   safety for this check. This function therefore reports the interaction
%   ratio R (the left-hand side of the criterion, evaluated at the design
%   loads) and Pass = (R <= 1) — not a margin of safety. See the
%   SECONDARY, INFORMATIONAL field "a" note below for a related load-scale
%   factor that is not this result either.
%
%   Load ratios at the design loads:
%       Rt = Ptu / Ptu_allow          (Ptu_allow = the bolt's own ultimate
%                                      allowable — joint.BoltRatedUltimateLoad
%                                      when set, else a derived Ptu_allow =
%                                      At*Ftu; see boltTensileAllowable)
%       Rs = Psu / Psu_allow          (Psu_allow from engine.marginShearUlt,
%                                      reused so both checks share one allowable)
%
%   The criterion (NASA-STD-5020B Eq. 20 body / Eq. 22 threads):
%       R = Rs^es + (Rt + Rb)^et,     Pass iff R <= 1
%   with Rb = fbu/Ftu, the bending ratio, added to Rt inside the tension
%   bracket before the exponent — not as a separate term. Rb = 0 exactly
%   when no bending moment is supplied, so the criterion collapses to
%   R = Rt^et + Rs^es bit for bit (see BENDING below), with exponents by
%   shear-plane condition:
%       BodyInShear    — et = 1.5, es = 2.5 (NASA-STD-5020B Eq. 20/21)
%       ThreadsInShear — et = 2.0, es = 1.2 (NASA-STD-5020B Eq. 22/23;
%                        hand-derived, tests/tDabjCase.m — DABJ §9 has no
%                        threads-in-shear example). Exponents swapped
%                        relative to BodyInShear (tension up, shear down)
%                        per NASA-STD-5020B's own explanation: tensile and
%                        shear stresses peak at the same cross section
%                        when the threads are in the shear plane, but not
%                        when the full-diameter body is in the shear plane.
%   R is evaluated directly — Rt, Rs >= 0 always (loads and allowables are
%   both nonnegative), so Rt^et and Rs^es are ordinary real powers with no
%   root-find, no bracket, and no monotonicity argument needed for R
%   itself (unlike the secondary field "a" below).
%
%   BENDING (NASA-STD-5020B Eq. 20/22, §4.4.4):
%       fbu = 32*Mbu/(pi*d^3)      engine/private/boltBendingStress
%       Rb  = fbu / Ftu            Ftu = joint.BoltMaterial.Ftu
%   fbu is 5020B's "design ultimate bending stress based on linear-elastic
%   theory" — M*c/I on a circular section with c = d/2, I = pi*d^4/64 —
%   built from designLoads.Mbu (FSU*FFU*LoadCase.BoltBendingLimitMoment,
%   in-lbf). Which d to use is a derived convention, not a 5020B relation:
%   the section follows the shear plane, body diameter for BodyInShear and
%   minor diameter for ThreadsInShear, mirroring Eq. 12 vs Eq. 13 for the
%   shear allowable in these same criteria. See boltBendingStress's header
%   for why nominal D throughout would be unconservative exactly where
%   5020B says the tensile and shear stresses peak together.
%
%   Only Eq. 20 and Eq. 22 are implemented. Eq. 21/23 add a separate
%   fbu/Fbu term crediting plastic bending; Fbu (allowable flexural
%   stress) is not a field on model.Material, and 5020B states that
%   including the bending term in Eq. 20/22 "is considered to be
%   conservative" — so the reachable option is also the conservative one.
%   While fbu = 0 the two coincide and the Method string says "Eq. 20/21"
%   or "Eq. 22/23"; once bending is included it names the single equation
%   that actually ran.
%
%   NASA-STD-5020B §4.4.4 (p33) makes the fbu = 0 omission conditional:
%   bending must be considered "if the shear is transferred across gaps
%   or non load carrying spacers, or if there are clearances between the
%   bolt and joint." joint.ShearTransferCondition
%   (model.ShearTransferCondition) turns that exemption from a silent,
%   unconditional assumption into an explicit, recorded determination.
%   The determination controls only the no-moment case: a supplied
%   LoadCase.BoltBendingLimitMoment is used on every determination,
%   because §4.4.4's exemption covers only bending "caused by the shear
%   loading" and a supplied moment may come from anywhere (see "A
%   SUPPLIED MOMENT IS ALWAYS USED" below the Rb computation). With no
%   moment:
%       NotDeclared                  — default. fbu = 0; Method/Detail say
%                                      the §4.4.4 exemption is assumed, not
%                                      verified, and name the property.
%       CloseToleranceOrInterference — analyst has confirmed §4.4.4's
%                                      exemption condition holds. Same
%                                      numeric result as NotDeclared;
%                                      Method/Detail say verified.
%       ClearanceOrGapped            — analyst has confirmed §4.4.4's
%                                      exemption does not apply, so bending
%                                      must be accounted for. With a moment
%                                      supplied the criterion is evaluated
%                                      with the Rb term. With no moment it
%                                      stays R = NaN, Pass = false, no
%                                      throw — the analyst has said bending
%                                      matters and given nothing to compute
%                                      it from, so there is still no honest
%                                      answer.
%
%   A supplied moment is used on every determination — a bulk run
%   resolves one from the FE moments for every element, so this matters:
%       NotDeclared        — used, conservatively. Nobody assessed the
%                             joint and the model reports a moment;
%                             dropping it silently would be the quiet
%                             non-conservatism this enum exists to prevent.
%       CloseTolerance     — used. §4.4.4's exemption is scoped to bending
%                             "caused by the shear loading" (p33); a
%                             supplied moment may come from prying,
%                             eccentric tension or flange rotation, none
%                             of which it covers (see the "A SUPPLIED
%                             MOMENT IS ALWAYS USED" note below the Rb
%                             computation for the full reading).
%       ClearanceOrGapped  — used. That is the point of the declaration.
%
%   SECONDARY, INFORMATIONAL field "a": the load-scale factor solving
%   (a*Rt)^et + (a*Rs)^es = 1 — how far both design loads could scale,
%   together, before the envelope is reached. It is not a margin of
%   safety and not this check's result (R and Pass are); it is kept only
%   because it answers a genuinely different, useful question than R
%   does. a >= 1 iff R <= 1 (both encode the same pass/fail direction:
%   g(1) = R - 1, and g is strictly increasing for a > 0 for any positive
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
%       a       double — secondary, informational load-scale factor (see
%               above). Not a margin of safety; NaN if not evaluated.
%       Bending struct — the bending story as data, not prose: Included
%               (logical), Fbu (psi), Rb, Diameter (in), Basis
%               ("body"/"minor"/"none"), Condition (the §4.4.4
%               determination). Reaches the GUI as Result.Bending; a view
%               that had to parse Detail to find out whether bending was
%               included would eventually parse it wrong.
%       Method  string: governing equation + exponents, plus the §4.4.4
%               bolt-bending exemption's assumed/verified/included/
%               not-evaluated status
%       Detail  string: R's value and pass/fail, the bolt ultimate
%               allowable's basis (rated/derived) and arithmetic, the
%               §4.4.4 exemption determination (and which property to set
%               to change it), or the not-evaluated reason
%       Inputs  engine.eqInput array: every term, with its source

arguments
    joint       (1,1) model.Joint
    designLoads (1,1) struct
end

% NASA-STD-5020B §4.4.4 (p33) requires bending to be considered when shear
% is transferred across gaps/spacers or when there is clearance between
% the bolt and joint (see BENDING in the header). When the analyst has
% recorded that this configuration is exactly the one §4.4.4 flags, and no
% moment is available to evaluate it, the Eq. 20-23 criterion cannot be
% evaluated conservatively -- NotEvaluated, no throw, checked before the
% bolt-allowable lookup below so the reason is never masked by an
% unrelated "allowable unavailable" message.
%
% Mbu is read defensively: engine.designLoads always emits it, but a bare
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

% A supplied moment is always used, on every determination. §4.4.4's
% exemption is scoped to bending "caused by the shear loading" (p33) —
% prying, eccentric tension, flange rotation are none of that, and the
% standard's very next sentence is unqualified: fasteners under combined
% tensile, shear, and any applicable bending loads should have that
% interaction accounted for. "Typically there is no need to account for"
% excuses deriving a shear-induced moment you do not have; it is not
% licence to discard one you were handed — and §4.4.4 says including the
% term "is considered to be conservative", so using a supplied moment is
% never wrong, only ever more conservative. A bulk run resolving a moment
% for every element, and FE moments on a stiff connection sometimes being
% an idealisation artefact, argues for the analyst not supplying the
% moment — not for the tool discarding it on their behalf.
%
% The determination controls exactly one thing: what happens when no
% moment is supplied. Then all three read fbu = 0 and differ only in how
% they say why —
%   CloseToleranceOrInterference  exemption verified
%   NotDeclared                   exemption assumed, not confirmed
%   ClearanceOrGapped             NotEvaluated (the analyst has said
%                                 bending matters and given nothing to
%                                 compute it from)
useBending = bend.HasMoment;

% A ClearanceOrGapped joint is one the analyst has declared §4.4.4's
% exemption does not cover, so bending has to be accounted for -- but only
% if a moment was actually supplied. With none, this is the honest
% not-evaluated case: the analyst has said bending matters and given
% nothing to compute it from.
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

% Deliberately the bolt's own allowable, not the NASA-STD-5020B §4.4.1
% fastening-system allowable (engine.systemTensileAllowable) that
% engine.marginTensionUlt uses. The Eq. 20-23 interaction envelope and its
% shear-plane-dependent exponents describe combined tension+shear failure
% of the fastener; 5020B gives no interaction envelope for nut-stripping /
% insert pull-out / parent-thread modes — those members carry the axial
% bolt load but not the joint shear, and each is checked on its own
% Margins row (marginNutStrength / marginInsert / marginTappedParentThread).
% Folding a member-governed system allowable into a bolt interaction
% envelope would mix failure modes across equations. Three grounds
% support landing this on the bolt, in increasing strength:
%
%   (1) §4.4.4 frames itself around the fastener — "When assessing the
%       strength of the fastener due to combined loading...", "For
%       fasteners under simultaneously applied tensile and shear loads..."
%       (p33) — and never re-invokes the fastening system or
%       cross-references §4.4.1's definition.
%   (2) The empirical basis is fastener rupture: "these criteria... are
%       based on tests of A-286 3/8-24 (NAS1956C14) fasteners performed at
%       NASA MSFC in 2010" (p33), and Psu_allow is unambiguously a bolt
%       cross-section quantity (Eq. 12/13).
%   (3) The bracket structure itself is decisive. Eq. 20/22 sum the
%       tension and bending ratios inside one parenthesis:
%           (Ptu/Ptu_allow + fbu/Ftu)^k
%       fbu is a bending stress and Ftu an allowable stress on the bolt
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
% The gap this leaves is real and is not a defect in this function.
% 5020B provides no interaction envelope for internally-threaded-part
% failure under combined load. When a nut or insert governs axially,
% Eq. 20-23 with bolt allowables genuinely does not check that member
% under simultaneous tension and shear — and neither does anything else in
% the standard. Substituting the system minimum into Rt would be
% conservative and cheap, but it is an engineering judgment, not a reading
% of 5020B, and doing it silently would redefine a cited equation's symbol
% — which this repo's traceability rule forbids. If that residual risk
% needs covering, add a separately labelled supplementary check rather
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
    % Through the shared helper, like the other three not-evaluated exits,
    % so a caller never has to guess which fields a NaN result carries.
    r = bendingNotEvaluated("Not evaluated: " + bt.Ult.Reason + ".", ...
        bend, joint.ShearTransferCondition, ...
        "NASA-STD-5020B Eq. 20-23 — not evaluated");
    return
end
PtuAllow = bt.Ult.Value;

switch joint.ShearPlane
    case model.ShearPlaneCondition.BodyInShear
        % NASA-STD-5020B Eq. 20/21 (body in shear) -- criterion
        % Rt^1.5 + Rs^2.5 <= 1 (Rb = 0 unless a moment is supplied; see
        % BENDING in the header)
        et = 1.5;                               % tension exponent
        es = 2.5;                               % shear exponent
        methodLabel = "NASA-STD-5020B Eq. 20/21 (body in shear, exp 1.5/2.5) - R = Rs^2.5 + (Rt + Rb)^1.5, PASS iff R <= 1";
    case model.ShearPlaneCondition.ThreadsInShear
        % NASA-STD-5020B Eq. 22/23 (threads in shear) -- criterion
        % Rt^2.0 + Rs^1.2 <= 1 (Rb = 0 unless a moment is supplied).
        % Exponents swapped from body-in-shear (tension 1.5->2.0, shear
        % 2.5->1.2) per NASA-STD-5020B's own explanation quoted above: the
        % tensile and shear stresses peak at the same cross section when
        % the threads are in the shear plane, unlike the body-in-shear case.
        et = 2.0;                               % tension exponent
        es = 1.2;                               % shear exponent
        methodLabel = "NASA-STD-5020B Eq. 22/23 (threads in shear, exp 2.0/1.2) - R = Rs^1.2 + (Rt + Rb)^2.0, PASS iff R <= 1";
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
% sits inside the tension bracket. Ftu is the bolt material's allowable
% ultimate tensile stress; the standard pairs fbu with Ftu (not with the
% rated allowable behind Rt) in Eq. 20 and Eq. 22 as printed.
Ftu = joint.BoltMaterial.Ftu;
if useBending && (~isfinite(Ftu) || Ftu <= 0)
    % Only fatal with a moment: with none, Rb is 0 and Ftu never matters.
    r = bendingNotEvaluated("Not evaluated: a bending moment was supplied " + ...
        "but the bolt material has no Ftu, so the NASA-STD-5020B Eq. 20/22 " + ...
        "fbu/Ftu term cannot be formed.", bend, joint.ShearTransferCondition);
    return
end
% Rb is exactly zero with no moment, so a joint that supplies none
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
% added to the tension ratio inside the bracket, before the exponent — not
% as a separate term. (A separate fbu/Fbu term is Eq. 21/23, the plastic-
% bending variants; Fbu is not in model.Material, and 5020B calls including
% bending in Eq. 20/22 the conservative choice.)
% Direct evaluation: Rt, Rs, Rb >= 0 always, so no root-find is needed.
R = Rs^es + (Rt + Rb)^et;
Pass = R <= 1;

% ---- Secondary, informational load-scale factor "a" (not the result) ----
% (a*Rt)^et + (a*Rs)^es = 1. g(0) = -1 and g is strictly increasing for
% a > 0 (see the module-header argument), so the root is unique. Solve on
% a positive bracket [0, hi] so fzero never evaluates a < 0 (a
% non-integer power of a negative base is complex and aborts the search).
% Rb scales with the loads: fbu is linear in the applied moment, so
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
% branches produce the identical numeric R, a — only the assumed/verified
% wording differs, mirroring engine.private.separationBeforeRuptureGate's
% own e/D assumed-vs-verified distinction.
if useBending
    % Bending is in the number: Eq. 21/23 are the plastic-bending variants
    % (a separate fbu/Fbu term) and are not what ran, so the label drops to
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
            % No moment was supplied — if one had been, useBending would
            % have taken the branch above. §4.4.4's exemption covers only
            % bending caused by the shear loading, so it justifies not
            % deriving one here; it never justified discarding one.
            bendingNote = "§4.4.4 bolt-bending exemption VERIFIED (fbu = 0, no " + ...
                "moment supplied; Joint.ShearTransferCondition = " + ...
                "CloseToleranceOrInterference). The exemption covers bending " + ...
                "caused by the SHEAR loading; a moment from any other source " + ...
                "would still be included if one were supplied";
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
    "Inputs",  [ ...
        engine.eqInput("Ptu", designLoads.Ptu, "lbf", ...
            "engine.designLoads = FSU*FFU*PtL"), ...
        engine.eqInput("Ptu_allow", PtuAllow, "lbf", ...
            "the BOLT's own allowable, NOT the 4.4.1 system min"), ...
        engine.eqInput("Rt", Rt, "", ...
            "= Ptu/Ptu_allow"), ...
        engine.eqInput("Psu", designLoads.Psu, "lbf", ...
            "engine.designLoads = FSU*FFU*PsL"), ...
        engine.eqInput("Psu_allow", shearUlt.ShearAllowable, "lbf", ...
            "engine.marginShearUlt, Eq. 12/13"), ...
        engine.eqInput("Rs", Rs, "", ...
            "= Psu/Psu_allow"), ...
        engine.eqInput("Rb", Rb, "", ...
            "= fbu/Ftu; 0 when 4.4.4 exempts bending"), ...
        engine.eqInput("et", et, "", ...
            "tension exponent, per " + string(joint.ShearPlane)), ...
        engine.eqInput("es", es, "", ...
            "shear exponent, per " + string(joint.ShearPlane)), ...
        engine.eqInput("R", R, "", ...
            "= Rs^es + (Rt+Rb)^et, PASS iff R <= 1")], ...
    "Bending", bendingOut(bend, Rb, joint.ShearTransferCondition, useBending));
end

% ---- Local helpers --------------------------------------------------------
function r = bendingNotEvaluated(detail, bend, condition, method)
%BENDINGNOTEVALUATED  The NotEvaluated return, with the bending block intact.
%   One shape for all four not-evaluated exits, so a caller never has to
%   guess which fields a NaN result carries. The condition is passed in
%   rather than assumed to be ClearanceOrGapped: two of the exits (no
%   section, no Ftu) are reachable from any determination, and a Bending
%   block that misreported which one the analyst recorded would be worse
%   than none.
%
%   Method is overridable because not every not-evaluated exit is about
%   bending. Three are, and take the default. The fourth — no assessable
%   bolt tensile allowable — is not, and labelling it "(§4.4.4 bending)"
%   would name the wrong cause on the row the analyst reads.
arguments
    detail
    bend
    condition
    method (1,1) string = "NASA-STD-5020B Eq. 20-23 — not evaluated (§4.4.4 bending)"
end
r = struct( ...
    "R",       NaN, ...
    "Pass",    false, ...
    "a",       NaN, ...
    "Method",  method, ...
    "Detail",  string(detail), ...
    "Inputs",  engine.eqInput(), ...
    "Bending", bendingOut(bend, NaN, condition, false));
end

function o = bendingOut(bend, Rb, condition, included)
%BENDINGOUT  The bending story as structure, for a view to lay out.
%   Same reasoning as Result.Gate and Result.Allowables: a panel that has
%   to parse a sentence to find out whether bending was included is a panel
%   that will eventually parse it wrong.
o = struct( ...
    "Included",  included, ...
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
