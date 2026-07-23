classdef FlangeLayer
    %FLANGELAYER  One layer of the clamped stack (flanges only, not threads).
    %   HoleDiameter and EdgeDistance are the Phase 3.2 member-strength
    %   geometry: HoleDiameter feeds the bearing-under-head/nut annulus
    %   (engine.marginBearingUnderHead) and EdgeDistance the shear tear-out
    %   check (engine.marginShearTearout). Both default NaN ("unconfigured");
    %   checks that need them report NotEvaluated until they are set.
    %
    %   fl = model.FlangeLayer(Material=al7075, Thickness=0.10, ...
    %                          HoleDiameter=0.397, EdgeDistance=0.75);

    properties
        Name             (1,1) string = ""                          % cosmetic layer label (e.g. "Bracket flange")
        Material         (1,1) model.Material = model.Material()
        Thickness        (1,1) double {mustBePositive} = 0.1        % in
        HoleDiameter     (1,1) double {mustBePositiveOrNaN} = NaN   % clearance/hole diameter dh, in
        EdgeDistance     (1,1) double {mustBePositiveOrNaN} = NaN   % hole center -> free edge, e, in
        CheckShearTearout (1,1) logical = true                      % run tear-out on this layer when EdgeDistance is set
    end

    methods
        function obj = FlangeLayer(args)
            arguments
                args.?model.FlangeLayer
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end
    end
end
