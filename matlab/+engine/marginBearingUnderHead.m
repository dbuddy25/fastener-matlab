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
%   TM-106943 (Chambers):
%       Abr = (pi/4)*(dh^2 - dt^2)        (bearing annulus, Eq. 75)
%       MS  = Fbr*Abr / (FF*FS*Pb) - 1    (MS form of Eq. 74)
%   where dh is the bearing (head/washer/nut) outer diameter, dt the
%   flange hole diameter, and Pb the bolt axial design load:
%       Pb = Pp_max + n·phi·PtL           (NASA-STD-5020B Eq. 8)
%   with n = joint.LoadingPlaneFactor, phi from engine.stiffness (5020B
%   Eq. 9), and PtL = loadCase.BoltTensileLimitLoad.
%
%   DESIGN-LOAD NOTE (deliberate): this replicates the reference Python
%   tool's convention — FF·FS multiplies the WHOLE Pb, preload term
%   included. That is slightly conservative versus the thread-shear design
%   load, which factors only the external part (Pp_max + FF·FS·n·phi·PtL).
%
%   Sides evaluated (each for BOTH criteria, ultimate Fbru with FFU*FSU
%   and yield Fbry with FFY*FSY, using that side's flange material):
%       Head side — dh = HeadWasher.OuterDiameter if finite, else
%                   Bolt.HeadBearingDiameter; dt = FlangeStack(1).HoleDiameter.
%       Nut side  — dh = NutWasher.OuterDiameter (NaN -> side skipped);
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
%       Detail  string: governing side + criterion (or the not-evaluated
%               reason)
%
%   No public worked example covers this check; it is verified by
%   HAND-DERIVED arithmetic on the DABJ Example 8-b geometry in
%   tests/tBearing.m (bearingUnderHeadHandDerived).

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
% NASA-STD-5020B Eq. 8 — Pb = Pp_max + n·φ·PtL (bolt axial load)
Pb = preload.PpMax + n * phi * PtL;    % lbf

% ---- The two bearing sides ----------------------------------------------
% engine.stiffness guarantees a non-empty FlangeStack (it errors otherwise).
% Head side: washer OD if specified, else the bolt head washer-face dia.
dhHead = joint.HeadWasher.OuterDiameter;
if isnan(dhHead)
    dhHead = joint.Bolt.HeadBearingDiameter;
end
sides = struct( ...
    "Name", {"head side", "nut side"}, ...
    "dh",   {dhHead, joint.NutWasher.OuterDiameter}, ...           % NaN nut washer OD -> side skipped
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
    % NASA TM-106943 Eq. 75 — Abr = (π/4)(dh² − dt²) ; MS = Fbr·Abr/(FF·FS·Pb) − 1  (MS form Eq. 74)
    Abr = max((pi/4) * (dh^2 - dt^2), 0);   % bearing annulus, clamped >= 0, in^2

    % Ultimate criterion (Fbru with FFU*FSU)
    Fbru = sides(k).Mat.Fbru;
    if ~isnan(Fbru) && Fbru > 0
        msList(end+1)     = Fbru * Abr / (factors.FFU * factors.FSU * Pb) - 1; %#ok<AGROW>
        detailList(end+1) = string(sides(k).Name) + ", ultimate" + ...
            string(sprintf(" (dh %.3f / dt %.3f in, Abr %.4f in^2, Pb %.0f lbf)", ...
            dh, dt, Abr, Pb));                                                 %#ok<AGROW>
    end
    % Yield criterion (Fbry with FFY*FSY)
    Fbry = sides(k).Mat.Fbry;
    if ~isnan(Fbry) && Fbry > 0
        msList(end+1)     = Fbry * Abr / (factors.FFY * factors.FSY * Pb) - 1; %#ok<AGROW>
        detailList(end+1) = string(sides(k).Name) + ", yield" + ...
            string(sprintf(" (dh %.3f / dt %.3f in, Abr %.4f in^2, Pb %.0f lbf)", ...
            dh, dt, Abr, Pb));                                                 %#ok<AGROW>
    end
end

if isempty(msList)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: no side has a bearing diameter, hole diameter, and flange bearing allowable all set.");
    return
end

[MS, idx] = min(msList);   % worst side/criterion governs
r = struct("MS", MS, "Method", method, "Detail", "Governing: " + detailList(idx) + ".");
end
