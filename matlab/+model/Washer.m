classdef Washer
    %WASHER  A washer under the bolt head or nut.
    %   Washers are treated as RIGID in the conical-frustum member-stiffness
    %   model (DABJ §8): they do not deform as frustum material, but they
    %   enter the member stiffness kc through the contact diameter dc
    %   (the frustum spreads through the washer thickness before reaching
    %   the fitting stack) and enter the bolt stiffness kb through the
    %   added clamped length.
    %
    %   w = model.Washer(Thickness=0.078, OuterDiameter=0.687);

    properties
        Thickness     (1,1) double {mustBeNonnegative} = 0     % in
        OuterDiameter (1,1) double {mustBePositiveOrNaN} = NaN % in (NaN = unspecified; frustum cone diameter governs)
    end

    methods
        function obj = Washer(args)
            arguments
                args.?model.Washer
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end
    end
end
