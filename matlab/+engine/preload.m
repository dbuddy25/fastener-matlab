function p = preload(joint)
%PRELOAD  Min/max bolt preload incl. thermal (NASA-STD-5020A Eq. 25/26 + Eq. 1/2).
%   p = engine.preload(joint) computes the initial and worst-case preloads
%   for one joint. All loads in lbf, torque in in-lbf, temperature in °C
%   (see UNITS.md).
%
%   Returned struct fields (all lbf):
%       PpiMax       max initial preload at installation (Eq. 25)
%       PpiMin       min initial preload at installation (Eq. 26a/26b)
%       ThermalDelta preload change over the worst thermal excursion (>= 0)
%       PpMax        max in-service preload = PpiMax + ThermalDelta
%       PpMin        min in-service preload =
%                    (1 - relaxation)·PpiMin - creep - ThermalDelta
%
%   Preload method (PreloadSpec.Method):
%     TorqueControl — preload from effective torque and nut factor K:
%         PpiMax = (1 + Γ)·Tmax / (K·D)                       (Eq. 25)
%         PpiMin = (1 - Γ)·Tmin / (K·D)          separation-critical (Eq. 26a)
%         PpiMin = (1 - Γ/√nf)·Tmin / (K·D)      otherwise           (Eq. 26b)
%       where Γ = PreloadSpec.Uncertainty and nf = joint.BoltCount.
%     DirectPreload — nominal preload specified directly:
%         PpiMax = (1 + Γ)·Pnom,   PpiMin = (1 - Γ)·Pnom
%
%   Thermal: ThermalDelta = PreloadSpec.ThermalRate (lbf/°C) × the larger
%   excursion from ReferenceTemperature toward MaxTemperature or
%   MinTemperature. Applied as +ThermalDelta on the max side and
%   -ThermalDelta on the min side (conservative both ways).
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
        PpiMax = (1 + G) * ps.TorqueMax / (K * D);           % Eq. 25
        if ps.SeparationCritical
            PpiMin = (1 - G) * ps.TorqueMin / (K * D);       % Eq. 26a
        else
            PpiMin = (1 - G/sqrt(nf)) * ps.TorqueMin / (K * D);  % Eq. 26b
        end
    case model.PreloadMethod.DirectPreload
        PpiMax = (1 + G) * ps.NominalPreload;
        PpiMin = (1 - G) * ps.NominalPreload;
    otherwise
        error("engine:preload:unknownMethod", ...
            "Unsupported preload method: %s", string(ps.Method));
end

% ---- Thermal excursion (worst direction from reference, °C) ------------
dT = max(joint.MaxTemperature - joint.ReferenceTemperature, ...
         joint.ReferenceTemperature - joint.MinTemperature);
ThermalDelta = ps.ThermalRate * dT;                          % lbf

% ---- In-service min/max preload ----------------------------------------
PpMax = PpiMax + ThermalDelta;
PpMin = (1 - ps.RelaxationFraction) * PpiMin - ps.CreepLoss - ThermalDelta;

p = struct( ...
    "PpiMax",       PpiMax, ...
    "PpiMin",       PpiMin, ...
    "ThermalDelta", ThermalDelta, ...
    "PpMax",        PpMax, ...
    "PpMin",        PpMin);
end
