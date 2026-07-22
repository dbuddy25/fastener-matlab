classdef Bolt
    %BOLT  Geometry + thread definition of an inch-series bolt (material is separate).
    %
    %   Construct with name-value pairs:
    %       b = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
    %                      Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
    %                      TensileStressArea=0.0200);
    %       b.Pitch    % -> 1/32 in

    properties
        Designation       (1,1) string = ""                            % e.g. "#10-32 UNF"
        NominalDiameter   (1,1) double {mustBePositive} = 0.1900       % major dia D, in
        Series            (1,1) model.ThreadSeries = model.ThreadSeries.UNF
        ThreadsPerInch    (1,1) double {mustBePositive} = 32           % n (TPI)
        TensileStressArea (1,1) double {mustBePositive} = 0.0200       % At, in^2
    end

    properties (Dependent)
        Pitch   % thread pitch, p = 1/n, in
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
    end
end
