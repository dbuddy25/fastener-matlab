classdef ThreadedMember
    %THREADEDMEMBER  What the bolt threads into (nut, insert, or tapped hole).
    %   For a Nut or Insert, RatedUltimateLoad is the spec-rated Pult
    %   (per NASA-STD-5020A §4.2.2.8). For a TappedHole, Material is the PARENT
    %   material and RatedUltimateLoad may be 0 — parent-thread-shear is
    %   computed later (Phase 3.3).
    %
    %   tm = model.ThreadedMember(Type=model.ThreadedMemberType.Nut, ...
    %                             Material=nutMat, RatedUltimateLoad=4080);

    properties
        Type              (1,1) model.ThreadedMemberType = model.ThreadedMemberType.Nut
        Material          (1,1) model.Material = model.Material()   % nut/insert/parent material
        RatedUltimateLoad (1,1) double {mustBeNonnegative} = 0      % spec-rated Pult, lbf
    end

    methods
        function obj = ThreadedMember(args)
            arguments
                args.?model.ThreadedMember
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end
    end
end
