function p = preload(joint)
%PRELOAD  Min/max bolt preload incl. thermal (NASA-STD-5020B Eq. 3/4/5 + Eq. 24
%   + Eq. 1/2; thermal change per NASA TM-106943 Eq. 10).
%   p = engine.preload(joint) computes the initial and worst-case preloads
%   for one joint. All loads in lbf, torque in in-lbf, temperature in °C
%   (see UNITS.md).
%
%   Returned struct fields (all lbf):
%       PpiMax       max initial preload at installation (Eq. 3)
%       PpiMin       min initial preload at installation (Eq. 4/5)
%       ThermalDelta thermal preload GAIN applied on the max side (>= 0;
%                    = P_thermal_max below)
%       PpMax        max in-service preload = PpiMax + P_thermal_max
%       PpMin        min in-service preload =
%                    (1 - relaxation)·PpiMin - creep - P_thermal_min
%
%   Preload method (PreloadSpec.Method):
%     TorqueControl — nominal torque + tolerance, NASA-STD-5020B c-factor form:
%         Ppi_nom = T_nom / (K·D)                                 (Eq. 24)
%         PpiMax  = c_max·(1 + Γ)·Ppi_nom                         (Eq. 3)
%         PpiMin  = c_min·(1 - Γ)·Ppi_nom      separation-critical (Eq. 4)
%         PpiMin  = c_min·(1 - Γ/√nf)·Ppi_nom  otherwise           (Eq. 5)
%       where c_max = 1 + TorqueTolerance and c_min = 1 - TorqueTolerance
%       are the NASA-STD-5020B torque-tolerance factors (§4.3.1: "40 ± 2 N-m" ->
%       c_max = 1.05, c_min = 0.95), Γ = PreloadSpec.Uncertainty, and
%       nf = joint.BoltCount.
%     DirectPreload — nominal preload specified directly:
%         PpiMax = (1 + Γ)·Pnom,   PpiMin = (1 - Γ)·Pnom
%
%   Thermal: preload change from CTE mismatch per NASA TM-106943 (Chambers)
%   Eq. 10 — P_th = (Kb·Kc)/(Kb+Kc)·L·ΔT·(αj − αb) — with the stiffnesses
%   from engine.stiffness, L = GripLength, αj the thickness-weighted flange
%   CTE, and αb the bolt CTE. Both temperature excursions are evaluated:
%   the worst preload GAIN goes on the max side (P_thermal_max) and the
%   worst preload LOSS on the min side (P_thermal_min); each is floored at
%   zero. If PreloadSpec.ThermalRate is set (nonzero, non-NaN) it OVERRIDES
%   the stiffness form: ThermalDelta = ThermalRate (lbf/°C) × the larger
%   excursion from ReferenceTemperature, applied symmetrically (+ on the
%   max side, - on the min side — conservative both ways). On the
%   stiffness path, engine.stiffness errors (threaded-in configuration,
%   missing frustum geometry) propagate: supply either the geometry or a
%   ThermalRate override.
%
%   Validated against the DABJ Section 9 class problem
%   (validation.dabjSection9): PpiMax 10,889 / PpiMin 7,000 /
%   ThermalDelta 180.25 / PpMax 11,069 / PpMin 6,470 lbf.

arguments
    joint (1,1) model.Joint
end

ps = joint.PreloadSpec;
G  = ps.Uncertainty;                 % Γ

