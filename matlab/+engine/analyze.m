function r = analyze(joint, loadCase, factors)
%ANALYZE  Run every margin check for one joint -> one engine.Result.
%   r = engine.analyze(joint, loadCase, factors) is the single-joint solver:
%   it computes the preloads and design loads, runs each built margin check,
%   and returns the one standard engine.Result that every consumer (report,
%   GUI, bulk table) reads. All loads in lbf, temperatures in degC (see
%   UNITS.md).
%
%   Evaluated checks (each function carries its own point-of-use equation
%   citations; their Method strings are surfaced in Result.Margins):
%       Tension-Ultimate   engine.marginTensionUlt   NASA-STD-5020B Eq. 6 (assured) / Eq. 10 (rupture) + Fig. 8 gate; Ptu-allow = FASTENING-SYSTEM allowable (§4.4.1, engine.systemTensileAllowable)
%       Tension-Yield      engine.marginTensionYield NASA-STD-5020B Eq. 15
%       Shear-Ultimate     engine.marginShearUlt     NASA-STD-5020B Eq. 12/13 + Eq. 14
%       Interaction        engine.marginInteraction  NASA-STD-5020B Eq. 20-23 —
%                          a CRITERION (R <= 1), not a margin; see the
%                          INTERACTION IS NOT A MARGIN note below
%       Separation         engine.marginSeparation   NASA-STD-5020B Eq. 19
%       Slip               engine.marginSlip         NASA-STD-5020B Eq. 84 (joint) / Eq. 86 (single-fastener), per joint.SlipMode; Ignored -> NotEvaluated
%       Bearing            engine.marginBearing            NASA TM-106943 Eq. 72-74 (required by 5020B §4.4.2)
%       Bearing-under-head engine.marginBearingUnderHead   NASA TM-106943 Eq. 74/75 + 5020B Eq. 8 (Pb)
%       Shear-tearout      engine.marginShearTearout       NASA TM-106943 Eq. 69-71 (required by 5020B §4.4.2)
%       Bolt-thread shear  engine.marginBoltThreadShear    TM-106943 Eq. 63/64/65, pitch-diameter As = 0.75·pi·E·Le form; Pb per 5020B Eq. 8
%       Nut strength       engine.marginNutStrength        TM-106943 Eq. 76/77 + Eq. 65, same As form, ult/yld pair; spec rating as ultimate ceiling per 5020B §4.4.1 (Nut config only)
%       Insert internal    engine.marginInsert             Shear-engagement-area x parent shear strength (ult/yld pair, rated pull-out as ultimate ceiling) or rated pull-out alone, 5020B §4.4.1 (Insert config only)
%       Tapped parent      engine.marginTappedParentThread TM-106943 Eq. 79 + Eq. 65, same As form (TappedHole config only)
%   plus the Separation-before-rupture gate (NASA-STD-5020B Fig. 8), a
%   boolean check reported as its own Margins row (Pass = assured) and as
%   Result.Narrative.
%
%   The Margins array always advertises the FULL 15-check set (PRD 5.1);
%   every check reports NotEvaluated (MS = NaN) when its inputs are not
%   configured — real results ship without fake numbers (no EdgeDistance
%   -> no tear-out; no HoleDiameter / stiffness geometry -> no
%   bearing-under-head; no flange bearing allowables -> no bearing; no
%   PitchDiameter / EngagementLength or EngagementRatio / stiffness geometry -> no thread
%   checks; no insert rating or shear engagement area -> no insert check).
%   The thread-stripping
%   pair is covered by two rows — bolt-external (bolt Fsu) and the
%   internal side (nut, insert, or tapped parent Fsu) — the weaker side governs through
%   the WorstMargin pick. The "Insert external-thread" row stays
%   NotEvaluated by design: this tool carries ONE pull-out result for the
%   whole insert (on the "Insert internal-thread" row), not the
%   TM-106943 three-mode insert split.
%
%   Status thresholds (bookkeeping, not equations): MS >= 0 -> "Pass",
%   MS < 0 -> "Fail", NaN -> "NotEvaluated". WorstMargin is the minimum MS
%   over the evaluated checks; GoverningCheck is that check's Name.
%
%   WARNINGS (Result.Warnings, zero or more rows, NOT margins -- they never
%   affect WorstMargin/GoverningCheck and carry no Margins row of their
%   own): two pure, never-throwing queries are run on every analyze() call,
%   bolt length first then preload, matching the GUI's banner order
%   (GUI_PORT_SPEC.md Section 4):
%     engine.boltLengthCheck  -> "BoltLengthShort" (Warning) when
%       Shortfall > 0 (NaN Shortfall, i.e. not evaluated, never fires) --
%       its own Method/Detail are reused verbatim, no re-derivation here.
%     engine.preloadWatchdog  -> "PreloadNearYield" (Warning) /
%       "PreloadExceedsYield" / "PreloadExceedsUltimate" (both Critical)
%       when its Name is non-empty -- again, Method/Detail reused verbatim.
%   Both underlying functions are documented as NEVER THROWING and
%   NaN-tolerant, so adding them here cannot turn a previously-successful
%   analyze() call into a failing one.
%
%   INTERACTION IS NOT A MARGIN, and is deliberately excluded from the
%   WorstMargin/GoverningCheck pick. engine.marginInteraction reports a
%   ratio R (NASA-STD-5020B Eq. 20-23 states this check as a pass/fail
%   CRITERION, R <= 1, never as a margin equation) — R and MS live on
%   different, non-comparable scales (R = 0.86 is a healthy pass; MS = 0.86
%   would be a large pass; R = 1.2 fails while MS = 1.2 would be a huge
%   pass), so folding R into the same min() as the other 14 true margins
%   would make WorstMargin meaningless whenever Interaction happened to be
%   numerically smallest. Its Margins row therefore carries MS = NaN (so
%   it is automatically excluded from the WorstMargin min by the same NaN
%   filter every other NotEvaluated row uses) but a Status set DIRECTLY
%   from R <= 1 (Pass/Fail), NOT from the NaN -> NotEvaluated rule — the
%   same pattern already used here for the boolean Separation-before-
%   rupture gate row (sbr, below): a real, non-margin result, MS = NaN,
%   Status independently computed, excluded from the min but never hidden
%   (Detail carries R itself). A failing interaction is therefore visible
%   as its own Fail row in the full 15-check Margins table even though it
%   cannot move WorstMargin/GoverningCheck — callers must check every
%   row's Status, not just WorstMargin, to know a joint is fully clean
%   (already true of this table in general: see the PRD 5.1 "full 15-check
%   set" note below).
%
%   R ALSO LIVES ON ITS OWN Margins.R FIELD (added alongside MS, never
%   inside it — see the local entry() helper below), NaN on every row
%   except "Interaction". This is what lets downstream consumers
%   (engine.analyzeBulk, report.singleJointReport, the GUI Results row and
%   Bulk grid) carry the real ratio through to their own tables/exports
%   without ever reading it out of MS (which stays NaN for this row by
%   design, per the note above) or risking a caller applying the MS >= 0
%   sign test to a value that passes at R <= 1 instead.
%
%   Call graph:
%       Precedents (calls)      18 engine functions: engine.preload,
%                               engine.designLoads; the six margin checks
%                               marginTensionUlt, marginTensionYield,
%                               marginShearUlt, marginInteraction,
%                               marginSeparation, marginSlip; the three
%                               member checks marginBearing,
%                               marginShearTearout, marginBearingUnderHead;
%                               the four thread checks
%                               marginBoltThreadShear, marginNutStrength,
%                               marginInsert, marginTappedParentThread;
%                               boltLengthCheck, preloadWatchdog; and the
%                               engine.Result constructor.
%       Dependents (called by)  engine.analyzeBulk, gui.FastenerApp
%                               (single-joint Results tab and the per-row
%                               bulk path), report.singleJointReport.
%       Tests                   tests/tDabjCase.m
%                               analyzeReproducesAllDABJMargins (the DABJ
%                               §9 regression); tests/tSystemAllowable.m
%                               dabjAnswerKeyUnchanged; tests/tBearing.m
%                               dabjSection9RegressionUnchanged;
%                               tests/tCaseIO.m caseRoundTripsLossless;
%                               tests/tBulk.m
%                               bulkFailingInteractionVisibleButNeverGoverns;
%                               tests/tThreadShear.m
%                               dabjNutRatingFallbackStaysNotEvaluated /
%                               dabjSection9RegressionUnchanged.
%
%   Validation status/coverage: VALIDATION.md's Structural/non-numeric
%   table, row "Solver `analyze()` + `Result` (15-row)", pins the DABJ §9
%   answer key; Margin-checks rows 1-3 and 10-13 cover the individual
%   checks this fixture reproduces. The same fixture also regression-guards
%   row 5 (Bearing, tests/tBearing.m dabjSection9RegressionUnchanged) — a
%   later check must never disturb an earlier fixture's answer key.

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

% ---- Supporting computations --------------------------------------------
p = engine.preload(joint);                  % NASA-STD-5020B Eq. 3/4/5 + Eq. 24 + Eq. 1/2
d = engine.designLoads(loadCase, factors);  % NASA-STD-5020B design load = FS x FF x limit

% ---- The six built margin checks (Phases 2.5-2.8) ------------------------
tu = engine.marginTensionUlt(joint, p, d);           % NASA-STD-5020B Eq. 6 / Eq. 10 + Fig. 8 gate
ty = engine.marginTensionYield(joint, p, d);         % NASA-STD-5020B Eq. 15 / Eq. 16-17 + Fig. 8 gate
su = engine.marginShearUlt(joint, d);                % NASA-STD-5020B Eq. 12/13 + Eq. 14
ia = engine.marginInteraction(joint, d);             % NASA-STD-5020B Eq. 20-23 criterion (R <= 1) — NOT a margin, see below
sp = engine.marginSeparation(p, d);                  % NASA-STD-5020B Eq. 19
sl = engine.marginSlip(joint, loadCase, p, factors); % NASA-STD-5020B Eq. 84 (Joint) / Eq. 86 (SingleFastener) per joint.SlipMode; Ignored -> MS NaN -> NotEvaluated

% ---- The three member checks (Phase 3.2) ---------------------------------
br = engine.marginBearing(joint, loadCase, factors);            % NASA TM-106943 Eq. 72-74 (bolt bearing; required by 5020B §4.4.2)
to = engine.marginShearTearout(joint, loadCase, factors);       % NASA TM-106943 Eq. 69-71 (shear tear-out; required by 5020B §4.4.2)
bh = engine.marginBearingUnderHead(joint, loadCase, factors, p); % NASA TM-106943 Eq. 74/75 + 5020B Eq. 8 Pb = PpMax + n·phi·PtL

% ---- The four thread-strength checks (Phase 3.3) -------------------------
% Thread-stripping is checked on BOTH sides of the engagement: the
% bolt-external threads (bolt Fsu) and the internal side (nut, insert or
% tapped parent, per configuration) — the weaker side governs via the
% WorstMargin pick. The bolt, nut and tapped-parent checks use the
% pitch-diameter area form As = 0.75·pi·E·Le (E = pitch dia, Le =
% engagement); the INSERT
% check does not — it takes a supplied shear engagement area or the
% manufacturer's rated pull-out, because an insert's engagement geometry
% is not derivable from the bolt's thread alone. The nut
% and insert checks carry an ultimate/yield pair; a spec-rated ultimate
% load, when set, CAPS the computed ultimate allowable (lower-of) or
% stands alone when no area is available. These four rows are a
% supplemental practice, not a 5020B requirement (5020B handles thread
% stripping by design rule, §4.7.4, not a computed margin) — but they can
% GOVERN via the WorstMargin pick below, so their design load
% (engine.boltDesignLoad) must not be non-conservative: it branches on the
% SAME NASA-STD-5020B Fig. 8 gate as tu.SeparationBeforeRupture above (one
% shared evaluation, engine's private separationBeforeRuptureGate), using
% the preload-included Pb = PpMax+FF·FS·n·phi·PtL only while the gate is
% NOT assured; once separation before rupture is assured, Pb = FF·FS·PtL
% (no preload/n·phi — the members carry no load once separated).
bt = engine.marginBoltThreadShear(joint, loadCase, factors, p);    % TM-106943 Eq. 63 (0.75·pi·E·Le pitch-diameter form) + Eq. 64/65; Pb per 5020B Eq. 8
ns = engine.marginNutStrength(joint, loadCase, factors, p);        % TM-106943 Eq. 76/77 + Eq. 65 (same As form, ult/yld; rating ceiling per 5020B §4.4.1); Nut config only
it = engine.marginInsert(joint, loadCase, factors, p);             % Shear-engagement-area x parent shear strength (ult/yld) or Heli-Coil rated pull-out (5020B §4.4.1); Insert config only
tp = engine.marginTappedParentThread(joint, loadCase, factors, p); % TM-106943 Eq. 79 + Eq. 65 (same As form); TappedHole config only

% ---- Warnings: bolt length, then preload (spec banner order) -------------
% Both underlying queries are pure and NEVER THROW (see their own headers),
% so this is safe to run unconditionally on every analyze() call. Neither
% is a margin: they do not affect WorstMargin/GoverningCheck and carry no
% Margins row of their own -- they live ONLY on Result.Warnings.
% Empty template is a 1x0 row (repmat(...,1,0), same idiom as
% Result.Warnings' own default) so an all-clean joint carries a genuine
% 1x0 row, matching the (1,:) shape Result.Warnings requires -- never a
% shapeless 0x0 that would fail that property's size validation.
warnings = repmat(struct( ...
    "Name", "", "Severity", "Warning", "Message", "", "Method", "", "Detail", ""), 1, 0);

blc = engine.boltLengthCheck(joint);   % NASA-STD-5020B Sec 4.7.4 (nut) / derived convention (threaded-in)
if blc.Shortfall > 0   % Shortfall is NaN when not evaluated -- NaN > 0 is false, so this never fires spuriously
    warnings(end+1) = struct( ...
        "Name",     "BoltLengthShort", ...
        "Severity", "Warning", ...
        "Message",  blc.Detail, ...
        "Method",   blc.Method, ...
        "Detail",   blc.Detail);
end

pw = engine.preloadWatchdog(joint, p);   % NASA-STD-5020B Eq. 1 (PpMax) vs bolt allowables; 85%/100% bands are a derived convention (see its own header)
if strlength(pw.Name) > 0
    warnings(end+1) = struct( ...
        "Name",     pw.Name, ...
        "Severity", pw.Severity, ...
        "Message",  pw.Detail, ...
        "Method",   pw.Method, ...
        "Detail",   pw.Detail);
end

% ---- Separation-before-rupture as its own row ----------------------------
% The gate (NASA-STD-5020B Fig. 8 / DABJ Fig. 9-9) is boolean — it has no
% numeric MS, so its Status comes from the gate result, not the NaN rule:
% assured -> "Pass"; not assured -> "Fail" (rupture conservatively assumed).
sbr = entry("Separation-before-rupture", NaN, ...
    "NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) decision tree", tu.Decision);
if tu.SeparationBeforeRupture
    sbr.Status = "Pass";
else
    sbr.Status = "Fail";
end

% ---- Interaction as its own row -- NOT a margin --------------------------
% ia.R is a ratio (NASA-STD-5020B Eq. 20-23 criterion, Pass iff R <= 1),
% on a scale that is NOT comparable to the other 14 rows' MS values (see
% the module header's INTERACTION IS NOT A MARGIN note). Exactly like the
% boolean Separation-before-rupture gate above, this row carries MS = NaN
% (which excludes it from the WorstMargin min via the same NaN filter
% every NotEvaluated row uses) with Status set DIRECTLY from ia.Pass, NOT
% from the generic NaN -> NotEvaluated rule -- so a real interaction
% failure still shows as its own Fail row, never silently swallowed by
% the NaN.
iaRow = entry("Interaction", NaN, ia.Method, ia.Detail, ia.R);
if isnan(ia.R)
    iaRow.Status = "NotEvaluated";
elseif ia.Pass
    iaRow.Status = "Pass";
else
    iaRow.Status = "Fail";
end

% ---- The full 15-check set (PRD 5.1) -------------------------------------
% Insert "failure modes" (PRD check 9) is advertised as its two thread
% failure modes (internal/external) — that is what brings the advertised
% set to 15 rows. This tool carries ONE pull-out result for the whole
% insert (area form and/or rated load, engine.marginInsert) on the
% internal-thread row; the external-thread row is therefore NotEvaluated
% by design (folded into the single result).
margins = [ ...
    entry("Tension-Ultimate", tu.MS, tu.Method, tu.Decision), ...
    entry("Tension-Yield",    ty.MS, ty.Method, ty.Detail), ...
    entry("Shear-Ultimate",   su.MS, su.Method, su.Detail), ...
    iaRow, ...
    entry("Separation",       sp.MS, sp.Method, ""), ...
    entry("Slip",             sl.MS, sl.Method, ""), ...
    sbr, ...
    entry("Bearing",                   br.MS, br.Method, br.Detail), ...
    entry("Bearing-under-head",        bh.MS, bh.Method, bh.Detail), ...
    entry("Shear-tearout",             to.MS, to.Method, to.Detail), ...
    entry("Bolt-thread shear",         bt.MS, bt.Method, bt.Detail), ...
    entry("Nut strength",              ns.MS, ns.Method, ns.Detail), ...
    entry("Insert internal-thread",    it.MS, it.Method, it.Detail), ...
    entry("Insert external-thread",    NaN, ...
        "Folded into the Heli-Coil rated pull-out (single manufacturer rating; see the Insert internal-thread row)", ""), ...
    entry("Tapped-hole parent-thread", tp.MS, tp.Method, tp.Detail)];

% ---- Worst margin / governing check (thresholds, not equations) ----------
msAll   = [margins.MS];
idxEval = find(~isnan(msAll));          % evaluated checks only (ignore NaN)
if isempty(idxEval)
    worst     = NaN;
    governing = "";
else
    [worst, k] = min(msAll(idxEval));
    governing  = margins(idxEval(k)).Name;
end

% ---- Assemble the Result --------------------------------------------------
r = engine.Result( ...
    JointName      = joint.Name, ...
    CaseName       = loadCase.Name, ...
    Preload        = p, ...
    DesignLoads    = d, ...
    Margins        = margins, ...
    WorstMargin    = worst, ...
    GoverningCheck = governing, ...
    Narrative      = tu.Decision, ...
    Warnings       = warnings);
end

% ---- Local helpers --------------------------------------------------------
function e = entry(name, ms, method, detail, r)
%ENTRY  One Margins row with the status threshold applied.
%   Status thresholds (bookkeeping, not equations): a margin of safety
%   passes when MS >= 0 (capacity >= demand at the design load), fails when
%   MS < 0; NaN means the check produced no number (not built, or not
%   applicable — the Method string says which).
%
%   r (optional, default NaN): the NASA-STD-5020B Eq. 20-23 interaction
%   RATIO, carried alongside MS rather than smuggled inside it — R and MS
%   live on OPPOSITE-direction scales (Pass iff R <= 1, vs Pass iff
%   MS >= 0), so a caller that blindly thresholds ">= 0" on this field
%   would get the Interaction row backwards. Every row gets this field
%   (NaN on the 14 true margins) so Margins stays one uniform struct
%   array; only the "Interaction" row (see the iaRow assembly above) is
%   ever non-NaN. Callers needing R must read Margins(k).R explicitly —
%   asTable() does not surface it (same treatment as Detail).
if nargin < 5
    r = NaN;
end
if isnan(ms)
    status = "NotEvaluated";
elseif ms >= 0
    status = "Pass";
else
    status = "Fail";
end
e = struct( ...
    "Name",   string(name), ...
    "MS",     ms, ...
    "R",      r, ...
    "Status", status, ...
    "Method", string(method), ...
    "Detail", string(detail));
end
