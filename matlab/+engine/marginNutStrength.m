function r = marginNutStrength(joint, loadCase, factors, preload)
%MARGINNUTSTRENGTH  Nut internal-thread shear margin (Nut configuration only).
%   r = engine.marginNutStrength(joint, loadCase, factors, preload) checks
%   shear failure of the NUT's internal threads — the internal side of the
%   thread-stripping pair (the bolt-external side is
%   engine.marginBoltThreadShear; the weaker side governs via analyze()'s
%   worst-margin pick). Only evaluated when
%   joint.ThreadedMember.Type == Nut; otherwise MS = NaN (NotEvaluated).
%   preload is the struct from engine.preload. Loads in lbf, lengths in
%   inches, strengths in psi (see UNITS.md).
%
%   TWO BASES, one row (which one ran is stated in Method/Detail),
%   mirroring engine.marginInsert:
%
%   (1) THREAD-SHEAR-AREA form (runs whenever an area is available).
%       AREA BASIS (deliberate): internal-thread shear area in the
%       pitch-diameter form,
%           As = 0.75·pi·E·Le
%       with E = thread pitch diameter (joint.Bolt.PitchDiameter) and
%       Le = engagement length (the nut thread height), resolved by the
%       private helper resolveEngagementLength: joint.ThreadedMember.
%       EngagementRatio x Bolt.NominalDiameter when the ratio is set
%       (OVERRIDING EngagementLength — Detail says which), else the
%       unchanged joint.ThreadedMember.EngagementLength. This is NASA TM-106943 (Chambers) Eq. 76's
%       internal-thread shear area (3/4·pi coefficient; Eq. 76 is the
%       THREADED-INSERT section's INTERNAL thread failure mode — a bolt
%       pulling out of a single internal thread, the same single-interface
%       geometry as a nut, which is why its area form is the right thing
%       to borrow) with a pitch-diameter substitution (TM's printed Eq. 76
%       uses the mating external-thread MAJOR diameter). The pitch diameter
%       is the smaller of the two, so the substitution shrinks the area and
%       is the conservative choice; the same 0.75·pi·E·Le form is used for
%       every internal-thread shear area in this engine.
%       TM-106943's own NUT STRENGTH section (p. 24) is a different,
%       spec-rated form — Eq. 81, Puh = (125,000)*At — Class II nuts
%       developing the full tensile strength of a 125-ksi bolt, At on the
%       basic pitch diameter, tabulated in its Table VI (Eq. 80 is that
%       section's MS form); this code deliberately does NOT use Eq. 81,
%       computing instead from the actual nut material and engagement (a
%       supplied rating still participates as a ceiling — see RATING AS A
%       CEILING below). NASA-STD-5020B prints no thread-shear-area
%       equation. The area is ALWAYS the computed 0.75·pi·E·Le:
%       joint.ThreadedMember.ShearEngagementArea is deliberately NOT read
%       on the nut path, because §4.4.1 gives a nut a rated LOAD and
%       contemplates no shear engagement area for one at all (the insert
%       path is the opposite case — see engine.marginInsert). The area drives
%       BOTH criteria (marginBearing shape — worst governs, criterion named
%       in Detail), each against the design bolt load built with ITS OWN
%       factor pair (engine.boltDesignLoad, NASA-STD-5020B Eq. 8 form):
%           ultimate: MS = As·Fsu / Pb − 1,       Pult = Fsu·As
%                     (TM-106943 Eq. 77), with
%                     Pb      = PpMax + FFU·FSU·n·phi·PtL
%           yield:    MS = As·Fsy / PbYield − 1   (Eq. 77 form with the
%                     shear YIELD strength — a yield counterpart carried
%                     beside the ultimate, because NASA-STD-5020B §4.4.2
%                     requires yield design loads be assessed even where it
%                     prints no thread-shear equation), with
%                     PbYield = PpMax + FFY·FSY·n·phi·PtL
%       both in the TM-106943 Eq. 65 MS form (MS = allowable/load − 1),
%       with Fsu/Fsy of joint.ThreadedMember.Material (the NUT material).
%       A NaN Fsy is estimated as Fty/sqrt(3) (von Mises) via
%       engine.shearYieldStrength — the estimate is ALWAYS flagged in
%       Detail so a constitutive assumption never masquerades as test data.
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
%       RATING AS A CEILING (NASA-STD-5020B §4.4.1): 5020B directs that
%       "nuts should be limited to the load rating of the nut" and that a
%       procured item's strength be based on its specification rating
%       rather than thread-stripping analysis, because such items can
%       expand (dilate) under load, reducing the thread engagement areas —
%       a computed engagement area is therefore OPTIMISTIC. So a supplied
%       joint.ThreadedMember.RatedUltimateLoad does not compete with the
%       area form; it CAPS it:
%           ultimate allowable = min(As·Fsu, RatedUltimateLoad)
%       and Detail names which source governs. Lower-of means a stale or
%       mismatched rating can only cost margin, never grant it. The
%       ceiling applies to the ULTIMATE criterion only — the rating is an
%       ultimate allowable; the yield criterion is a different limit state
%       (onset of permanent deformation) the ultimate rating says nothing
%       about, and with any factor set where FFY·FSY <= FFU·FSU a
%       rating-capped yield criterion could never govern below the
%       rating-capped ultimate anyway (R/PbYield − 1 >= R/Pb − 1). The
%       choice is deliberate, not incidental.
%
%   (2) FLAT SPEC-RATED fallback (runs only when NO area is available —
%       PitchDiameter and the resolved Le (via resolveEngagementLength) not
%       both set): the spec-rated nut ultimate
%       load alone, per
%       NASA-STD-5020B §4.4.1 (nut limited to its load rating):
%           MS = RatedUltimateLoad / Pb − 1    (TM-106943 Eq. 65 MS form)
%       ULTIMATE-ONLY — a rating carries no yield information, so no yield
%       criterion is formed on this path (Detail says so). DABJ §9
%       exercises this basis (RatedUltimateLoad = 15,200 lbf, no area); see
%       VALIDATION.md's DABJ §9 + Phase 3.3 interplay note for why that
%       fixture still stays NotEvaluated.
%
%   In both bases the design bolt loads come from engine.boltDesignLoad
%   (NASA-STD-5020B Eq. 8 form). Same thread-family design-load convention
%   as the sibling checks: FF·FS factors INSIDE Pb, on the external-load
%   term only, yield criterion vs the yield-factored PbYield (see the
%   DESIGN-LOAD NOTE in engine.marginInsert).
%
%   NotEvaluated (MS = NaN) when the configuration is not a nut; when no
%   basis is configured (no usable area AND no rating); when an area is
%   available but the nut Fsu, or Fty/Fsy, is NaN (reason names the
%   missing property — no silent fallback to the flat rating, and no
%   criterion is silently skipped, mirroring engine.marginInsert); or when
%   Pb cannot be computed. Reason in Detail; never crashes.
%
%   Returned struct fields:
%       MS        margin of safety (worst criterion on the area form;
%                 NaN = not evaluated)
%       Method    string: basis + citation (distinguishes the two bases)
%       Detail    string: governing criterion + numbers + area source +
%                 Fsy basis + rating disposition (or the not-evaluated
%                 reason)
%       As        thread-shear area used, in^2 (always the computed
%                 0.75·pi·E·Le; NaN on the flat-rating path / not evaluated)
%       Pult      EFFECTIVE ultimate allowable actually used, lbf:
%                 min(As·Fsu, rating) on the area form, the rating on the
%                 flat path (NaN if not evaluated)
%       AllowYld  yield allowable As·Fsy, lbf (NaN unless the area form ran)
%       Pb        ULTIMATE design bolt load, lbf (NaN if not computable)
%       PbYield   YIELD design bolt load (FFY·FSY pair), lbf (NaN unless
%                 the area form ran)
%       Rating    spec-rated nut ultimate load participating in the check,
%                 lbf (the supplied value whenever it is set — as the
%                 flat basis or the ceiling; NaN when none is set)
%
%   Call graph:
%       Precedents (calls)      engine.boltDesignLoad, engine.shearYieldStrength,
%                               memberTensileUltAllowable (private).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tThreadShear.m —
%                               nutStrengthHandDerived, nutYieldGovernsHandDerived,
%                               nutSuppliedAreaIsIgnored,
%                               nutRatingCeilingGoverns, nutRatingNotLimiting,
%                               nutRatingOnlyFallback, nutDerivedFsyFlagged
%                               (area/yield/ceiling pins);
%                               dabjNutRatingFallbackStaysNotEvaluated
%                               (DABJ §9 regression guard, direct call);
%                               dabjSection9RegressionUnchanged (§9 answer
%                               key unchanged, via engine.analyze).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 8).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