% ---- Initial (installation) preload range ------------------------------
switch ps.Method
    case model.PreloadMethod.TorqueControl
        D  = joint.Bolt.NominalDiameter;    % in
        K  = ps.NutFactor;
        nf = joint.BoltCount;
        % NASA-STD-5020B Eq. 24 — Ppi_nom = T / (Knom·D)
        PpiNom = ps.NominalTorque / (K * D);
        % NASA-STD-5020B torque-tolerance factors — c_max = 1 + tol, c_min = 1 - tol
        cMax = 1 + ps.TorqueTolerance;
        cMin = 1 - ps.TorqueTolerance;
        % NASA-STD-5020B Eq. 3 — Ppi_max = c_max·(1 + Γ)·Ppi_nom
        PpiMax = cMax * (1 + G) * PpiNom;
        if ps.SeparationCritical
            % NASA-STD-5020B Eq. 4 (separation-critical) — Ppi_min = c_min·(1 - Γ)·Ppi_nom
            PpiMin = cMin * (1 - G) * PpiNom;
        else
            % NASA-STD-5020B Eq. 5 (not separation-critical) — Ppi_min = c_min·(1 - Γ/√nf)·Ppi_nom
            PpiMin = cMin * (1 - G/sqrt(nf)) * PpiNom;
        end
    case model.PreloadMethod.DirectPreload
        % NASA-STD-5020B Eq. 3/4 uncertainty form with c = 1 (no torque
        % tolerance) — PpiMax = (1 + Γ)·Pnom, PpiMin = (1 - Γ)·Pnom
        PpiMax = (1 + G) * ps.NominalPreload;
        PpiMin = (1 - G) * ps.NominalPreload;
    otherwise
        error("engine:preload:unknownMethod", ...
            "Unsupported preload method: %s", string(ps.Method));
end

% ---- Thermal preload change (max-side gain / min-side loss, °C) --------
if ~isnan(ps.ThermalRate) && ps.ThermalRate ~= 0
    % Override path: supplied rate × the larger excursion from reference,
    % applied SYMMETRICALLY (+ on max, - on min — conservative both ways).
    % NASA TM-106943 (Chambers) Eq. 10 approximated by a supplied rate —
    % ThermalDelta = ThermalRate·dT
    dT = max(joint.MaxTemperature - joint.ReferenceTemperature, ...
             joint.ReferenceTemperature - joint.MinTemperature);
    td = ps.ThermalRate * dT;                                % lbf
    PthermalMax = td;
    PthermalMin = td;
else
    % Stiffness path: compute the CTE-mismatch preload change from the
    % joint stiffness for BOTH excursions (hot and cold).
    dThot  = joint.MaxTemperature - joint.ReferenceTemperature;   % °C, >= 0
    dTcold = joint.MinTemperature - joint.ReferenceTemperature;   % °C, <= 0
    if dThot == 0 && dTcold == 0
        % No thermal excursion — no CTE-mismatch load (stiffness not needed).
        PthermalMax = 0;
        PthermalMin = 0;
    else
        % engine.stiffness errors (threaded-in configuration, missing
        % frustum geometry) propagate — supply the geometry or a
        % ThermalRate override.
        s = engine.stiffness(joint);
        kSeries = s.Kb * s.Kc / (s.Kb + s.Kc);   % bolt+members in series, lbf/in
        % Thickness-weighted flange CTE (joint members), 1/°C
        t      = [joint.FlangeStack.Thickness];
        cte    = arrayfun(@(fl) fl.Material.CTE, joint.FlangeStack);
        alphaJ = sum(t .* cte) / sum(t);
        alphaB = joint.BoltMaterial.CTE;         % bolt CTE, 1/°C
        L      = joint.GripLength;               % clamped-stack length, in
        % NASA TM-106943 (Chambers) Eq. 10 — Pth = (Kb·Kc/(Kb+Kc))·L·ΔT·(αj − αb)
        PthHot  = kSeries * L * dThot  * (alphaJ - alphaB);  % lbf
        PthCold = kSeries * L * dTcold * (alphaJ - alphaB);  % lbf
        % Worst preload GAIN on the max side, worst LOSS on the min side,
        % each floored at zero (an excursion that only helps is not credited).
        PthermalMax = max([PthHot, PthCold, 0]);
        PthermalMin = max([-PthHot, -PthCold, 0]);
    end
end
ThermalDelta = PthermalMax;                      % reported: max-side gain, lbf

% ---- In-service min/max preload ----------------------------------------
% NASA-STD-5020B Eq. 1 — PpMax = PpiMax + P_thermal_max
PpMax = PpiMax + PthermalMax;
% NASA-STD-5020B Eq. 2 — PpMin = (1 - relaxation)·PpiMin - creep - P_thermal_min
PpMin = (1 - ps.RelaxationFraction) * PpiMin - ps.CreepLoss - PthermalMin;

p = struct( ...
    "PpiMax",       PpiMax, ...
    "PpiMin",       PpiMin, ...
    "ThermalDelta", ThermalDelta, ...
    "PpMax",        PpMax, ...
    "PpMin",        PpMin);
end
