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
%       the insert is installed in).
%
%       This yield criterion, though it carries no equation number, matches
%       an independent construction: scaling the ultimate allowable
%       (As*Fsu) by the parent's shear yield/ultimate ratio gives
%       As*Fsu*(Fsy/Fsu) = As*Fsy — the same result as computing the
%       insert's yield tensile strength as (ultimate tensile strength x
%       parent Fsy) / parent Fsu. So this is the standard construction
%       rather than something invented here; §4.4.2 simply prints no
%       pull-out equation to number it with.
%
%       A NaN Fsy is estimated as Fty/sqrt(3)
%       (NASA-STD-5020B Eq. 63, von Mises) via engine.shearYieldStrength —
%       the estimate is ALWAYS
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
%             thread pitch. The "− 1.125·p" term is a derived
%             convention — no published equation, no equation number
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
%         (d) else NotEvaluated — and the reason distinguishes "no insert
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
%       RATING DOES NOT CAP THIS ROW. RatedUltimateLoad is a separate
%       §4.4.1 allowable — the insert's internal-thread capability
%       (engine.marginInsertInternal) — not a ceiling on the parent
%       pull-out computed here; capping here would hide which mode
%       governs. NASA-STD-5020B's "the lower value should be used for
%       strength analysis" is instead satisfied ACROSS the two rows by
%       analyze()'s worst-margin pick. (The rating DOES cap the SYSTEM
%       tension allowable computed in memberTensileUltAllowable / ua.EffUlt
%       — a different, system-level minimum from this per-mode row; see
%       the comment by allowUlt below.)
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
%       Rating    ThreadedMember.RatedUltimateLoad, echoed for traceability
%                 ONLY — it does not participate in this check. It is the
%                 insert's INTERNAL-THREAD allowable (marginInsertInternal),
%                 a different failure mode; NaN when none is set or
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
%   YIELD CRITERION SCOPE. TM-106943 Eq. 80 (p24) scopes its own
%   thread-shear modes to "the margin of safety ... for ultimate strength
%   only, to determine the limiting mode of failure" — no yield margin is
%   asked for. NASA-STD-5020B §4.4.2 (p29) separately requires the yield
%   assessment to "address all elements of the threaded fastening system,"
%   but that is discharged by engine.systemTensileYieldAllowable, which
%   folds this member's As·Fsy into the Tension-Yield row's Pty_allow.
%
%   This row's yield criterion is therefore supplemental to both documents
%   — neither TM's method nor 5020B's requirement — kept because a
%   governing yield mode is worth naming rather than left buried inside a
%   system minimum. engine.marginTappedParentThread is the consistent one:
%   ultimate only, exactly as Eq. 80 says.
arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

