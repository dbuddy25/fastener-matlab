classdef Factors
    %FACTORS  Safety + fitting factors (program-level policy).
    %   Passed to analyze() alongside the Joint and LoadCase — not stored on
    %   the Joint. Built-in default preset = DABJ example factors.
    %
    %   fac = model.Factors();                 % DABJ defaults
    %   fac = model.Factors(FSU=1.4, FFU=1.15);

    properties
        FSU    (1,1) double {mustBePositive} = 1.4    % ultimate factor of safety
        FSY    (1,1) double {mustBePositive} = 1.25   % yield factor of safety
        FSSep  (1,1) double {mustBePositive} = 1.0    % separation factor of safety
        FFU    (1,1) double {mustBePositive} = 1.15   % ultimate fitting factor
        FFY    (1,1) double {mustBePositive} = 1.0    % yield fitting factor
        FFSep  (1,1) double {mustBePositive} = 1.0    % separation fitting factor
        FSSlip (1,1) double {mustBePositive} = 1.0    % slip factor of safety
    end

    methods
        function obj = Factors(args)
            arguments
                args.?model.Factors
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end
    end
end
