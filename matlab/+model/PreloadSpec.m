classdef PreloadSpec
    %PRELOADSPEC  Full preload definition for a joint (replaces a scalar preload).
    %   Captures how preload is established (torque control vs direct), its
    %   uncertainty Γ, relaxation/creep losses, and thermal behavior — the
    %   inputs to the min/max preload equations (5020A Eq. 25/26).
    %
    %   Torque-controlled:
    %       ps = model.PreloadSpec(Method=model.PreloadMethod.TorqueControl, ...
    %                              TorqueMin=20, TorqueMax=25, ...
    %                              NutFactor=0.2, Uncertainty=0.25);
    %   Direct preload:
    %       ps = model.PreloadSpec(Method=model.PreloadMethod.DirectPreload, ...
    %                              NominalPreload=2000, Uncertainty=0.25);

    properties
        Method             (1,1) model.PreloadMethod = model.PreloadMethod.TorqueControl
        TorqueMin          (1,1) double {mustBeNonnegativeOrNaN} = NaN   % effective torque (above running torque), in-lbf
        TorqueMax          (1,1) double {mustBeNonnegativeOrNaN} = NaN   % in-lbf
        NutFactor          (1,1) double {mustBePositiveOrNaN} = 0.2      % K
        Uncertainty        (1,1) double {mustBeNonnegative} = 0.25       % preload uncertainty Γ
        RelaxationFraction (1,1) double {mustBeNonnegative} = 0.05
        CreepLoss          (1,1) double {mustBeNonnegative} = 0          % lbf
        SeparationCritical (1,1) logical = false                         % selects min-preload eqn (26a vs 26b)
        ThermalRate        (1,1) double = 0                              % lbf/°C; 0 = compute from CTE/stiffness later
        NominalPreload     (1,1) double {mustBePositiveOrNaN} = NaN      % lbf, used when Method = DirectPreload
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
    end
end
