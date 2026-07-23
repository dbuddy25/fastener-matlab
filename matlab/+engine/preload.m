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
%       ThermalDelta preload change over the worst thermal excursion (>= 0)
%       PpMax        max in-service preload = PpiMax + ThermalDelta
%       PpMin        min in-service preload =
%                    (1 - relaxation)·PpiMin - creep - ThermalDelta
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

% ---- Thermal excursion (worst direction from reference, °C) ------------
dT = max(joint.MaxTemperature - joint.ReferenceTemperature, ...
         joint.ReferenceTemperature - joint.MinTemperature);
% NASA TM-106943 (Chambers) Eq. 10 — thermal preload change from CTE mismatch;
% full form P_dT = (Kb·Kj)/(Kb+Kj)·L·ΔT·(CTE_j − CTE_b). Here approximated by a
% supplied rate (Phase 3.1 adds the stiffness-based form): ThermalDelta = ThermalRate·dT
ThermalDelta = ps.ThermalRate * dT;                          % lbf

% ---- In-service min/max preload ----------------------------------------
% NASA-STD-5020B Eq. 1 — PpMax = PpiMax + ThermalDelta
PpMax = PpiMax + ThermalDelta;
% NASA-STD-5020B Eq. 2 — PpMin = (1 - relaxation)·PpiMin - creep - ThermalDelta
PpMin = (1 - ps.RelaxationFraction) * PpiMin - ps.CreepLoss - ThermalDelta;

p = struct( ...
    "PpiMax",       PpiMax, ...
    "PpiMin",       PpiMin, ...
    "ThermalDelta", ThermalDelta, ...
    "PpMax",        PpMax, ...
    "PpMin",        PpMin);
end