methodRated = "Insert pull-out from the parent per NASA-STD-5020B §4.4.1 — NOT EVALUATED without a shear engagement area. There is no flat-rated fallback: ThreadedMember.RatedUltimateLoad is the insert INTERNAL-THREAD allowable (engine.marginInsertInternal), a different failure mode, and reporting it here would put an internal-thread capability under a pull-out heading. Pb per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, Pb = FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";
methodArea  = "Insert pull-out = shear engagement area x parent-material allowable shear stress. ULTIMATE (Fsu vs Pb with FFU·FSU) per NASA-STD-5020B §4.4.1, which defines pull-out against the parent's allowable ULTIMATE shear stress. The YIELD counterpart (Fsy vs PbYield with FFY·FSY) is this tool's own CRITERION, not a §4.4.1 formula -- §4.4.2 requires yield design loads but prints no pull-out equation, so the same area form is evaluated against the parent's shear yield strength; no equation number is claimed for the CRITERION, though the Fsy inside it is NASA-STD-5020B Eq. 63 (p66, Appendix A.8), Fsy = Fty/sqrt(3), per §4.4.2 p31's direction to use a failure theory. Area is SPECIFIED (ThreadedMember.ShearEngagementArea) when supplied, else COMPUTED (DERIVED, no equation number, DEVELOPMENT_PLAN.md §2.3) from catalogue geometry As = 0.75·pi·D2·(Le-1.125·p) -- the 0.75·pi·E·Le pitch-diameter form (NASA TM-106943 Eq. 78/79 give a 5/8-coefficient area; the 0.75 coefficient is this tool's own convention, as in marginNutStrength/marginTappedParentThread) with D2 = ThreadedMember.StiPitchDiameter (NASM33537 Rev 4 Table IV STI pitch diameter) and the -1.125·p install-offset term derived from NASM33537 §11.1 (see Detail for the source actually used). UNCAPPED: ThreadedMember.RatedUltimateLoad is the insert INTERNAL-THREAD allowable and is checked on its own row, so §4.4.1's rule that the lower value should be used is applied ACROSS the two rows by analyze()'s worst-margin pick rather than hidden inside this one. SCOPE LIMIT (§4.4.1 p27): ''Such an allowable pull-out load applies when the insert is installed in a solid, homogenous material. For inserts installed in nonhomogeneous or nonmetallic materials or in sandwich panels, allowable pull-out loads should be derived from test.'' This computed form therefore ASSUMES a solid homogeneous parent; the tool models no panel construction and cannot detect otherwise. Pb/PbYield per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";

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
    % No pull-out area, so no pull-out answer. There is no flat-rating
    % fallback: ThreadedMember.RatedUltimateLoad is the insert's
    % internal-thread allowable, checked on its own row
    % (engine.marginInsertInternal) — reporting it here would conflate the
    % two allowables NASA-STD-5020B §4.4.1 names, putting an
    % internal-thread capability under a pull-out heading.
    % ua.Reason is EMPTY when a rating let the shared helper assess the
    % mode for the system minimum; the area refusal still has to be
    % reported here, because this row is the OTHER allowable.
    why = ua.Reason;
    if strlength(why) == 0
        why = ua.AreaReason;
    end
    if strlength(why) == 0
        why = "no shear engagement area could be resolved";
    end
    r = notEval(methodArea, "Not evaluated: " + why + ". (An insert's " + ...
        "internal-thread allowable is a separate check on its own row.)");
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
% area) x (allowable shear stress of the parent material), each criterion
% vs the design bolt load built with its own factor pair (thread-family
% convention: MS = allowable/Pb − 1, factors inside Pb on the external term).
% memberTensileUltAllowable also computes a lower-of ceiling,
% min(A_shear·Fsu, RatedUltimateLoad) (ua.EffUlt) — a procured item's
% strength is limited to its specification rating (items can expand under
% load, reducing engagement areas; "the lower value should be used for
% strength analysis") — but that ceiling belongs to the SYSTEM allowable,
% not this row: the rating is the OTHER §4.4.1 allowable (the insert's
% internal-thread capability, on its own row), so capping pull-out with it
% here would hide which mode governs. engine.analyze carries both modes as
% rows and WorstMargin takes the lower — the same answer, with the reason
% visible. The yield criterion is never capped: the rating is an ultimate
% quantity.
allowUlt = As * Fsu;     % ultimate pull-out allowable, lbf
% Yield through memberTensileYldAllowable, SHARED with
% engine.systemTensileYieldAllowable so this row and the system yield
% minimum can never disagree — the arrangement the ultimate side already has.
ya       = memberTensileYldAllowable(joint);
allowYld = ya.AllowYld;  % yield pull-out allowable, lbf  (= As * sy.Fsy)
% Echoed into the returned struct for traceability only — this row is
% UNCAPPED (see the header). The value is the insert's internal-thread
% allowable, checked by engine.marginInsertInternal.
rating = joint.ThreadedMember.RatedUltimateLoad;   % internal-thread allowable, lbf (0 = unset)
%   ultimate: MS = A_shear·Fsu / Pb − 1, Pb = PpMax + FFU·FSU·n·phi·PtL (5020B Eq. 8)
%             UNCAPPED — the rating is the OTHER §4.4.1 allowable, on its own row.
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

% Detail stays qualitative — which criterion governed, where the area came
% from, how Fsy was obtained, which Pb branch ran; the arithmetic is read
% off the Inputs list.
detail = "Governing: " + crit + " — parent " + parent.Name + ", " + ...
    areaSrc + "; " + sy.Basis;
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
    "As", As, "Pult", allowUlt, "AllowYld", allowYld, ...
    "Inputs", [areaInputs(joint, As, areaSrc), ...
        engine.eqInput("Fsu", Fsu, "psi", ...
            "ThreadedMember.Material.Fsu (PARENT, not the insert)"), ...
        engine.eqInput("Fsy", sy.Fsy, "psi", ...
            "engine.shearYieldStrength (PARENT)"), ...
        engine.eqInput("Pult", allowUlt, "lbf", ...
            "5020B 4.4.1 = As*Fsu"), ...
        engine.eqInput("Pyld", allowYld, "lbf", ...
            "tool's own yield criterion = As*Fsy"), ...
        engine.eqInput("Pb", d.Pb, "lbf", ...
            "engine.boltDesignLoad (ultimate)" + noteSuffix(d.Note)), ...
        engine.eqInput("PbYield", d.PbYield, "lbf", ...
            "engine.boltDesignLoad (yield, FFY*FSY pair)" + noteSuffix(d.Note))]);
