function [jl, factors] = applyGlobalSettings(jl, s)
%APPLYGLOBALSETTINGS  Stamp the global settings onto a parsed joint library.
%   [jl, factors] = applyGlobalSettings(jl, s) applies a data.loadSettings
%   struct `s` to a data.loadJointLibrary struct array `jl`: every Joint
%   gets the three global temperatures
%       ReferenceTemperature = s.NominalTempC
%       MaxTemperature       = s.HotTempC
%       MinTemperature       = s.ColdTempC
%   and `factors` is s.Factors (the model.Factors built from the settings
%   file), ready to pass to engine.analyzeBulk.
%
%   SHARED by engine.runBulk and engine.runWorkbook — the one place the
%   "settings -> joints" application lives, so the two entry points cannot
%   drift.
factors = s.Factors;
for i = 1:numel(jl)
    j = jl(i).Joint;
    j.ReferenceTemperature = s.NominalTempC;
    j.MaxTemperature       = s.HotTempC;
    j.MinTemperature       = s.ColdTempC;
    jl(i).Joint = j;
end
end
