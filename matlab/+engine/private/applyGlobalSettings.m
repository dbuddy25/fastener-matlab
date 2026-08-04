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
%
%   Call graph:
%       Precedents (calls)      model.Joint.checkTemperatureOrder (the
%                               temperature-order invariant, shared with
%                               model.Joint's own constructor); otherwise a
%                               leaf — no other engine.* dependencies.
%       Dependents (called by)  engine.runBulk, engine.runWorkbook (both
%                               via the private/ path, private to +engine).
%       Tests                   tests/tApplyGlobalSettings.m
%                               outOfOrderSettingsTemperaturesRejected;
%                               also exercised via tests/tExport.m
%                               runBulkEndToEnd and tests/tWorkbook.m
%                               workbookRunsFreshTemplateWithoutCrashing,
%                               both of which depend on the stamped
%                               temperatures reaching engine.preload.
%
%   Validation status/coverage: no dedicated VALIDATION.md row — this
%   function is exercised as a shared input to the Structural/non-numeric
%   rows "Bulk runner + XLSX export" and "Single-workbook end-to-end".
factors = s.Factors;

% Re-assert the invariant here (see header): the loop below writes these
% three temperatures onto an already-built Joint's properties directly,
% which does not go through model.Joint's constructor.
model.Joint.checkTemperatureOrder(s.ColdTempC, s.NominalTempC, s.HotTempC);

for i = 1:numel(jl)
    j = jl(i).Joint;
    j.ReferenceTemperature = s.NominalTempC;
    j.MaxTemperature       = s.HotTempC;
    j.MinTemperature       = s.ColdTempC;
    jl(i).Joint = j;
end
end
