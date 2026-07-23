classdef Joint
    %JOINT  A complete bolted joint: bolt + materials + clamped stack + preload.
    %   Temperatures in °C (engine works internally in °C); loads in lbf.
    %
    %   Usage:
    %       b  = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
    %                       Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
    %                       TensileStressArea=0.0200, MinorDiameter=0.156);
    %       bm = model.Material(Name="A286", Ftu=140000, Fty=95000, ...
    %                           Fsu=85000, E=29.1e6, CTE=16.5e-6);
    %       fm = model.Material(Name="Al 7075-T7351", Ftu=68000, Fty=57000, ...
    %                           Fsu=39000, Fbru=121000, Fbry=94000, ...
    %                           E=10.3e6, CTE=23.2e-6);
    %       j  = model.Joint(Name="Demo joint", Bolt=b, BoltMaterial=bm, ...
    %                        FlangeStack=[model.FlangeLayer(Material=fm, Thickness=0.10), ...
    %                                     model.FlangeLayer(Material=fm, Thickness=0.15)], ...
    %                        ThreadedMember=model.ThreadedMember(RatedUltimateLoad=4080), ...
    %                        PreloadSpec=model.PreloadSpec(Method=model.PreloadMethod.DirectPreload, ...
    %                                                      NominalPreload=2000, Uncertainty=0.25), ...
    %                        MinTemperature=-54, MaxTemperature=71);
    %       j.GripLength   % -> 0.25 in

    properties
        Name                  (1,1) string = ""
        Bolt                  (1,1) model.Bolt = model.Bolt()
        BoltMaterial          (1,1) model.Material = model.Material()
        FlangeStack           (1,:) model.FlangeLayer = model.FlangeLayer.empty(1,0)   % ordered clamped layers
        ThreadedMember        (1,1) model.ThreadedMember = model.ThreadedMember()
        PreloadSpec           (1,1) model.PreloadSpec = model.PreloadSpec()
        BoltCount             (1,1) double {mustBePositive} = 1               % nf
        FrictionCoefficient   (1,1) double {mustBeNonnegative} = 0            % μ (0 → slip not evaluated)
        LoadingPlaneFactor    (1,1) double {mustBeNonnegative} = 1.0          % n = Llp/L (1.0 = conservative)
        BoltRatedUltimateLoad (1,1) double {mustBeNonnegativeOrNaN} = NaN     % spec Ptu-allow, lbf (NaN → derive At·Ftu)
        BoltRatedYieldLoad    (1,1) double {mustBeNonnegativeOrNaN} = NaN     % spec Pty-allow, lbf (NaN → derive)
        ReferenceTemperature  (1,1) double = 20                               % assembly/reference temp, °C
        MinTemperature        (1,1) double = 20                               % °C
        MaxTemperature        (1,1) double = 20                               % °C
        ShearPlane            (1,1) model.ShearPlaneCondition = model.ShearPlaneCondition.ThreadsInShear
        SlipMode              (1,1) model.SlipMode = model.SlipMode.SingleFastener   % slip check mode (default single-fastener)
    end

    properties (Dependent)
        GripLength   % total clamped-stack thickness, in
    end

    methods
        function obj = Joint(args)
            arguments
                args.?model.Joint
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
            temps = [obj.MinTemperature, obj.ReferenceTemperature, obj.MaxTemperature];
            if ~any(isnan(temps)) && ...
                    ~(obj.MinTemperature <= obj.ReferenceTemperature && ...
                      obj.ReferenceTemperature <= obj.MaxTemperature)
                error("model:Joint:temperatureOrder", ...
                    "Temperatures must satisfy MinTemperature <= ReferenceTemperature <= MaxTemperature (got %g <= %g <= %g °C).", ...
                    obj.MinTemperature, obj.ReferenceTemperature, obj.MaxTemperature);
            end
        end

        function g = get.GripLength(obj)
            if isempty(obj.FlangeStack)
                g = 0;
            else
                g = sum([obj.FlangeStack.Thickness]);
            end
        end
    end
end
