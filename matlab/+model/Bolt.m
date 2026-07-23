classdef Bolt
    %BOLT  Geometry + thread definition of an inch-series bolt (material is separate).
    %
    %   Construct with name-value pairs:
    %       b = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
    %                      Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
    %                      TensileStressArea=0.0200, MinorDiameter=0.156);
    %       b.Pitch    % -> 1/32 in

    properties
        Designation       (1,1) string = ""                            % e.g. "#10-32 UNF"
        NominalDiameter   (1,1) double {mustBePositiveOrNaN} = NaN     % major dia D, in
        Series            (1,1) model.ThreadSeries = model.ThreadSeries.UNF
        ThreadsPerInch    (1,1) double {mustBePositiveOrNaN} = NaN     % n (TPI)
        TensileStressArea (1,1) double {mustBePositiveOrNaN} = NaN     % At, in^2
        MinorDiameter     (1,1) double {mustBePositiveOrNaN} = NaN     % minor (thread-root) diameter, in
        BodyDiameter      (1,1) double {mustBePositiveOrNaN} = NaN     % unthreaded shank diameter, in (NaN → use NominalDiameter)
        HeadBearingDiameter (1,1) double {mustBePositiveOrNaN} = NaN   % washer-face / head bearing dia d_wf, in
    end

    properties (Dependent)
        Pitch       % thread pitch, p = 1/n, in
        MinorArea   % minor (thread-root) area, in^2
        BodyArea    % unthreaded shank area, in^2 (falls back to NominalDiameter)
    end

    methods
        function obj = Bolt(args)
            arguments
                args.?model.Bolt
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end

        function p = get.Pitch(obj)
            p = 1 / obj.ThreadsPerInch;
        end

        function a = get.MinorArea(obj)
            a = pi/4 * obj.MinorDiameter^2;
        end

        function a = get.BodyArea(obj)
            d = obj.BodyDiameter;
            if isnan(d)
                d = obj.NominalDiameter;
            end
            a = pi/4 * d^2;
        end
    end
end
