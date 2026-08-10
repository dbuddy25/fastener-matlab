function j = applyTemperatures(j, s)
%APPLYTEMPERATURES  Stamp the global service temperatures onto ONE joint.
%   j = engine.applyTemperatures(j, s) applies a settings struct `s`
%   (fields NominalTempC / HotTempC / ColdTempC, °C) to a model.Joint:
%       ReferenceTemperature = s.NominalTempC
%       MaxTemperature       = s.HotTempC
%       MinTemperature       = s.ColdTempC
%
%   Temperatures are a PROJECT-LEVEL setting, not a joint property the
%   user edits — one isothermal-soak trio for every joint (UNITS.md: the
%   engine works internally in °C). They are therefore stamped onto the
%   joint at the moment of analysis rather than carried on it, which is
%   why a joint saved to the defined-joints library does not need them.
%
%   THE ONE PLACE THE settings -> joint MAPPING LIVES. It used to live
%   only inside the private applyGlobalSettings, which is reachable from
%   the bulk runners and nothing else, so the gui2 single-joint Analyze
%   path never applied the temperatures at all: every single-joint run
%   used model.Joint's 20/20/20 °C defaults and produced a thermal
%   preload term of exactly zero no matter what the Temp & Loads page
%   said. Anything that runs a joint must come through here.
%
%   TEMPERATURE INVARIANT: this writes the three properties DIRECTLY onto
%   an already-built Joint, which bypasses model.Joint's constructor — the
%   only place MinTemperature <= ReferenceTemperature <= MaxTemperature is
%   normally enforced. It re-asserts that invariant first, via
%   model.Joint's OWN static checkTemperatureOrder rather than a
%   hand-written comparison that could drift from the constructor's, so an
%   out-of-order settings file cannot silently build an invalid joint and
%   run the thermal preload chain on it.
%
%   Call graph:
%       Precedents (calls)      model.Joint.checkTemperatureOrder — the
%                               shared invariant. Otherwise a leaf.
%       Dependents (called by)  engine/private/applyGlobalSettings (and so
%                               engine.runBulk / engine.runWorkbook), and
%                               gui2.JointConfigPage's Analyze path.
%       Tests                   tests/tApplyGlobalSettings.m
%
%   Validation status/coverage: no dedicated VALIDATION.md row — exercised
%   as a shared input to the "Bulk runner + XLSX export" and
%   "Single-workbook end-to-end" structural rows.

arguments
    j (1,1) model.Joint
    s (1,1) struct
end

% Re-assert the invariant BEFORE stamping (see header): the writes below
% do not go through model.Joint's constructor.
model.Joint.checkTemperatureOrder(s.ColdTempC, s.NominalTempC, s.HotTempC);

j.ReferenceTemperature = s.NominalTempC;
j.MaxTemperature       = s.HotTempC;
j.MinTemperature       = s.ColdTempC;
end
