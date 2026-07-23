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
%       Tension-Ultimate   engine.marginTensionUlt   NASA-STD-5020B Eq. 6 (assured) / Eq. 10 (rupture) + Fig. 8 gate
%       Tension-Yield      engine.marginBoltYield    NASA-STD-5020B Eq. 15
%       Shear-Ultimate     engine.marginShearUlt     NASA-STD-5020B Eq. 12/13 + Eq. 14
%       Interaction        engine.marginInteraction  NASA-STD-5020B Eq. 20/21
%       Separation         engine.marginSeparation   NASA-STD-5020B Eq. 19
%       Slip               engine.marginSlip         NASA-STD-5020B Eq. 84 (joint) / Eq. 86 (single-fastener), per joint.SlipMode; Disabled -> NotEvaluated
%       Bearing            engine.marginBearing            NASA TM-106943 Eq. 72-74 (required by 5020B §4.4.2)
%       Bearing-under-head engine.marginBearingUnderHead   NASA TM-106943 Eq. 74/75 + 5020B Eq. 8 (Pb)
%       Shear-tearout      engine.marginShearTearout       NASA TM-106943 Eq. 69-71 (required by 5020B §4.4.2)
%   plus the Separation-before-rupture gate (NASA-STD-5020B Fig. 8), a
%   boolean check reported as its own Margins row (Pass = assured) and as
%   Result.Narrative.
%
%   The Margins array always advertises the FULL 15-check set (PRD 5.1);
%   checks arriving in Phase 3.3 (bolt-thread shear, nut strength, insert
%   internal/external thread, tapped-hole parent-thread) appear with
%   MS = NaN and Status "NotEvaluated" — real results ship without fake
%   numbers. The Phase 3.2 member checks likewise report NotEvaluated when
%   their inputs are not configured (no EdgeDistance -> no tear-out; no
%   HoleDiameter / stiffness geometry -> no bearing-under-head; no flange
%   bearing allowables -> no bearing).
%
%   Status thresholds (bookkeeping, not equations): MS >= 0 -> "Pass",
%   MS < 0 -> "Fail", NaN -> "NotEvaluated". WorstMargin is the minimum MS
%   over the evaluated checks; GoverningCheck is that check's Name.
%
%   Validated against the DABJ Section 9 class problem
%   (validation.dabjSection9, via tests/tDabjCase.m): one analyze() call
%   reproduces all six published margins — Tension-Ultimate +0.69,
%   Tension-Yield +0.63, Shear-Ultimate +3.18, Interaction +0.59,
%   Separation +0.16, Slip -0.65 — with WorstMargin -0.65 governed by Slip
%   (the book's joint slips at limit load). On that case the Phase 3.2
%   member checks resolve as: Shear-tearout and Bearing-under-head
%   NotEvaluated (no EdgeDistance/HoleDiameter/frustum geometry in the §9
%   fixture); Bearing EVALUATES (passing, ~+5.77) because the library's
%   Al 7075-T7351 carries handbook-fill Fbru/Fbry — it does not disturb
%   the answer key (tests/tBearing.m pins this regression).

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
ty = engine.marginBoltYield(joint, d);               % NASA-STD-5020B Eq. 15
su = engine.marginShearUlt(joint, d);                % NASA-STD-5020B Eq. 12/13 + Eq. 14
ia = engine.marginInteraction(joint, d);             % NASA-STD-5020B Eq. 20/21 solve-for-a
sp = engine.marginSeparation(p, d);                  % NASA-STD-5020B Eq. 19
sl = engine.marginSlip(joint, loadCase, p, factors); % NASA-STD-5020B Eq. 84 (Joint) / Eq. 86 (SingleFastener) per joint.SlipMode; Disabled -> MS NaN -> NotEvaluated

% ---- The three member checks (Phase 3.2) ---------------------------------
br = engine.marginBearing(joint, loadCase, factors);            % NASA TM-106943 Eq. 72-74 (bolt bearing; required by 5020B §4.4.2)
to = engine.marginShearTearout(joint, loadCase, factors);       % NASA TM-106943 Eq. 69-71 (shear tear-out; required by 5020B §4.4.2)
bh = engine.marginBearingUnderHead(joint, loadCase, factors, p); % NASA TM-106943 Eq. 74/75 + 5020B Eq. 8 Pb = PpMax + n·phi·PtL

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

% ---- The full 15-check set (PRD 5.1) -------------------------------------
% Insert "failure modes" (PRD check 9) is advertised as its two thread
% failure modes (internal = bolt/insert thread, external = insert/parent
% pull-out), matching the reference Python tool's check set — that is what
% brings the advertised set to 15 rows.
margins = [ ...
    entry("Tension-Ultimate", tu.MS, tu.Method, tu.Decision), ...
    entry("Tension-Yield",    ty.MS, ty.Method, ""), ...
    entry("Shear-Ultimate",   su.MS, su.Method, ""), ...
    entry("Interaction",      ia.MS, ia.Method, ""), ...
    entry("Separation",       sp.MS, sp.Method, ""), ...
    entry("Slip",             sl.MS, sl.Method, ""), ...
    sbr, ...
    entry("Bearing",                   br.MS, br.Method, br.Detail), ...
    entry("Bearing-under-head",        bh.MS, bh.Method, bh.Detail), ...
    entry("Shear-tearout",             to.MS, to.Method, to.Detail), ...
    entry("Bolt-thread shear",         NaN, "Bolt-thread shear — Phase 3.3", ""), ...
    entry("Nut strength",              NaN, "Nut strength — Phase 3.3", ""), ...
    entry("Insert internal-thread",    NaN, "Insert internal-thread — Phase 3.3", ""), ...
    entry("Insert external-thread",    NaN, "Insert external-thread — Phase 3.3", ""), ...
    entry("Tapped-hole parent-thread", NaN, "Tapped-hole parent-thread — Phase 3.3", "")];

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
    Narrative      = tu.Decision);
end

% ---- Local helpers --------------------------------------------------------
function e = entry(name, ms, method, detail)
%ENTRY  One Margins row with the status threshold applied.
%   Status thresholds (bookkeeping, not equations): a margin of safety
%   passes when MS >= 0 (capacity >= demand at the design load), fails when
%   MS < 0; NaN means the check produced no number (not built, or not
%   applicable — the Method string says which).
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
    "Status", status, ...
    "Method", string(method), ...
    "Detail", string(detail));
end
