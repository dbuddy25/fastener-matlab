classdef FlangeLayer
    %FLANGELAYER  One layer of the clamped stack (flanges only, not threads).
    %
    %   fl = model.FlangeLayer(Material=al7075, Thickness=0.10);

    properties
        Material  (1,1) model.Material = model.Material()
        Thickness (1,1) double {mustBePositive} = 0.1   % in
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
