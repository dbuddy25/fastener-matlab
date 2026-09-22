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
%
%   TEMPERATURE INVARIANT: the three properties are assigned by DIRECT
%   property write onto an ALREADY-BUILT Joint, which bypasses
%   model.Joint's constructor — the only place MinTemperature <=
%   ReferenceTemperature <= MaxTemperature is normally enforced
%   (model:Joint:temperatureOrder). A settings file with ColdTempC above
%   HotTempC (or either past NominalTempC) would otherwise build an
%   invalid joint silently and run the thermal preload chain on it. This
%   function re-asserts the SAME invariant, via model.Joint's own static
%   model.Joint.checkTemperatureOrder — not a second, hand-written
%   comparison that could drift from the constructor's — before stamping
%   the temperatures onto any joint.
factors = s.Factors;

% Re-asserted HERE TOO, not only inside engine.applyTemperatures: an
% EMPTY joint library never enters the loop, and an out-of-order settings
% file must be rejected on its own terms rather than going unnoticed
% because there happened to be no joints to stamp it onto.
model.Joint.checkTemperatureOrder(s.ColdTempC, s.NominalTempC, s.HotTempC);

% Delegated per joint. The settings -> joint MAPPING lives in exactly one
% place (engine.applyTemperatures), because the gui single-joint Analyze
% path needs the same mapping and this function is private to +engine —
% unreachable from the GUI.
for i = 1:numel(jl)
    jl(i).Joint = engine.applyTemperatures(jl(i).Joint, s);
end
end
