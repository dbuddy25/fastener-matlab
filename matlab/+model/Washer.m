classdef Washer
    %WASHER  A washer under the bolt head or nut.
    %   Washers are treated as RIGID in the conical-frustum member-stiffness
    %   model (DABJ §8): they do not deform as frustum material, but they
    %   enter the member stiffness kc through the contact diameter dc
    %   (the frustum spreads through the washer thickness before reaching
    %   the fitting stack) and enter the bolt stiffness kb through the
    %   added clamped length.
    %
    %   MATERIAL IS USED — for the THERMAL term, not for stiffness. Rigid in
    %   the frustum is a STIFFNESS idealisation, not a thermal one: a washer
    %   still occupies clamped length and still expands with its own CTE, so
    %   engine.preload includes it in the member CTE sum for TM-106943
    %   Eq. 10 (see that function; before 2026-08-13 washers were thermally
    %   absent, which was arithmetically identical to giving every washer
    %   the BOLT's CTE). A washer with Thickness > 0 whose Material carries
    %   no CTE makes the thermal calculation REFUSE rather than silently
    %   drop the term. InnerDiameter is still carried for completeness only
    %   (library / template round-tripping).
    %
    %   w = model.Washer(Thickness=0.078, OuterDiameter=0.687);

    properties
        Thickness     (1,1) double {mustBeNonnegative} = 0     % in
        OuterDiameter (1,1) double {mustBePositiveOrNaN} = NaN % in (NaN = unspecified; frustum cone diameter governs)
        InnerDiameter (1,1) double {mustBePositiveOrNaN} = NaN % ID, in (carried for completeness; unused by the engine)
        Material      (1,1) model.Material = model.Material()  % CTE feeds the thermal preload term; rigid in the frustum
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