methodArea = "TM-106943 Eq. 76 (nut internal thread shear) via the As = 0.75·pi·E·Le pitch-diameter form + Eq. 77 allowable Pult = Fsu·As (yield counterpart Fsy·As vs PbYield with FFY·FSY), Eq. 65 MS; spec rating per NASA-STD-5020B §4.4.1 as an ultimate ceiling when set; Pb/PbYield per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";
methodRated = "Nut spec-rated ultimate load (NASA-STD-5020B §4.4.1 — nut limited to its load rating), Eq. 65 MS form; ultimate-only (a rating carries no yield information); Pb per NASA-STD-5020B Eq. 8 (clamped, PpMax+FF·FS·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, Pb = FF·FS·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";

if joint.ThreadedMember.Type ~= model.ThreadedMemberType.Nut
    r = notEval(methodArea, ...
        "Not evaluated: threaded member is not a nut (" + ...
        string(joint.ThreadedMember.Type) + ").");
    return
end

rating = joint.ThreadedMember.RatedUltimateLoad;   % spec-rated nut Pult, lbf (0 = unset)

% ---- Resolve the thread-shear area (always computed) ---------------------
% Area + ultimate-allowable arithmetic live in memberTensileUltAllowable,
% SHARED with engine.systemTensileAllowable (5020B §4.4.1 system minimum)
% so this row and the system allowable can never disagree: the TM-106943
% Eq. 76 pitch-diameter form As = 0.75·pi·E·Le, else NaN (flat-rating fallback
% below). A per-joint ShearEngagementArea is NOT consulted on the nut path.
ua = memberTensileUltAllowable(joint);
As      = ua.As;
areaSrc = ua.AreaSrc;

