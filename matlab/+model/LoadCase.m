classdef LoadCase
    %LOADCASE  Applied limit loads for ONE analysis case.
    %   The engine consumes per-bolt loads already resolved upstream (most-loaded
    %   bolt). Joint-level totals are stored separately because joint totals are
    %   NOT simply BoltCount × per-bolt; leave a joint-level load NaN to mean
    %   "engine derives from BoltCount × per-bolt."
    %
    %   lc = model.LoadCase(Name="Liftoff", BoltTensileLimitLoad=1200, ...
    %                       BoltShearLimitLoad=400);
    %
    %   BoltShearLimitLoad is per shear plane, not the bolt's total shear.
    %   NASA-STD-5020B Eq. 14 defines PsL as "the limit shear load acting on
    %   the shear plane", and engine.marginShearUlt compares it against the
    %   allowable for one area (Eq. 12's pi*D^2*Fsu/4 or Eq. 13's Fsu*Am) --
    %   one plane's worth of capacity.
    %
    %   The two are the same number in single shear, which is the only
    %   configuration this tool is used for, so nothing here needs a
    %   shear-plane count. It matters only if a bolt crosses more than one
    %   faying surface: in double shear the bolt carries V but each plane
    %   carries V/2, and entering the bolt total would compare two planes of
    %   load against one plane of capacity -- conservative by 2x, never
    %   unconservative. 5020B frames the allowable the same way ("the
    %   allowable ultimate shear load per shear plane is commonly assumed to
    %   be half the value given in the fastener specification for
    %   double-shear joints").

    properties
        Name                  (1,1) string = ""
        BoltTensileLimitLoad  (1,1) double {mustBeNonnegativeOrNaN} = NaN   % PtL, most-loaded bolt, lbf
        BoltShearLimitLoad    (1,1) double {mustBeNonnegativeOrNaN} = NaN   % PsL, most-loaded bolt, per shear plane, lbf (see note)
        % In-lbf, not lbf -- the only moment on this class, and the only
        % field here that is not a force. MbL, the limit bending moment on
        % the most-loaded bolt, feeding the NASA-STD-5020B Eq. 20/22 fbu
        % term via engine.designLoads -> engine.marginInteraction.
        % NaN (the default) means no bending moment was supplied, which
        % §4.4.4 permits whenever the shear is not transferred across a gap
        % and the fit is close or interference -- see
        % Joint.ShearTransferCondition, which records which of those a
        % joint is in. NaN yields fbu = 0 exactly.
        BoltBendingLimitMoment (1,1) double {mustBeNonnegativeOrNaN} = NaN  % MbL, most-loaded bolt, in-lbf
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