end

% ---- Local helpers --------------------------------------------------------

function terms = areaInputs(joint, As, areaSrc)
%AREAINPUTS  The area term, plus the geometry behind it when it was DERIVED.
%   A SPECIFIED area is one number and there is nothing underneath it. A
%   COMPUTED one is 0.75*pi*D2*(Le - 1.125*p), and the three inputs to that
%   are exactly what an analyst comparing this row against another tool
%   needs — the STI pitch diameter, the engagement length, and the pitch —
%   because a pull-out disagreement is almost always one of them rather
%   than the product.
%
%   Read off the joint rather than returned from computeInsertArea: this
%   branch only runs when that helper already resolved all three, so there
%   is nothing to re-derive and no second definition to drift.
if startsWith(areaSrc, "specified")
    terms = engine.eqInput("As", As, "in^2", "ThreadedMember.ShearEngagementArea");
else
    terms = engine.eqInput("As", As, "in^2", "DERIVED = 0.75*pi*D2*(Le-1.125p)");
end
if startsWith(areaSrc, "specified")
    return
end
p = 1 / joint.Bolt.ThreadsPerInch;
terms = [ ...
    engine.eqInput("D2", joint.ThreadedMember.StiPitchDiameter, "in", ...
        "STI tapped-hole pitch dia, NASM33537 Table IV"), ...
    engine.eqInput("Le", resolveEngagementLength(joint).Le, "in", ...
        "resolveEngagementLength"), ...
    engine.eqInput("p", p, "in", ...
        "1/Bolt.ThreadsPerInch"), ...
    engine.eqInput("Le-1.125p", resolveEngagementLength(joint).Le - 1.125 * p, "in", ...
        "DERIVED, no eq. no. - NASM33537 11.1 install offset"), ...
    terms];
end

function s = noteSuffix(note)
%NOTESUFFIX  " - <note>", or "" when there is no note.
%   boltDesignLoad's Note says WHICH branch set Pb (the clamped Eq. 8 form,
%   or Eq. 6 when the Fig. 8 gate assured separation before rupture) — the
%   first thing to check when a Pb disagrees. Empty on the ordinary path,
%   where concatenating it would leave a dangling dash.
if strlength(note) == 0
    s = "";
else
    s = " - " + note;
end
end

function r = notEval(method, detail)
%NOTEVAL  A full-field NotEvaluated result (every branch returns the same fields).
r = struct("MS", NaN, "Method", method, "Detail", string(detail), ...
    "Rating", NaN, "Pb", NaN, "PbYield", NaN, ...
    "As", NaN, "Pult", NaN, "AllowYld", NaN, ...
    "Inputs", engine.eqInput());
end
