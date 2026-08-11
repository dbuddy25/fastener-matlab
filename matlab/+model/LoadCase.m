classdef LoadCase
    %LOADCASE  Applied limit loads for ONE analysis case.
    %   The engine consumes per-bolt loads already resolved upstream (most-loaded
    %   bolt). Joint-level totals are stored separately because joint totals are
    %   NOT simply BoltCount × per-bolt; leave a joint-level load NaN to mean
    %   "engine derives from BoltCount × per-bolt."
    %
    %   lc = model.LoadCase(Name="Liftoff", BoltTensileLimitLoad=1200, ...
    %                       BoltShearLimitLoad=400);

    properties
        Name                  (1,1) string = ""
        BoltTensileLimitLoad  (1,1) double {mustBeNonnegativeOrNaN} = NaN   % PtL, most-loaded bolt, lbf
        BoltShearLimitLoad    (1,1) double {mustBeNonnegativeOrNaN} = NaN   % PsL, most-loaded bolt, lbf
        % IN-LBF, NOT LBF -- the only moment on this class, and the only
        % field here that is not a force. MbL, the limit bending moment on
        % the most-loaded bolt, feeding the NASA-STD-5020B Eq. 20/22 fbu
        % term via engine.designLoads -> engine.marginInteraction.
        % NaN (the default) means no bending moment was supplied, which
        % §4.4.4 permits whenever the shear is not transferred across a gap
        % and the fit is close or interference -- see
        % Joint.ShearTransferCondition, which records WHICH of those a
        % joint is in. NaN yields fbu = 0 exactly, so a joint with no
        % moment analyses precisely as it did before this field existed.
        BoltBendingLimitMoment (1,1) double {mustBeNonnegativeOrNaN} = NaN  % MbL, most-loaded bolt, IN-LBF
        JointTensileLimitLoad (1,1) double {mustBeNonnegativeOrNaN} = NaN   % joint total, lbf (NaN → engine derives)
        JointShearLimitLoad   (1,1) double {mustBeNonnegativeOrNaN} = NaN   % joint total, lbf (NaN → engine derives)
    end

    methods
        function obj = LoadCase(args)
            arguments
                args.?model.LoadCase
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end
    end
end
