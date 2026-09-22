classdef Material
    %MATERIAL  Mechanical + thermal properties of a bolt/flange/insert material.
    %   Strengths in psi; CTE in 1/°C (engine works internally in °C).
    %
    %   CTE's unset value is NaN, not zero. Zero is a legitimate-looking
    %   physical claim ("this material does not expand"), so defaulting to
    %   it would make "no coefficient supplied" indistinguishable from
    %   "measured at zero", and the thermal-preload term (NASA TM-106943
    %   Eq. 10, via engine.preload) would compute a confident number from an
    %   input nobody had given. NaN makes the absence detectable, and
    %   engine.preload refuses with engine:preload:missingCTE naming what to
    %   fix. Every other optional number in +model uses NaN the same way.
    %
    %   engine.summary renders it through fmt(), which prints NaN as "—",
    %   so an unspecified coefficient reads as unspecified rather than as
    %   a zero someone might trust. data.Library stores catalogue entries
    %   as raw structs, so this default never round-trips into
    %   library.json.
    %
    %   m = model.Material(Name="A286", Ftu=140000, Fty=95000, Fsu=85000, ...
    %                      E=29.1e6, CTE=16.5e-6);

    properties
        Name (1,1) string = ""
        Ftu  (1,1) double {mustBePositiveOrNaN} = NaN   % ultimate tensile strength, psi
        Fty  (1,1) double {mustBePositiveOrNaN} = NaN   % tensile yield strength, psi
        Fsu  (1,1) double {mustBePositiveOrNaN} = NaN   % ultimate shear strength, psi
        Fsy  (1,1) double {mustBePositiveOrNaN} = NaN   % shear yield strength, psi (NaN -> engine.shearYieldStrength estimates Fty/sqrt(3), von Mises — the estimate is flagged in the margin Detail)
        Fbru (1,1) double {mustBeNonnegative} = 0       % ultimate bearing strength, psi
        Fbry (1,1) double {mustBeNonnegative} = 0       % bearing yield strength, psi
        E    (1,1) double {mustBePositiveOrNaN} = NaN   % elastic (Young's) modulus, psi
        CTE  (1,1) double = NaN                      % coeff. of thermal expansion, 1/°C (NaN = not specified)
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
