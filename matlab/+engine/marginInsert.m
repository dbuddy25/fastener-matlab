function r = marginInsert(joint, loadCase, factors, preload)
%MARGININSERT  Insert pull-out margin — parent-material area form or rated load.
%   r = engine.marginInsert(joint, loadCase, factors, preload) checks a
%   threaded insert (Heli-Coil) for pull-out. Only evaluated when
%   joint.ThreadedMember.Type == Insert; otherwise MS = NaN (NotEvaluated).
%   preload is the struct from engine.preload. Loads in lbf, areas in in^2,
%   strengths in psi (see UNITS.md).
%
%   TWO BASES, one row (which one ran is stated in Method/Detail):
%
%   (1) SHEAR-ENGAGEMENT-AREA form (governs whenever an area is
%       available — either SUPPLIED directly
%       (ThreadedMember.ShearEngagementArea, labelled "specified" in
%       Detail) or, when that is NaN, COMPUTED from catalogue geometry
%       (labelled "computed (DERIVED)" in Detail) — see AREA SOURCE
%       PRECEDENCE below). NASA-STD-5020B §4.4.1: an insert's allowable
%       pull-out load depends on the PARENT material — the common failure
%       mode is shear of the parent internal threads, and insert
%       specifications define the allowable as a specified minimum shear
%       engagement area times the parent's allowable shear stress:
%           allowable = A_shear x F_parent
%       Note §4.4.1 is titled "Ultimate Design Loads" and states this
%       against the parent's allowable ULTIMATE shear stress, so the
%       ULTIMATE criterion below is the standard's; the YIELD counterpart
%       is this tool's own criterion — §4.4.2 requires yield design loads
%       but prints no pull-out equation, so the same area form is
%       evaluated against the parent's shear YIELD strength and no
%       equation number is claimed for it. Both are then evaluated
%       (marginBearing shape — worst governs,
%       criterion named in Detail), each against the design bolt load built
%       with ITS OWN factor pair (engine.boltDesignLoad, 5020B Eq. 8 form):
%           ultimate: MS = A_shear·Fsu / Pb − 1,
%                     Pb      = PpMax + FFU·FSU·n·phi·PtL
%           yield:    MS = A_shear·Fsy / PbYield − 1,
%                     PbYield = PpMax + FFY·FSY·n·phi·PtL
%       with Fsu/Fsy of joint.ThreadedMember.Material (the PARENT material
%       the insert is installed in). A NaN Fsy is estimated as Fty/sqrt(3)
%       (von Mises) via engine.shearYieldStrength — the estimate is ALWAYS
%       flagged in Detail so a constitutive assumption never masquerades as
%       test data.
%
%       AREA SOURCE PRECEDENCE (always visible in Detail, never silent —
%       see the private helper memberTensileUltAllowable / its local
%       function computeInsertArea for the full implementation):
%         (a) ThreadedMember.ShearEngagementArea, when set — "specified".
%         (b) else ThreadedMember.StiPitchDiameter set AND the engagement
%             length resolves (resolveEngagementLength) — COMPUTED,
%             flagged "computed (DERIVED)":
%                 As = 0.75·pi·D2·(Le − 1.125·p)
%             D2 = StiPitchDiameter, the STI tapped-hole pitch diameter
%             (NASM33537 Rev 4 Table IV; equivalently Stanley HELI-COIL
%             catalogue HC2000 Rev 12 Table VII p.20) — the diameter at
%             which the PARENT's internal thread shears, LARGER than the
%             bolt's own pitch diameter, so joint.Bolt.PitchDiameter
%             cannot be substituted for it the way E is used in the
%             nut/tapped-hole 0.75·pi·E·Le forms (NASA TM-106943 Eq. 78/79
%             give the thread-shear area with a 5/8 coefficient; the 0.75
%             substitution is this tool's own convention, already used by
%             marginNutStrength / marginTappedParentThread — same
%             citation those two carry). p = 1/Bolt.ThreadsPerInch, the
%             thread pitch. The "− 1.125·p" TERM IS A DERIVED
%             CONVENTION — no published equation, no equation number
%             attached (DEVELOPMENT_PLAN.md §2.3): NASM33537 §11.1
%             installs the insert's top edge 0.75p to 1.5p below the
%             tapped-hole surface (midpoint 1.125p), so that much of the
%             tapped parent thread sits above the insert and carries no
%             pull-out load; the resulting form was checked against 27
%             sizes x 5 length classes of manufacturer pull-out data and
%             sits below every point by 1.6%-10.4%, i.e. conservative
%             throughout (data itself not reproduced here). GUARDED:
%             Le − 1.125·p <= 0 refuses rather than emit a negative or
%             zero area (reason stated, never a crash).
%         (c) else the flat MANUFACTURER RATED basis, (2) below.
%         (d) else NotEvaluated — and the reason DISTINGUISHES "no insert
%             is catalogued for this thread size" (StiPitchDiameter NaN —
%             e.g. #0-80, #5-44, for which no helical insert exists in
%             either NASM33537 or the Stanley catalogue) from an
%             otherwise-catalogued insert with an incomplete
%             configuration (Le or TPI missing, or the guard above) — an
%             analyst must never read the second reason when the first is
%             the true one.
%       StiPitchDiameter is populated at build time from
%       data.Library.insertFor(nominalDiameter, tpi) by the GUI and the
%       bulk loader — this function never reads the library itself.
%
%       Pb/PbYield above are engine.boltDesignLoad's CLAMPED form; that
%       function branches on the NASA-STD-5020B Fig. 8 separation-before-
%       rupture gate (shared with engine.marginTensionUlt via the private
%       helper separationBeforeRuptureGate, so this row and the tension row
%       can never disagree about which branch applies). When the gate is
%       ASSURED, the clamped members carry no load once separated, so
%       Pb = FFU·FSU·PtL and PbYield = FFY·FSY·PtL instead — no preload, no
%       n·phi (NASA-STD-5020B Eq. 6 principle). Detail names which branch
%       produced the numbers actually used.
%
%       RATING AS A CEILING: when RatedUltimateLoad is ALSO set, it does
%       not compete with the area form — it CAPS it:
%           ultimate allowable = min(A_shear·Fsu, RatedUltimateLoad)
%       with the governing source named in Detail. NASA-STD-5020B directs
%       that a procured item's strength be based on the strength specified
%       for that item (such items can expand under load, reducing the
%       thread engagement areas — a computed area is optimistic) and that
%       where two values exist "the lower value should be used for
%       strength analysis". Lower-of satisfies both: a stale or
%       parent-mismatched rating can only cost margin, never grant it,
%       whereas superseding silently discards a number the user
%       deliberately entered. The ceiling applies to the ULTIMATE
%       criterion only — the rating is an ultimate allowable; the yield
%       criterion is a different limit state (onset of permanent
%       deformation) the ultimate rating says nothing about, and with any
%       factor set where FFY·FSY <= FFU·FSU a rating-capped yield
%       criterion could never govern below the rating-capped ultimate
%       anyway (R/PbYield − 1 >= R/Pb − 1). Deliberate, not incidental.
%
%       DESIGN-LOAD NOTE: this check uses the SAME thread-family
%       convention as its siblings (marginBoltThreadShear,
%       marginNutStrength, marginTappedParentThread, and the flat-rating
%       path below) — MS = allowable/Pb − 1 with the FF·FS factors INSIDE
%       Pb, on the external-load term only (preload not factored). The
%       yield criterion uses the yield-factored PbYield (FFY·FSY), NOT an
%       ultimate-factored load divided by yield factors — the same
%       FSU·FFU vs FSY·FFY pairing engine.designLoads expresses between
%       Ptu and Pty. engine.marginBearingUnderHead deliberately differs:
%       it factors the WHOLE unfactored Pb (preload included).
%
%   (2) MANUFACTURER RATED pull-out (the original fallback basis, unchanged
%       — runs only when NEITHER area source resolves: ShearEngagementArea is
%       NaN AND the computed form above could not be formed either): a
%       SINGLE spec-rated value on joint.ThreadedMember.RatedUltimateLoad — NOT the
%       0.75·pi·E·Le thread-shear calculation and NOT TM-106943's
%       three-mode insert split (Eq. 76-80). This mirrors NASA-STD-5020B's
%       use of specification-rated joint hardware strength (§4.4.1
%       fastening-system rationale; cf. §4.4.1 for spec-rated nuts).
%           MS = RatedUltimateLoad / Pb − 1
%       Note the ASYMMETRY with the tapped-hole check is deliberate:
%       engine.marginTappedParentThread stays ULTIMATE-ONLY (a yield
%       counterpart there is an open decision, deliberately not assumed) —
%       only the insert check carries the ultimate/yield pair.
%
%   In both bases the design bolt loads come from engine.boltDesignLoad
%   (NASA-STD-5020B Eq. 8 form; phi is COMPUTED for this threaded-in
%   configuration via the shortened grip L = t1 + D/2, falling back to the
%   conservative bound phi = 1 only when the frustum geometry is
%   incomplete). analyze() carries this check on the
%   "Insert internal-thread" row and leaves the "Insert external-thread"
%   row NotEvaluated (folded into the single row).
%
%   NotEvaluated (MS = NaN) when the configuration is not an insert; when
%   no basis is configured at all (no specified area, no computed area, and
%   no rated load — the reason distinguishes "no insert is catalogued for
%   this thread size" from an otherwise-catalogued insert's incomplete
%   configuration; see AREA SOURCE PRECEDENCE above); when an area (either
%   source) is available but the parent Fsu, or Fty/Fsy, is NaN (reason
%   names the missing property — no silent fallback to the flat rating, and
%   no criterion is silently skipped); or when Pb cannot be computed.
%   Reason in Detail; never crashes.
%
%   Returned struct fields:
%       MS        margin of safety (worst criterion on the area form;
%                 NaN = not evaluated)
%       Method    string: basis + citation (distinguishes the two bases)
%       Detail    string: governing criterion + numbers + Fsy basis (or the
%                 not-evaluated reason)
%       Rating    rated pull-out load participating in the check, lbf (the
%                 supplied value whenever it is set — as the flat basis or
%                 the ceiling on the area form; NaN when none is set or
%                 nothing evaluated)
%       Pb        ULTIMATE design bolt load, lbf (NaN if not computable)
%       PbYield   YIELD design bolt load (FFY·FSY pair), lbf (NaN unless
%                 the area form ran)
%       As        shear engagement area used by basis (1), in^2 — specified
%                 or computed (DERIVED), source stated in Detail (NaN on
%                 the flat-rating path) — named to match the sibling checks
%                 (marginBoltThreadShear, marginNutStrength,
%                 marginTappedParentThread), not "Area"
%       Pult      EFFECTIVE ultimate pull-out allowable actually used,
%                 min(A_shear·Fsu, rating), lbf (NaN unless the area form
%                 ran) — named to match the sibling checks' "Pult", not
%                 "AllowUlt"
%       AllowYld  yield pull-out allowable A_shear·Fsy, lbf (NaN unless the
%                 area form ran)
%
%   Call graph:
%       Precedents (calls)      engine.boltDesignLoad, engine.shearYieldStrength,
%                               memberTensileUltAllowable (private).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tThreadShear.m —
%                               insertUsesHelicoilRating,
%                               insertFlatRatingFallbackRegression (rated
%                               path, bit-identical regression guard);
%                               insertAreaYieldGovernsSuppliedFsy,
%                               insertAreaDerivedFsyFlagged,
%                               insertAreaUltimateGoverns (area-form
%                               ultimate/yield worst-of-two + derived-Fsy
%                               flag); insertRatingNotLimiting,
%                               insertRatingCeilingGoverns (rating
%                               ceiling, both sides);
%                               insertAreaNaNParentNotEvaluated;
%                               insertComputedAreaGovernsWhenUnspecified,
%                               insertSuppliedAreaWinsOverCatalogueGeometry,
%                               insertComputedAreaRatingStillCaps,
%                               insertUncataloguedSizeVsIncompleteConfigRefusal,
%                               insertComputedAreaGuardRefusesNonPositiveArea
%                               (AREA SOURCE PRECEDENCE: computed form,
%                               supplied-still-wins, rating ceiling on the
%                               computed area, the two distinguished
%                               refusal reasons, and the Le-1.125p guard);
%                               dabjSection9RegressionUnchanged (§9 answer
%                               key unchanged, both insert rows
%                               NotEvaluated, via engine.analyze).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 9).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

