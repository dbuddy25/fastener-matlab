function p = preload(joint)
%PRELOAD  Min/max bolt preload incl. thermal (NASA-STD-5020A Eq. 25/26 + Eq. 1/2;
%   thermal change per NASA TM-106943 Eq. 10).
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
%   Thermal: preload change from CTE mismatch per NASA TM-106943 (Chambers)
%   Eq. 10 — P_dT = (Kb·Kj)/(Kb+Kj)·L·ΔT·(CTE_j − CTE_b) — approximated here
%   by a supplied rate: ThermalDelta = PreloadSpec.ThermalRate (lbf/°C) × the
%   larger excursion from ReferenceTemperature toward MaxTemperature or
%   MinTemperature (Phase 3.1 adds the stiffness-based form). Applied as
%   +ThermalDelta on the max side and -ThermalDelta on the min side
%   (conservative both ways).
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
        % NASA-STD-5020A Eq. 25 — PpiMax = (1 + Γ)·Tmax / (K·D)
        PpiMax = (1 + G) * ps.TorqueMax / (K * D);
        if ps.SeparationCritical
            % NASA-STD-5020A Eq. 26a (separation-critical) — PpiMin = (1 - Γ)·Tmin / (K·D)
            PpiMin = (1 - G) * ps.TorqueMin / (K * D);
        else
            % NASA-STD-5020A Eq. 26b (not separation-critical) — PpiMin = (1 - Γ/√nf)·Tmin / (K·D)
            PpiMin = (1 - G/sqrt(nf)) * ps.TorqueMin / (K * D);
        end
    case model.PreloadMethod.DirectPreload
        % NASA-STD-5020A Eq. 25/26 uncertainty form (no numbered eq for
        % direct preload) — PpiMax = (1 + Γ)·Pnom, PpiMin = (1 - Γ)·Pnom
        PpiMax = (1 + G) * ps.NominalPreload;
        PpiMin = (1 - G) * ps.NominalPreload;
    otherwise
        error("engine:preload:unknownMethod", ...
            "Unsupported preload method: %s", string(ps.Method));
end

% ---- Thermal excursion (worst direction from reference, °C) ------------
dT = max(joint.MaxTemperature - joint.ReferenceTemperature, ...
         joint.ReferenceTemperature - joint.MinTemperature);
% NASA TM-106943 (Chambers) Eq. 10 — thermal preload change from CTE mismatch;
% full form P_dT = (Kb·Kj)/(Kb+Kj)·L·ΔT·(CTE_j − CTE_b). Here approximated by a
% supplied rate (Phase 3.1 adds the stiffness-based form): ThermalDelta = ThermalRate·dT
ThermalDelta = ps.ThermalRate * dT;                          % lbf

% ---- In-service min/max preload ----------------------------------------
% NASA-STD-5020A Eq. 1 — PpMax = PpiMax + ThermalDelta
PpMax = PpiMax + ThermalDelta;
% NASA-STD-5020A Eq. 2 — PpMin = (1 - relaxation)·PpiMin - creep - ThermalDelta
PpMin = (1 - ps.RelaxationFraction) * PpiMin - ps.CreepLoss - ThermalDelta;

p = struct( ...
    "PpiMax",       PpiMax, ...
    "PpiMin",       PpiMin, ...
    "ThermalDelta", ThermalDelta, ...
    "PpMax",        PpMax, ...
    "PpMin",        PpMin);
end
