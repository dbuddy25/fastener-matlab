classdef PreloadSpec
    %PRELOADSPEC  Full preload definition for a joint (replaces a scalar preload).
    %   Captures how preload is established (torque control vs direct), its
    %   uncertainty Γ, relaxation/creep losses, and thermal behavior — the
    %   inputs to the min/max preload equations (NASA-STD-5020A Eq. 3/4/5, with the
    %   nominal preload from torque per NASA-STD-5020A Eq. 24).
    %
    %   Torque control is specified as NOMINAL torque + fractional tolerance
    %   (the NASA-STD-5020A c-factor form): a spec of "470 ± 20 in-lb" is
    %   NominalTorque = 470, TorqueTolerance = 20/470, giving the c-factors
    %   c_max = 1 + tol and c_min = 1 - tol of NASA-STD-5020A Eq. 3/4/5 (e.g. NASA-STD-5020A
    %   §4.3.1: "40 ± 2 N-m" -> c_max = 42/40 = 1.05, c_min = 38/40 = 0.95).
    %   TorqueMax/TorqueMin/CMax/CMin are derived (Dependent) for display.
    %
    %   Torque-controlled:
    %       ps = model.PreloadSpec(Method=model.PreloadMethod.TorqueControl, ...
    %                              NominalTorque=22.5, TorqueTolerance=0.10, ...
    %                              NutFactor=0.2, Uncertainty=0.25);
    %   Direct preload:
    %       ps = model.PreloadSpec(Method=model.PreloadMethod.DirectPreload, ...
    %                              NominalPreload=2000, Uncertainty=0.25);

    properties
        Method             (1,1) model.PreloadMethod = model.PreloadMethod.TorqueControl
        NominalTorque      (1,1) double {mustBeNonnegativeOrNaN} = NaN   % nominal applied effective torque T (above running torque), in-lbf
        TorqueTolerance    (1,1) double {mustBeNonnegative} = 0          % fractional torque tolerance (0.05 = ±5%)
        NutFactor          (1,1) double {mustBePositiveOrNaN} = 0.2      % K
        Uncertainty        (1,1) double {mustBeNonnegative} = 0.25       % preload uncertainty Γ
        RelaxationFraction (1,1) double {mustBeNonnegative} = 0.05
        CreepLoss          (1,1) double {mustBeNonnegative} = 0          % lbf
        SeparationCritical (1,1) logical = false                         % selects min-preload eqn (NASA-STD-5020A Eq. 4 vs Eq. 5)
        ThermalRate        (1,1) double = 0                              % lbf/°C; 0 = compute from CTE/stiffness later
        NominalPreload     (1,1) double {mustBePositiveOrNaN} = NaN      % lbf, used when Method = DirectPreload
    end

    properties (Dependent)
        TorqueMax          % in-lbf, NominalTorque·(1 + TorqueTolerance)
        TorqueMin          % in-lbf, NominalTorque·(1 - TorqueTolerance)
        CMax               % NASA-STD-5020A c_max = 1 + TorqueTolerance (Eq. 3)
        CMin               % NASA-STD-5020A c_min = 1 - TorqueTolerance (Eq. 4/5)
    end

    methods
        function obj = PreloadSpec(args)
            arguments
                args.?model.PreloadSpec
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end

        function v = get.TorqueMax(obj)
            v = obj.NominalTorque * (1 + obj.TorqueTolerance);
        end

        function v = get.TorqueMin(obj)
            v = obj.NominalTorque * (1 - obj.TorqueTolerance);
        end

        function v = get.CMax(obj)
            v = 1 + obj.TorqueTolerance;
        end

        function v = get.CMin(obj)
            v = 1 - obj.TorqueTolerance;
        end
    end
end