methodRated = "Heli-Coil rated pull-out (manufacturer spec value) per NASA-STD-5020B §4.4.1 (spec-rated insert); Pb per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, Pb = FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";
methodArea  = "Insert pull-out = shear engagement area x parent-material allowable shear stress. ULTIMATE (Fsu vs Pb with FFU·FSU) per NASA-STD-5020B §4.4.1, which defines pull-out against the parent's allowable ULTIMATE shear stress. The YIELD counterpart (Fsy vs PbYield with FFY·FSY) is this tool's own criterion, not a §4.4.1 formula -- §4.4.2 requires yield design loads but prints no pull-out equation, so the same area form is evaluated against the parent's shear yield strength and no equation number is claimed for it. Area is SPECIFIED (ThreadedMember.ShearEngagementArea) when supplied, else COMPUTED (DERIVED, no equation number, DEVELOPMENT_PLAN.md §2.3) from catalogue geometry As = 0.75·pi·D2·(Le-1.125·p) -- the 0.75·pi·E·Le pitch-diameter form (NASA TM-106943 Eq. 78/79 give a 5/8-coefficient area; the 0.75 coefficient is this tool's own convention, as in marginNutStrength/marginTappedParentThread) with D2 = ThreadedMember.StiPitchDiameter (NASM33537 Rev 4 Table IV STI pitch diameter) and the -1.125·p install-offset term derived from NASM33537 §11.1 (see Detail for the source actually used); rated pull-out as an ultimate ceiling when set (lower-of); Pb/PbYield per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";

