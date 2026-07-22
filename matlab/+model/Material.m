classdef Material
    %MATERIAL  Mechanical + thermal properties of a bolt/flange/insert material.
    %   Strengths in psi; CTE in in/in/°F (engine works internally in °F).
    %
    %   m = model.Material(Name="A286", Ftu=140000, Fty=95000, Fsu=85000, ...
    %                      E=29.1e6, CTE=9.17e-6);

    properties
        Name (1,1) string = ""
        Ftu  (1,1) double {mustBeNonnegative} = 0   % ultimate tensile strength, psi
        Fty  (1,1) double {mustBeNonnegative} = 0   % tensile yield strength, psi
        Fsu  (1,1) double {mustBeNonnegative} = 0   % ultimate shear strength, psi
        Fbru (1,1) double {mustBeNonnegative} = 0   % ultimate bearing strength, psi
        Fbry (1,1) double {mustBeNonnegative} = 0   % bearing yield strength, psi
        E    (1,1) double {mustBeNonnegative} = 0   % elastic (Young's) modulus, psi
        CTE  (1,1) double = 0                        % coeff. of thermal expansion, in/in/°F
    end

    methods
        function obj = Material(args)
            arguments
                args.?model.Material
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end
    end
end
