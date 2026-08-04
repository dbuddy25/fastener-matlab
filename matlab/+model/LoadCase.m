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
