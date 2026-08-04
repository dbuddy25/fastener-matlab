function a = memberTensileUltAllowable(joint)
%MEMBERTENSILEULTALLOWABLE  Ultimate tensile allowable of the internal-thread member.
%   a = memberTensileUltAllowable(joint) resolves the ULTIMATE tensile
%   allowable of the joint's internal-thread member (nut / insert / tapped
%   hole). It is the single home of the member-side ultimate-allowable
%   arithmetic, shared by the per-mode margin checks
%   (engine.marginNutStrength, engine.marginInsert,
%   engine.marginTappedParentThread) and by engine.systemTensileAllowable
%   (the NASA-STD-5020B §4.4.1 fastening-system allowable) — one
%   implementation keeps the reported per-mode rows and the system minimum
%   arithmetically identical by construction. YIELD allowables stay in the
%   margin functions: Ptu-allow is an ultimate quantity.
%
%   The formulas are exactly the ones the margin checks have always used:
%
%     Nut (Type Nut):
%       area basis — As is ALWAYS the computed As = 0.75·pi·E·Le (NASA
%         TM-106943 Eq. 76 internal-thread form with the pitch-diameter
%         substitution). A per-joint
%         ThreadedMember.ShearEngagementArea is deliberately NOT read here
%         (see the Nut case below for why); computed ultimate Pult = Fsu·As (TM-106943 Eq. 77)
%         with the NUT material Fsu; a spec rating CAPS it
%         (NASA-STD-5020B §4.4.1 — nut "limited to the load rating of
%         the nut"): EffUlt = min(Fsu·As, RatedUltimateLoad).
%       rated basis (no area available) — EffUlt = RatedUltimateLoad alone,
%         per NASA-STD-5020B §4.4.1.
%
%     Insert (Type Insert):
%       area basis — As = supplied ThreadedMember.ShearEngagementArea, else
%         the DERIVED As = 0.75·pi·D2·(Le-1.125·p) computed from catalogue
%         geometry (D2 = ThreadedMember.StiPitchDiameter, the STI
%         tapped-hole pitch diameter, NASM33537 Rev 4 Table IV; the
%         -1.125·p term is a derived install-offset convention, no
%         equation number — see the local helper computeInsertArea,
%         below, for the full derivation and citations).
%         EffUlt = min(As·parent Fsu, rating); NASA-STD-5020B §4.4.1:
%         allowable pull-out = (minimum shear engagement area) x
%         (parent-material allowable shear stress), with the rated
%         pull-out as a lower-of ceiling.
%       rated basis (no area available by either source) —
%         EffUlt = RatedUltimateLoad (the manufacturer rated pull-out,
%         §4.4.1).
%
%     TappedHole:
%       EffUlt = Fsu·As with As = 0.75·pi·E·Le (TM-106943 Eq. 79 parent
%       pull-out strength Pult = Fsu·As, pitch-diameter area form);
%       ultimate-only, no rating for a tapped hole.
%
%   NO SILENT FALLBACK (mirrors the margin checks): when an area is
%   configured but the member material's Fsu is NaN, the mode is NOT
%   assessed — the true allowable is min(Fsu·As, rating) <= rating, so
%   standing the rating in for the uncomputable area form would be
%   OPTIMISTIC. The reason lands in Reason for the caller to surface.
%
%   Returned struct fields:
%     Mode      display name: "nut thread shear" / "insert pull-out" /
%               "tapped-hole parent thread"
%     Basis     "area" | "rated" | "none"
%     Assessed  logical — EffUlt is a usable ultimate allowable
%     EffUlt    effective ultimate allowable, lbf (rating-capped on the
%               area basis; NaN unless Assessed)
%     AllowUlt  computed (uncapped) area x Fsu, lbf (NaN off the area
%               basis, or when Fsu is NaN)
%     As        area used, in^2 (NaN off the area basis)
%     AreaSrc   string naming the area source ("" off the area basis)
%     Rating    spec rating participating in the mode, lbf (NaN when unset)
%     RatNote   rating-disposition string for Detail ("" when none applies)
%     Reason    why the mode could not be assessed ("" when Assessed)

arguments
    joint (1,1) model.Joint
end

a = struct("Mode", "", "Basis", "none", "Assessed", false, ...
    "EffUlt", NaN, "AllowUlt", NaN, "As", NaN, "AreaSrc", "", ...
    "Rating", NaN, "RatNote", "", "Reason", "");

switch joint.ThreadedMember.Type
    case model.ThreadedMemberType.Nut
        a.Mode = "nut thread shear";
        rating = joint.ThreadedMember.RatedUltimateLoad;   % spec-rated nut Pult, lbf (0 = unset)
        if rating > 0
            a.Rating = rating;
        end

        % ---- Area resolution (computed only) -----------------------------
        % A nut's area is ALWAYS computed here. ThreadedMember.
        % ShearEngagementArea is deliberately NOT read on this path, even
        % when set: NASA-STD-5020B §4.4.1 gives a nut a rated LOAD ("Nuts
        % should be limited to the load rating of the nut") and contemplates
        % no shear engagement area for one at all. The 0.75·pi·E·Le form
        % below is already a departure from that — it is the
        % thread-stripping analysis §4.4.1 says not to base assessment on —
        % kept because it can only lower the allowable beneath the rating
        % (lower-of, see the ceiling applied by the caller), never raise it.
        % An area supplied per joint would have overridden that computed
        % value with a number carrying neither the standard's authority nor
        % this engine's consistent area form, so it is not honoured. The
        % insert path is different and DOES read a specified area: §4.4.1
        % defines an insert's allowable as a specified minimum shear
        % engagement area times the parent's allowable shear stress.
        E    = joint.Bolt.PitchDiameter;         % thread pitch diameter, in
        % Le: ratio-or-absolute, single resolution — see resolveEngagementLength.
        rle  = resolveEngagementLength(joint);
        Le   = rle.Le;                           % nut thread engagement, in
        if ~isnan(E) && ~isnan(Le)
            % TM-106943 Eq. 76, pitch-diameter form — As = 0.75·pi·E·Le
            a.As      = 0.75 * pi * E * Le;           % internal-thread shear area, in^2
            a.AreaSrc = string(sprintf("As = 0.75·pi·E·Le with E %.4f in, %s", E, rle.Note));
        end

        if isnan(a.As)
            if rating > 0
                % NASA-STD-5020B §4.4.1 — nut limited to its load rating:
                % EffUlt = RatedUltimateLoad (flat rated basis, no area)
                a.Basis    = "rated";
                a.EffUlt   = rating;
                a.Assessed = true;
            else
                a.Reason = "no thread-shear area (needs Bolt.PitchDiameter + " + ...
                    "ThreadedMember.EngagementLength or EngagementRatio x Bolt.NominalDiameter) " + ...
                    "and no spec-rated load (ThreadedMember.RatedUltimateLoad)";
            end
            return
        end

        a.Basis = "area";
        Fsu = joint.ThreadedMember.Material.Fsu;   % NUT ultimate shear strength, psi
        if isnan(Fsu)
            a.Reason = "a thread-shear area is available but the nut " + ...
                "ThreadedMember.Material.Fsu is NaN — the spec rating, if any, only " + ...
                "CAPS the computed allowable (lower-of) and cannot stand in for it";
            return
        end
        % TM-106943 Eq. 77 — Pult = Fsu·As (nut internal-thread shear allowable)
        a.AllowUlt = Fsu * a.As;
        % NASA-STD-5020B §4.4.1 — the spec rating CAPS the computed
        % ultimate allowable (lower-of; nuts dilate under load, so a
        % computed area is optimistic): EffUlt = min(Fsu·As, RatedUltimateLoad)
        if rating > 0
            if rating < a.AllowUlt
                a.EffUlt  = rating;
                a.RatNote = string(sprintf( ...
                    "spec rating %.0f lbf GOVERNS the ultimate allowable (caps computed %.0f lbf per 5020B §4.4.1)", ...
                    rating, a.AllowUlt));
            else
                a.EffUlt  = a.AllowUlt;
                a.RatNote = string(sprintf( ...
                    "spec rating %.0f lbf not limiting (computed allowable %.0f lbf is lower)", ...
                    rating, a.AllowUlt));
            end
        else
            a.EffUlt = a.AllowUlt;
        end
        a.Assessed = true;

    case model.ThreadedMemberType.Insert
        a.Mode = "insert pull-out";
        rating = joint.ThreadedMember.RatedUltimateLoad;   % rated pull-out, lbf (0 = unset)
        if rating > 0
            a.Rating = rating;
        end

        % ---- Area resolution: SPECIFIED area, else COMPUTED from STI -----
        % catalogue geometry (computeInsertArea, below), else NaN ->
        % flat-rating basis. This does NOT mirror the Nut case: a nut's area
        % is always computed, because NASA-STD-5020B §4.4.1 gives a nut a
        % rated LOAD and contemplates no area for one. An insert is the
        % opposite — §4.4.1 defines its allowable as a SPECIFIED minimum
        % shear engagement area times the parent's allowable shear stress —
        % so a specified area is honoured here and is the tier a
        % manufacturer-published area would enter through. It is not
        % analyst input: no GUI control or workbook column sets it (see
        % commit 0846e0e, which removed both because an area typed against
        % the wrong bolt size could silently govern). computeInsertArea's
        % own reason, when it cannot form an area, distinguishes "no insert
        % is catalogued for this thread size" from an
        % incomplete-but-catalogued configuration — see that helper's header.
        area = joint.ThreadedMember.ShearEngagementArea;   % in^2 (NaN -> try computed form)
        if ~isnan(area)
            a.As         = area;                                          % supplied wins outright
            a.AreaSrc    = string(sprintf("specified shear engagement area %.4f in^2", area));
            noAreaReason = "";
        else
            [a.As, a.AreaSrc, noAreaReason] = computeInsertArea(joint);
        end

        if isnan(a.As)
            if rating > 0
                % NASA-STD-5020B §4.4.1 — manufacturer rated pull-out
                % (spec-rated insert): EffUlt = RatedUltimateLoad
                a.Basis    = "rated";
                a.EffUlt   = rating;
                a.Assessed = true;
            elseif strlength(noAreaReason) > 0
                a.Reason = noAreaReason + "; and no manufacturer rated pull-out load (ThreadedMember.RatedUltimateLoad)";
            else
                a.Reason = "no shear engagement area (ThreadedMember.ShearEngagementArea) " + ...
                    "and no manufacturer rated pull-out load (ThreadedMember.RatedUltimateLoad)";
            end
            return
        end

        a.Basis = "area";
        Fsu = joint.ThreadedMember.Material.Fsu;   % PARENT ultimate shear strength, psi
        if isnan(Fsu)
            a.Reason = "a shear engagement area is available (" + a.AreaSrc + ") but the parent " + ...
                "ThreadedMember.Material.Fsu is NaN — the rated pull-out, if any, only " + ...
                "CAPS the computed allowable (lower-of) and cannot stand in for it";
            return
        end
        % NASA-STD-5020B §4.4.1 — allowable pull-out = (minimum shear
        % engagement area) x (parent allowable shear stress): AllowUlt = A_shear·Fsu
        a.AllowUlt = a.As * Fsu;
        % NASA-STD-5020B lower-of ceiling ("the lower value should be used
        % for strength analysis"): EffUlt = min(A_shear·Fsu, RatedUltimateLoad)
        if rating > 0
            if rating < a.AllowUlt
                a.EffUlt  = rating;
                a.RatNote = string(sprintf( ...
                    "rated pull-out %.0f lbf GOVERNS the ultimate allowable (caps computed %.0f lbf, lower-of per 5020B)", ...
                    rating, a.AllowUlt));
            else
                a.EffUlt  = a.AllowUlt;
                a.RatNote = string(sprintf( ...
                    "rated pull-out %.0f lbf not limiting (computed allowable %.0f lbf is lower)", ...
                    rating, a.EffUlt));
            end
        else
            a.EffUlt = a.AllowUlt;
        end
        a.Assessed = true;

    case model.ThreadedMemberType.TappedHole
        a.Mode = "tapped-hole parent thread";
        E   = joint.Bolt.PitchDiameter;               % thread pitch diameter, in
        % Le: ratio-or-absolute, single resolution — see resolveEngagementLength.
        rle = resolveEngagementLength(joint);
        Le  = rle.Le;                                 % tapped thread engagement, in
        Fsu = joint.ThreadedMember.Material.Fsu;      % PARENT ultimate shear strength, psi
        if isnan(E) || isnan(Le) || isnan(Fsu)
            a.Reason = "needs Bolt.PitchDiameter, ThreadedMember.EngagementLength or " + ...
                "EngagementRatio, and the parent Material.Fsu (one or more NaN)";
            return
        end
        a.Basis   = "area";
        % Pitch-diameter thread-shear area — As = 0.75·pi·E·Le
        a.As      = 0.75 * pi * E * Le;               % parent internal-thread shear area, in^2
        a.AreaSrc = string(sprintf("As = 0.75·pi·E·Le with E %.4f in, %s", E, rle.Note));
        % TM-106943 Eq. 79 — Pult = Fsu·As (parent pull-out strength)
        a.AllowUlt = Fsu * a.As;
        a.EffUlt   = a.AllowUlt;
        a.Assessed = true;

    otherwise
        a.Mode   = "internal-thread member";
        a.Reason = "unknown threaded-member type (" + string(joint.ThreadedMember.Type) + ")";
end
end

% ---- Local helpers ----------------------------------------------------------
function [As, areaSrc, reason] = computeInsertArea(joint)
%COMPUTEINSERTAREA  Insert pull-out area DERIVED from STI catalogue geometry.
%   [As, areaSrc, reason] = computeInsertArea(joint) computes the labelled
%   fallback area used by the Insert case above whenever no
%   ShearEngagementArea was supplied:
%       As = 0.75*pi*D2*(Le - 1.125*p)
%   D2 = joint.ThreadedMember.StiPitchDiameter — the STI tapped-hole pitch
%   diameter, in (NASM33537 Rev 4 Table IV; equivalently Stanley HELI-COIL
%   catalogue HC2000 Rev 12 Table VII p.20) — the diameter at which the
%   PARENT's internal thread shears, LARGER than the bolt's own pitch
%   diameter (which is why joint.Bolt.PitchDiameter cannot stand in for it
%   the way it does in the nut/tapped-hole 0.75*pi*E*Le forms).
%   Le  = resolveEngagementLength(joint).Le (ratio-or-absolute resolution,
%   the SAME helper the nut/tapped-hole forms use).
%   p   = 1/joint.Bolt.ThreadsPerInch, the thread pitch, in.
%
%   0.75*pi*D2*Le IS the pitch-diameter thread-shear-area form already used
%   by this file's Nut case and by engine.marginTappedParentThread
%   (NASA TM-106943 (Chambers) Eq. 78/79 give the thread-shear area with a
%   5/8 coefficient; the 0.75 substitution is this engine's own convention,
%   not TM-106943's printed number, applied consistently so every
%   internal-thread shear area in the tool rests on one basis — same
%   citation those two carry).
%
%   THE "-1.125*p" TERM IS A DERIVED CONVENTION — no published equation, no
%   equation number attached (DEVELOPMENT_PLAN.md §2.3). Its basis:
%   NASM33537 §11.1 installs the insert's top edge 0.75p to 1.5p below the
%   tapped-hole surface (midpoint 1.125p), so that much of the tapped
%   parent thread sits above the insert and carries no pull-out load. The
%   resulting form was checked against 27 sizes x 5 length classes of
%   manufacturer pull-out data and sits below every point by 1.6%-10.4%,
%   i.e. conservative throughout (the underlying data is not reproduced
%   here — see the DEVELOPMENT_PLAN.md note this function implements).
%
%   Returns As = NaN (never negative or zero) with reason naming exactly
%   why, distinguishing an UNCATALOGUED size from an incomplete
%   configuration of an otherwise-catalogued one:
%     - StiPitchDiameter NaN: "no insert is catalogued for this thread
%       size" — e.g. #0-80, #5-44 (no helical insert is offered for them
%       in NASM33537 or the Stanley catalogue; see model.ThreadedMember's
%       header). An analyst reading this must NOT conclude they simply
%       forgot to enter an area — there is nothing to enter.
%     - the resolved Le is NaN: engagement length not configured
%       (EngagementLength / EngagementRatio) even though the insert IS
%       catalogued.
%     - Bolt.ThreadsPerInch is NaN/<=0: no pitch to form p.
%     - Le - 1.125*p <= 0: the derived install-offset guard — refuses
%       rather than emit a non-positive area.
%
%   Call graph:
%       Precedents (calls)      resolveEngagementLength (private).
%       Dependents (called by)  memberTensileUltAllowable (Insert case, this file).
%       Tests                   tests/tThreadShear.m —
%                               insertComputedAreaGovernsWhenUnspecified,
%                               insertSuppliedAreaWinsOverCatalogueGeometry,
%                               insertComputedAreaRatingStillCaps,
%                               insertUncataloguedSizeVsIncompleteConfigRefusal,
%                               insertComputedAreaGuardRefusesNonPositiveArea.

arguments
    joint (1,1) model.Joint
end

As      = NaN;
areaSrc = "";
reason  = "";

D2 = joint.ThreadedMember.StiPitchDiameter;   % STI tapped-hole pitch diameter, in
if isnan(D2)
    reason = "ThreadedMember.StiPitchDiameter is not set, so no STI tapped-hole geometry is available — either no insert is catalogued for this thread size (#0-80 and #5-44 have none), or this joint was built without library resolution (gui.FastenerApp.buildJoint, data.loadJointLibrary and engine.boltSizingSweep each resolve it via data.Library.insertFor; a hand-built headless joint does not)";
    return
end

% Le: ratio-or-absolute, single resolution — see resolveEngagementLength.
rle = resolveEngagementLength(joint);
Le  = rle.Le;
if isnan(Le)
    reason = "the insert is catalogued (StiPitchDiameter set) but the engagement length " + ...
        "could not be resolved (ThreadedMember.EngagementLength or EngagementRatio x Bolt.NominalDiameter)";
    return
end

tpi = joint.Bolt.ThreadsPerInch;
if isnan(tpi) || tpi <= 0
    reason = "the insert is catalogued and the engagement length resolved, but Bolt.ThreadsPerInch " + ...
        "is not set (needed for the thread pitch p = 1/TPI)";
    return
end

p     = 1 / tpi;             % thread pitch, in
netLe = Le - 1.125 * p;       % NASM33537 Sec 11.1-derived install-offset guard (see header)
if netLe <= 0
    reason = string(sprintf( ...
        "engagement length Le %.4f in does not exceed the derived install offset 1.125*p %.4f in (p = 1/TPI = %.4f in) -- the computed area would be non-positive", ...
        Le, 1.125 * p, p));
    return
end

% DERIVED area (see header) — the 0.75*pi*E*Le form with D2 (STI
% pitch diameter) in place of E, and Le reduced by the derived 1.125*p
% install-offset term.
As = 0.75 * pi * D2 * netLe;
% rle.Note carries how Le itself was resolved (ratio x nominal diameter,
% absolute length, or a ratio overriding a supplied length). Every other
% consumer of resolveEngagementLength folds it into its own Detail; this
% one must too, or a reviewer cross-checking the printed Le against an
% entered EngagementLength sees an unexplained number.
areaSrc = string(sprintf( ...
    "computed (DERIVED) As %.4f in^2 = 0.75·pi·D2·(Le-1.125p), D2 %.4f in (NASM33537 Rev 4 Table IV STI pitch diameter), Le %.4f in, p %.4f in; %s", ...
    As, D2, Le, p, rle.Note));
end