if joint.ThreadedMember.Type ~= model.ThreadedMemberType.Insert
    r = notEval(methodRated, ...
        "Not evaluated: threaded member is not an insert (" + ...
        string(joint.ThreadedMember.Type) + ").");
    return
end

% Area resolution (specified override, else computed from STI catalogue
% geometry) + ultimate-allowable arithmetic all live in
% memberTensileUltAllowable, SHARED with engine.systemTensileAllowable
% (5020B §4.4.1 system minimum) so this row and the system allowable can
% never disagree about which area source governs or what it computes to.
ua = memberTensileUltAllowable(joint);
As      = ua.As;        % resolved area, in^2 (NaN -> flat-rating path / refusal)
areaSrc = ua.AreaSrc;    % "specified ..." or "computed (DERIVED) ..." — see Detail

% =========================================================================
% Basis (2): flat manufacturer rated pull-out — UNCHANGED original path.
% Runs when NEITHER area source resolved (ShearEngagementArea unset AND the
% computed-from-StiPitchDiameter form could not be formed either);
% arithmetic identical to the pre-area implementation (regression-guarded
% in tests/tThreadShear.m).
% =========================================================================
if isnan(As)
    rating = joint.ThreadedMember.RatedUltimateLoad;   % manufacturer rated pull-out, lbf
    if isnan(rating) || rating <= 0
        % ua.Reason already distinguishes "no insert is catalogued for
        % this thread size" (StiPitchDiameter NaN) from an
        % otherwise-catalogued insert's incomplete configuration (Le/TPI
        % missing, or the Le-1.125p guard) — see computeInsertArea.
        r = notEval(methodRated, "Not evaluated: " + ua.Reason + ".");
        return
    end

    % Pb: NASA-STD-5020B Eq. 8 (clamped, PpMax+FFU·FSU·n·phi·PtL) or, when
    % the Fig. 8 gate assures separation before rupture, Eq. 6 principle
    % (FFU·FSU·PtL, no preload/n·phi) — engine.boltDesignLoad picks the
    % branch; d.Note says which.
    d = engine.boltDesignLoad(joint, loadCase, factors, preload);
    if isnan(d.Pb)
        r = notEval(methodRated, "Not evaluated: " + d.Note + ".");
        r.Rating = rating;
        return
    end

    % MS = rated pull-out / Pb - 1 (TM-106943 Eq. 65 MS form on the spec rating)
    MS = rating / d.Pb - 1;

    detail = string(sprintf("rated pull-out %.0f lbf, Pb %.0f lbf", rating, d.Pb));
    if strlength(d.Note) > 0
        detail = detail + "; " + d.Note;
    end
    r = struct("MS", MS, "Method", methodRated, "Detail", detail + ".", ...
        "Rating", rating, "Pb", d.Pb, "PbYield", NaN, ...
        "As", NaN, "Pult", NaN, "AllowYld", NaN);
    return
