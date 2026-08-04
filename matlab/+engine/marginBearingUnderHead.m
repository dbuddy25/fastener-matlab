function r = marginBearingUnderHead(joint, loadCase, factors, preload)
%MARGINBEARINGUNDERHEAD  Bearing under the bolt head / nut (TM-106943 Eq. 75).
%   r = engine.marginBearingUnderHead(joint, loadCase, factors, preload)
%   computes the bearing margin of the bolt head (or head washer) and the
%   nut (washer) pressing on the outer flange faces under the bolt AXIAL
%   load. preload is the struct from engine.preload. All loads in lbf,
%   lengths in inches, strengths in psi (see UNITS.md).
%
%   NASA-STD-5020B §4.4.2 REQUIRES margins for the joint members but
%   prints no member-strength equations; the working equations are NASA
%   TM-106943 (Chambers) Eq. 75 for area, Eq. 74 for the MS form:
%       Abr = (pi/4)*(dh^2 - dt^2)        (bearing annulus, Eq. 75)
%   with the MS denominator per branch below (5020B §4.4.5 on where FF·FS
%   may fall on preload — see the DESIGN-LOAD NOTE), dh the bearing
%   (head/washer/nut) outer diameter, dt the flange hole diameter — gated
%   on the SAME NASA-STD-5020B Fig. 8 separation-before-rupture decision
%   engine.boltDesignLoad uses (shared private helper
%   separationBeforeRuptureGate — one evaluation, so this row can never
%   disagree with the Tension-Ultimate row or the thread checks about
%   which branch applies). NASA-STD-5020B §4.4.5 is explicit that this is
%   a statement about the BOLT'S AXIAL LOAD, not about any one check:
%   "When a fastened joint is completely separated prior to rupture, the
%   total axial component of the load acting on the bolt is equal to the
%   axial component of the applied load only. If rupture occurs before
%   separation, preload also acts on the bolt and should be included...
%   In this case, a factor of safety is not applied to preload." Bearing
%   under the head is driven by that same axial load, so the gate applies
%   here exactly as it does to engine.boltDesignLoad's design load:
%
%   CLAMPED branch (Fig. 8 gate NOT assured — rupture assumed, or the gate
%   could not be assessed; TODAY'S behavior, unchanged):
%       Pb = Pp_max + n·phi·PtL           (NASA-STD-5020B Eq. 8)
%   with n = joint.LoadingPlaneFactor, phi from engine.stiffness (5020B
%   Eq. 9), and PtL = loadCase.BoltTensileLimitLoad.
%
%   SEPARATED branch (Fig. 8 gate ASSURED — separation before rupture):
%   once separated the clamped members carry no load at all, so the bolt
%   sees the applied load only — no preload term, no n·phi discount (the
%   §4.4.5 sentence quoted above, and also "a factor of safety is not
%   applied to preload" — consistent with this file's own convention of
%   leaving Pb itself unfactored and applying FF·FS only in the MS
%   formula below):
%       Pb = PtL
%
%   DESIGN-LOAD NOTE (deliberate, UNCHANGED by the gate above): NASA-STD-
%   5020B §4.4.5 is explicit that preload itself is never factored: "If
%   rupture occurs before separation, preload also acts on the bolt and
%   should be included when assessing the performance of the fastened
%   joint. In this case, a factor of safety is not applied to preload."
%   So on the CLAMPED branch, FF·FS multiplies only the EXTERNAL term —
%       MS = Fbr·Abr / (PpMax + FF·FS·n·phi·PtL) - 1
%   matching engine.boltDesignLoad's thread-check design load exactly (see
%   that file for the same §4.4.5 reasoning). This SHRINKS the design-load
%   denominator versus factoring the whole Pb (preload included), so
%   margins on this branch are LESS conservative than before — that is the
%   correct reading of the cited equation, not a relaxation of intent. The
%   SEPARATED branch is unaffected: it has no preload term at all
%   (Pb = PtL), so FF·FS·Pb was already §4.4.5-correct and is unchanged.
%   engine.boltDesignLoad is still deliberately NOT called here (scope
%   would otherwise drift in by accident); separationBeforeRuptureGate is
%   reused directly instead.
%
%   Sides evaluated (each for BOTH criteria, ultimate Fbru with FFU*FSU
%   and yield Fbry with FFY*FSY, using that side's flange material):
%       Head side — dh = HeadWasher.OuterDiameter if finite, else
%                   Bolt.HeadBearingDiameter; dt = FlangeStack(1).HoleDiameter.
%       Nut side  — dh = ThreadedMember.BearingDiameter if finite, else
%                   NutWasher.OuterDiameter (both NaN -> side skipped);
%                   dt = FlangeStack(end).HoleDiameter.
%   A side needs finite dh AND dt (and a set Fbru/Fbry for the criterion)
%   to be checked; Abr is clamped at >= 0. The reported margin is the
%   WORST (minimum) over sides and criteria; if neither side is checkable
%   the check reports MS = NaN (NotEvaluated). If engine.stiffness cannot
%   run (threaded-in configuration or missing frustum geometry), the check
%   reports MS = NaN with the reason in Detail rather than crashing.
%
%   Returned struct fields:
%       MS      worst margin of safety (double; NaN = not evaluated)
%       Method  string: governing equation citation
%       Detail  string: which Fig. 8 gate branch produced Pb, then the
%               governing side + criterion (or the not-evaluated reason)
%
%   Call graph:
%       Precedents (calls)      engine.stiffness (wrapped in try/catch —
%                               never allowed to crash this function),
%                               separationBeforeRuptureGate (private
%                               helper, +engine/private/ — SHARED with
%                               engine.boltDesignLoad / engine.marginTensionUlt).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tBearing.m —
%                               bearingUnderHeadHandDerived (DABJ Ex 8-b
%                               geometry, head-side hand-derived MS pin —
%                               the Fig. 8 gate is ASSURED on this
%                               fixture's own numbers, so Pb = PtL; see the
%                               test's derivation comment for why);
%                               bearingUnderHeadGateNotAssuredClampedLoad
%                               (Fig. 8 gate NOT assured, hand-derived,
%                               Pb = PpMax + n·phi·PtL — covers the
%                               CLAMPED branch, which the fixture above no
%                               longer exercises now that it is assured);
%                               dabjSection9RegressionUnchanged (confirms
%                               this row stays NotEvaluated on the §9
%                               fixture — no HoleDiameter/frustum geometry
%                               — and does not disturb the answer key).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 6).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "NASA TM-106943 Eq. 75 area + Eq. 74 MS form (bearing under head/nut); required by NASA-STD-5020B §4.4.2";

PtL = loadCase.BoltTensileLimitLoad;   % most-loaded-bolt tensile limit load, lbf
if isnan(PtL)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: bolt tensile limit load undefined (NaN).");
    return
end

% ---- Bolt axial design load ---------------------------------------------
% Needs phi from engine.stiffness; if stiffness cannot run (threaded-in
% configuration or missing frustum geometry) report NotEvaluated, do not crash.
try
    s = engine.stiffness(joint);       % errors for threaded-in / missing geometry
catch stiffErr
    r = struct("MS", NaN, ...
        "Method", method + " — requires stiffness geometry", ...
        "Detail", "Not evaluated: Pb needs phi from engine.stiffness, which could not run: " + ...
                  string(stiffErr.message));
    return
end
n   = joint.LoadingPlaneFactor;
phi = s.Phi;                           % NASA-STD-5020B Eq. 9 — phi = kb/(kb + kc)

% ---- Separation-before-rupture gate (NASA-STD-5020B Fig. 8) --------------
% SHARED with engine.boltDesignLoad / engine.marginTensionUlt via the
% private helper separationBeforeRuptureGate — one evaluation, so this
% bearing-under-head design load can never disagree with those rows about
% which branch applies. See the module header for the §4.4.5 basis.
gate = separationBeforeRuptureGate(joint, preload);

if gate.Assessed && gate.Assured
    % SEPARATED branch (Fig. 8 gate assured): once separated the clamped
    % members carry no load at all, so the bolt sees the applied load
    % only — no preload term, no n·phi discount. FF·FS is NOT baked in
    % here (unchanged scope — see DESIGN-LOAD NOTE above); it is applied,
    % to this same Pb, only in the MS formula below. No preload term means
    % §4.4.5's "no FS on preload" carve-out is moot — FF·FS·Pb is already
    % the correct denominator, unchanged by Part 1.
    Pb = PtL;                          % lbf
    denomFcn = @(FF, FS) FF * FS * Pb;
    branchNote = "SEPARATED branch (Fig. 8 gate assured: " + gate.Trace + "): " + ...
        "Pb = PtL (no preload/n·phi — members carry no load once separated)";
else
    % CLAMPED branch (Fig. 8 gate NOT assured, or not assessable; TODAY'S
    % behavior, unchanged): NASA-STD-5020B Eq. 8 — Pb = Pp_max + n·φ·PtL.
    % Pb here is the (unfactored) bolt axial design load, kept for Detail
    % reporting; per §4.4.5 ("a factor of safety is not applied to
    % preload") the MS denominator factors only the external n·phi·PtL
    % term, NOT the whole Pb — see DESIGN-LOAD NOTE above.
    Pb = preload.PpMax + n * phi * PtL;    % lbf, informational
    denomFcn = @(FF, FS) preload.PpMax + FF * FS * n * phi * PtL;
    if gate.Assessed
        branchNote = "CLAMPED branch (Fig. 8 gate not assured, rupture assumed: " + ...
            gate.Trace + "): Pb = PpMax + n·phi·PtL, MS denominator = PpMax + FF·FS·n·phi·PtL (5020B §4.4.5, no FS on preload)";
    else
        branchNote = "CLAMPED branch (" + gate.Trace + "): " + ...
            "Pb = PpMax + n·phi·PtL, MS denominator = PpMax + FF·FS·n·phi·PtL (5020B §4.4.5, no FS on preload), no branch silently picked";
    end
end

% ---- The two bearing sides ----------------------------------------------
% engine.stiffness guarantees a non-empty FlangeStack (it errors otherwise).
% Head side: washer OD if specified, else the bolt head washer-face dia.
dhHead = joint.HeadWasher.OuterDiameter;
if isnan(dhHead)
    dhHead = joint.Bolt.HeadBearingDiameter;
end
% Nut side: the threaded member's own bearing dia if specified, else the
% nut washer OD (both NaN -> side skipped).
dhNut = joint.ThreadedMember.BearingDiameter;
if isnan(dhNut)
    dhNut = joint.NutWasher.OuterDiameter;
end
sides = struct( ...
    "Name", {"head side", "nut side"}, ...
    "dh",   {dhHead, dhNut}, ...                                   % NaN dh -> side skipped
    "dt",   {joint.FlangeStack(1).HoleDiameter, joint.FlangeStack(end).HoleDiameter}, ...
    "Mat",  {joint.FlangeStack(1).Material, joint.FlangeStack(end).Material});

msList     = [];
detailList = strings(1, 0);
for k = 1:numel(sides)
    dh = sides(k).dh;
    dt = sides(k).dt;
    if isnan(dh) || isnan(dt)
        continue                       % side not configured
    end
    % NASA TM-106943 Eq. 75 — Abr = (π/4)(dh² − dt²) (MS form Eq. 74); MS
    % denominator per branch — see denomFcn above (5020B §4.4.5 on the
    % clamped branch: FS not applied to preload; SEPARATED branch: FF·FS·Pb)
    Abr = max((pi/4) * (dh^2 - dt^2), 0);   % bearing annulus, clamped >= 0, in^2

    % Ultimate criterion (Fbru with FFU*FSU)
    Fbru = sides(k).Mat.Fbru;
    if ~isnan(Fbru) && Fbru > 0
        denomU = denomFcn(factors.FFU, factors.FSU);
        msList(end+1)     = Fbru * Abr / denomU - 1; %#ok<AGROW>
        detailList(end+1) = string(sides(k).Name) + ", ultimate" + ...
            string(sprintf(" (dh %.3f / dt %.3f in, Abr %.4f in^2, Pb %.0f lbf, MS denom %.1f lbf)", ...
            dh, dt, Abr, Pb, denomU));                                        %#ok<AGROW>
    end
    % Yield criterion (Fbry with FFY*FSY)
    Fbry = sides(k).Mat.Fbry;
    if ~isnan(Fbry) && Fbry > 0
        denomY = denomFcn(factors.FFY, factors.FSY);
        msList(end+1)     = Fbry * Abr / denomY - 1; %#ok<AGROW>
        detailList(end+1) = string(sides(k).Name) + ", yield" + ...
            string(sprintf(" (dh %.3f / dt %.3f in, Abr %.4f in^2, Pb %.0f lbf, MS denom %.1f lbf)", ...
            dh, dt, Abr, Pb, denomY));                                        %#ok<AGROW>
    end
end

if isempty(msList)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: no side has a bearing diameter, hole diameter, and flange bearing allowable all set. " + ...
                  branchNote + ".");
    return
end

[MS, idx] = min(msList);   % worst side/criterion governs
r = struct("MS", MS, "Method", method, ...
    "Detail", branchNote + ". Governing: " + detailList(idx) + ".");
end
