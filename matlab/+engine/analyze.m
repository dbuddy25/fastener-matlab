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
%       Tension-Ultimate   engine.marginTensionUlt   5020A Eq. 6 + Fig. 8 gate
%       Tension-Yield      engine.marginBoltYield    5020A Eq. 15
%       Shear-Ultimate     engine.marginShearUlt     5020A Eq. 12/13 + Eq. 14
%       Interaction        engine.marginInteraction  5020A Eq. 20/21
%       Separation         engine.marginSeparation   5020A Eq. 19
%       Slip               engine.marginSlip         5020A Eq. 84 (joint) / Eq. 86 (single-fastener), per joint.SlipMode; Disabled -> NotEvaluated
%   plus the Separation-before-rupture gate (NASA-STD-5020A Fig. 8), a
%   boolean check reported as its own Margins row (Pass = assured) and as
%   Result.Narrative.
%
%   The Margins array always advertises the FULL 15-check set (PRD 5.1);
%   checks arriving in Phases 3.2/3.3 (bearing, bearing-under-head,
%   shear-tearout, bolt-thread shear, nut strength, insert internal/external
%   thread, tapped-hole parent-thread) appear with MS = NaN and Status
%   "NotEvaluated" — real results ship without fake numbers.
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
%   (the book's joint slips at limit load).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

% ---- Supporting computations --------------------------------------------
p = engine.preload(joint);                  % 5020A Eq. 25/26 + Eq. 1/2
d = engine.designLoads(loadCase, factors);  % 5020A design load = FS x FF x limit

% ---- The six built margin checks (Phases 2.5-2.8) ------------------------
tu = engine.marginTensionUlt(joint, p, d);           % 5020A Eq. 6 + Fig. 8 gate
ty = engine.marginBoltYield(joint, d);               % 5020A Eq. 15
su = engine.marginShearUlt(joint, d);                % 5020A Eq. 12/13 + Eq. 14
ia = engine.marginInteraction(joint, d);             % 5020A Eq. 20/21 solve-for-a
sp = engine.marginSeparation(p, d);                  % 5020A Eq. 19
sl = engine.marginSlip(joint, loadCase, p, factors); % 5020A Eq. 84 (Joint) / Eq. 86 (SingleFastener) per joint.SlipMode; Disabled -> MS NaN -> NotEvaluated

% ---- Separation-before-rupture as its own row ----------------------------
% The gate (NASA-STD-5020A Fig. 8 / DABJ Fig. 9-9) is boolean — it has no
% numeric MS, so its Status comes from the gate result, not the NaN rule:
% assured -> "Pass"; not assured -> "Fail" (rupture conservatively assumed).
sbr = entry("Separation-before-rupture", NaN, ...
    "NASA-STD-5020A Fig. 8 (DABJ Fig. 9-9) decision tree", tu.Decision);
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
    entry("Bearing",                   NaN, "Bearing — Phase 3.2", ""), ...
    entry("Bearing-under-head",        NaN, "Bearing-under-head — Phase 3.2", ""), ...
    entry("Shear-tearout",             NaN, "Shear-tearout — Phase 3.2", ""), ...
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