end

% =========================================================================
% Basis (1): shear engagement area (specified or computed) x parent shear
% strength (5020B §4.4.1).
% =========================================================================
parent = joint.ThreadedMember.Material;   % PARENT material the insert is installed in
Fsu = parent.Fsu;                          % parent ultimate shear strength, psi
sy  = engine.shearYieldStrength(parent);   % supplied Fsy, or Fty/sqrt(3) von Mises estimate

if isnan(Fsu) || isnan(sy.Fsy)
    missing = strings(1, 0);
    if isnan(Fsu)
        missing(end+1) = "Fsu";                       %#ok<AGROW>
    end
    if isnan(sy.Fsy)
        missing(end+1) = "Fsy (and Fty to estimate it)"; %#ok<AGROW>
    end
    r = notEval(methodArea, ...
        "Not evaluated: a shear engagement area is available (" + areaSrc + ") but the parent " + ...
        "ThreadedMember.Material lacks " + join(missing, " and ") + ...
        " — both criteria are required (no silent fallback to the flat rating).");
    r.As = As;
    return
end

% Pb/PbYield: NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when
% the Fig. 8 gate assures separation before rupture, Eq. 6 principle
% (FF·FS·PtL, no preload/n·phi) — engine.boltDesignLoad picks the branch;
% d.Note says which.
d = engine.boltDesignLoad(joint, loadCase, factors, preload);
if isnan(d.Pb)
    r = notEval(methodArea, "Not evaluated: " + d.Note + ".");
    r.As = As;
    return
