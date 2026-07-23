function r = marginBearing(joint, loadCase, factors)
%MARGINBEARING  Bolt bearing on the flanges (NASA TM-106943 Eq. 72-74).
%   r = engine.marginBearing(joint, loadCase, factors) computes the
%   bolt-bearing-on-flange margin for one joint. Bearing is driven by the
%   bolt SHEAR load pressing the bolt shank against the hole wall. All
%   loads in lbf, lengths in inches, strengths in psi (see UNITS.md).
%
%   NASA-STD-5020B §4.4.2 REQUIRES margins for the joint members (bearing
%   among them) but prints no member-strength equations; the working
%   equations are NASA TM-106943 (Chambers) Eq. 72-74:
%       Abr = D * t                 (projected bearing area, Eq. 72 form)
%       Pbr = Fbr * Abr             (bearing allowable, Eq. 72/73)
%       MS  = Pbr / (FF*FS*V) - 1   (Eq. 74)
%   evaluated per flange layer for BOTH criteria: ultimate (Fbru with
%   FFU*FSU) and yield (Fbry with FFY*FSY). The reported margin is the
%   WORST (minimum) over all layers and both criteria.
%
%   V = loadCase.BoltShearLimitLoad (most-loaded bolt) and
%   D = joint.Bolt.NominalDiameter. A layer whose material carries no
%   bearing allowable for a criterion (Fbru/Fbry NaN or 0 — the Material
%   default 0 means "not set") is skipped for that criterion. Guards:
%   V = NaN -> MS = NaN (NotEvaluated: no shear load defined); V = 0 ->
%   MS = Inf (no applied shear means infinite bearing margin — falls out
%   of the arithmetic); no checkable layer at all -> MS = NaN.
%
%   Returned struct fields:
%       MS                worst margin of safety (double; NaN = not evaluated)
%       Method            string: governing equation citation
%       Detail            string: governing layer + criterion (or the
%                         not-evaluated reason)
%       BearingAllowable  Pbr of the governing layer/criterion, lbf (NaN if
%                         not evaluated)
%
%   Validated against DABJ Example 5-b (allowable comparison): D = 0.375,
%   t = 0.320, Fbru = 123,000 psi gives Pbr = 123000*0.375*0.320 =
%   14,760 lbf (the book prints 14,800, rounded) — see tests/tBearing.m.
%   The MS form itself is exercised with hand-derived numbers (Ex 5-b
%   compares allowables only, not margins).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

method = "NASA TM-106943 Eq. 72-74 (bolt bearing); required by NASA-STD-5020B §4.4.2";

V = loadCase.BoltShearLimitLoad;   % PsL, most-loaded bolt — bearing is driven by SHEAR, lbf
D = joint.Bolt.NominalDiameter;    % bolt major diameter, in

if isnan(V) || isnan(D)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: bolt shear limit load and/or bolt diameter undefined (NaN).", ...
        "BearingAllowable", NaN);
    return
end

% Collect a candidate margin per (layer, criterion), then take the worst.
msList     = [];
pbrList    = [];
detailList = strings(1, 0);
for k = 1:numel(joint.FlangeStack)
    fl = joint.FlangeStack(k);
    t  = fl.Thickness;                    % layer thickness, in
    % NASA TM-106943 Eq. 72 — Abr = D·t (projected bearing area)
    Abr = D * t;                          % in^2
    layerName = sprintf("layer %d (%s)", k, fl.Material.Name);

    % Ultimate: NASA TM-106943 Eq. 72-74 — Pbr = Fbru·D·t ; MS = Pbr/(FFU·FSU·V) − 1
    Fbru = fl.Material.Fbru;
    if ~isnan(Fbru) && Fbru > 0
        Pbr = Fbru * Abr;                                     % bearing allowable, lbf
        msList(end+1)     = Pbr / (factors.FFU * factors.FSU * V) - 1; %#ok<AGROW>
        pbrList(end+1)    = Pbr;                              %#ok<AGROW>
        detailList(end+1) = layerName + ", ultimate";         %#ok<AGROW>
    end

    % Yield: NASA TM-106943 Eq. 72-74 — Pbr = Fbry·D·t ; MS = Pbr/(FFY·FSY·V) − 1
    Fbry = fl.Material.Fbry;
    if ~isnan(Fbry) && Fbry > 0
        Pbr = Fbry * Abr;                                     % bearing allowable, lbf
        msList(end+1)     = Pbr / (factors.FFY * factors.FSY * V) - 1; %#ok<AGROW>
        pbrList(end+1)    = Pbr;                              %#ok<AGROW>
        detailList(end+1) = layerName + ", yield";            %#ok<AGROW>
    end
end

if isempty(msList)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: no flange layer carries a bearing allowable (Fbru/Fbry unset).", ...
        "BearingAllowable", NaN);
    return
end

[MS, idx] = min(msList);   % worst layer/criterion governs
r = struct( ...
    "MS",               MS, ...
    "Method",           method, ...
    "Detail",           "Governing: " + detailList(idx) + ...
                        string(sprintf(" — Pbr = %.0f lbf vs V = %.0f lbf.", pbrList(idx), V)), ...
    "BearingAllowable", pbrList(idx));
end
