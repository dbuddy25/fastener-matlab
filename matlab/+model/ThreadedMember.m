classdef ThreadedMember
    %THREADEDMEMBER  What the bolt threads into (nut, insert, or tapped hole).
    %   For a Nut, RatedUltimateLoad is the spec-rated Pult (per NASA-STD-5020B
    %   §4.2.2.8) and Material.Fsu drives the nut internal-thread-shear check
    %   (engine.marginNutStrength). For an Insert, RatedUltimateLoad is the
    %   MANUFACTURER rated pull-out load (Heli-Coil spec value) consumed by
    %   engine.marginInsert. For a TappedHole, Material is the PARENT material
    %   whose Fsu drives the parent-thread-shear check
    %   (engine.marginTappedParentThread); RatedUltimateLoad may stay 0.
    %   EngagementLength is the thread engagement Le (nut thread height /
    %   tapped depth) used by the 0.75·pi·E·Le thread-shear areas (Phase 3.3).
    %
    %   tm = model.ThreadedMember(Type=model.ThreadedMemberType.Nut, ...
    %                             Material=nutMat, RatedUltimateLoad=4080, ...
    %                             EngagementLength=0.3);

    properties
        Type              (1,1) model.ThreadedMemberType = model.ThreadedMemberType.Nut
        Material          (1,1) model.Material = model.Material()   % nut/insert/parent material
        RatedUltimateLoad (1,1) double {mustBeNonnegative} = 0      % spec-rated Pult (nut) / rated pull-out (insert), lbf
        EngagementLength  (1,1) double {mustBePositiveOrNaN} = NaN  % thread engagement Le, in (nut height / tapped depth)
        BearingDiameter   (1,1) double {mustBePositiveOrNaN} = NaN  % nut/head bearing dia for under-nut bearing, in
        HostName          (1,1) string = ""                         % parent/host body name (cosmetic)
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