end

% NASA-STD-5020B §4.4.1 — allowable pull-out = (minimum shear engagement
% area) x (allowable shear stress of the parent material), both criteria,
% each vs the design bolt load built with its own factor pair (thread-family
% convention: MS = allowable/Pb − 1, factors inside Pb on the external term).
% The ultimate side (A_shear·Fsu) and the NASA-STD-5020B lower-of ceiling —
% a procured item's strength is limited to its specification rating (items
% can expand under load, reducing engagement areas; "the lower value should
% be used for strength analysis"):
%     ultimate allowable = min(A_shear·Fsu, RatedUltimateLoad)
% — are computed in memberTensileUltAllowable (shared with the system
% allowable; disposition in ua.RatNote), off THIS As regardless of whether
% it was specified or computed. The yield criterion is NOT capped: the
% rating is an ultimate quantity (see header).
allowUlt = ua.EffUlt;    % EFFECTIVE ultimate pull-out allowable, lbf
allowYld = As * sy.Fsy;  % yield pull-out allowable, lbf
ratNote  = ua.RatNote;
rating = joint.ThreadedMember.RatedUltimateLoad;   % rated pull-out, lbf (0 = unset)
%   ultimate: MS = min(A_shear·Fsu, rating) / Pb − 1, Pb = PpMax + FFU·FSU·n·phi·PtL (5020B Eq. 8)
MSu = allowUlt / d.Pb - 1;
%   yield:    MS = A_shear·Fsy / PbYield − 1, PbYield = PpMax + FFY·FSY·n·phi·PtL (5020B Eq. 8 form, yield factors)
MSy = allowYld / d.PbYield - 1;

% Worst criterion governs (marginBearing shape) — named in Detail.
if MSu <= MSy
    MS   = MSu;
    crit = "ultimate";
else
    MS   = MSy;
    crit = "yield";
end

detail = "Governing: " + crit + " — " + areaSrc + string(sprintf( ...
    ", parent %s Fsu %.0f psi, allowables ult %.0f / yld %.0f lbf, Pb ult %.0f / yld %.0f lbf", ...
    parent.Name, Fsu, allowUlt, allowYld, d.Pb, d.PbYield)) + "; " + sy.Basis;
if strlength(ratNote) > 0
    detail = detail + "; " + ratNote;
end
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end
if rating > 0
    ratingOut = rating;
else
    ratingOut = NaN;
end
r = struct("MS", MS, "Method", methodArea, "Detail", detail + ".", ...
    "Rating", ratingOut, "Pb", d.Pb, "PbYield", d.PbYield, ...
    "As", As, "Pult", allowUlt, "AllowYld", allowYld);
end

% ---- Local helpers --------------------------------------------------------
function r = notEval(method, detail)
%NOTEVAL  A full-field NotEvaluated result (every branch returns the same fields).
r = struct("MS", NaN, "Method", method, "Detail", string(detail), ...
    "Rating", NaN, "Pb", NaN, "PbYield", NaN, ...
    "As", NaN, "Pult", NaN, "AllowYld", NaN);
end