% =========================================================================
% Basis (2): flat spec-rated ultimate load — runs only when no area is
% available (NASA-STD-5020B §4.4.1: nut limited to its load rating).
% =========================================================================
if isnan(As)
    if rating <= 0
        r = notEval(methodArea, ...
            "Not evaluated: no thread-shear area (needs Bolt.PitchDiameter + " + ...
            "ThreadedMember.EngagementLength or EngagementRatio x Bolt.NominalDiameter) " + ...
            "and no spec-rated load (ThreadedMember.RatedUltimateLoad).");
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

    % TM-106943 Eq. 65 MS form on the spec rating — MS = rating/Pb − 1
    % (NASA-STD-5020B §4.4.1: nut limited to the load rating of the nut)
    MS = rating / d.Pb - 1;

    detail = string(sprintf( ...
        "spec-rated nut ultimate load %.0f lbf, Pb %.0f lbf; ultimate-only (no area/Fsy to form a yield criterion)", ...
        rating, d.Pb));
    if strlength(d.Note) > 0
        detail = detail + "; " + d.Note;
    end
    r = struct("MS", MS, "Method", methodRated, "Detail", detail + ".", ...
        "As", NaN, "Pult", rating, "AllowYld", NaN, ...
        "Pb", d.Pb, "PbYield", NaN, "Rating", rating);
    return
end

% =========================================================================
% Basis (1): thread-shear area x nut shear strength, ultimate + yield,
% spec rating (when set) capping the ultimate allowable.
% =========================================================================
nut = joint.ThreadedMember.Material;      % the NUT material
Fsu = nut.Fsu;                            % nut ultimate shear strength, psi
sy  = engine.shearYieldStrength(nut);     % supplied Fsy, or Fty/sqrt(3) von Mises estimate

if isnan(Fsu) || isnan(sy.Fsy)
    missing = strings(1, 0);
    if isnan(Fsu)
        missing(end+1) = "Fsu";                       %#ok<AGROW>
    end
    if isnan(sy.Fsy)
        missing(end+1) = "Fsy (and Fty to estimate it)"; %#ok<AGROW>
    end
    r = notEval(methodArea, ...
        "Not evaluated: a thread-shear area is available but the nut " + ...
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

% TM-106943 Eq. 77 — Pult = Fsu·As (nut internal-thread shear allowable;
% computed in memberTensileUltAllowable as ua.AllowUlt, shared with the
% system allowable)
% Eq. 77 form with the shear YIELD strength — Pyld = Fsy·As (the yield
% counterpart; Fsy per engine.shearYieldStrength, basis surfaced in Detail)
allowYld = sy.Fsy * As;   % yield allowable, lbf

% NASA-STD-5020B §4.4.1 — the nut is "limited to the load rating of the
% nut": the spec rating CAPS the computed ultimate allowable (lower-of;
% nuts dilate under load, so the computed area is optimistic) —
%     ultimate allowable = min(Fsu·As, RatedUltimateLoad)
% (cap applied in memberTensileUltAllowable; disposition in ua.RatNote).
% The yield criterion is NOT capped: the rating is an ultimate quantity
% (see header).
effUlt  = ua.EffUlt;
ratNote = ua.RatNote;

% TM-106943 Eq. 65 MS form, each criterion vs the design bolt load built
% with its own factor pair (thread-family convention — factors inside Pb,
% external term only):
%   ultimate: MS = min(Fsu·As, rating) / Pb − 1, Pb = PpMax + FFU·FSU·n·phi·PtL (5020B Eq. 8)
MSu = effUlt / d.Pb - 1;
%   yield:    MS = Fsy·As / PbYield − 1, PbYield = PpMax + FFY·FSY·n·phi·PtL (5020B Eq. 8 form, yield factors)
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
    ", nut %s Fsu %.0f psi, allowables ult %.0f / yld %.0f lbf, Pb ult %.0f / yld %.0f lbf", ...
    nut.Name, Fsu, effUlt, allowYld, d.Pb, d.PbYield)) + "; " + sy.Basis;
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
    "As", As, "Pult", effUlt, "AllowYld", allowYld, ...
    "Pb", d.Pb, "PbYield", d.PbYield, "Rating", ratingOut);
end

% ---- Local helpers --------------------------------------------------------
function r = notEval(method, detail)
%NOTEVAL  A full-field NotEvaluated result (every branch returns the same fields).
r = struct("MS", NaN, "Method", method, "Detail", string(detail), ...
    "As", NaN, "Pult", NaN, "AllowYld", NaN, ...
    "Pb", NaN, "PbYield", NaN, "Rating", NaN);
end
