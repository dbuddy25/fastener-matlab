function file = saveFactorPreset(name, factors, file)
%SAVEFACTORPRESET  Save a USER factor preset (Phase 3.7).
%   data.saveFactorPreset(name, factors) saves `factors` under `name` into
%   the user factor-presets file (default path: userFactorPresetsPath(),
%   e.g. fullfile(userpath, "fastener_factor_presets.json"), or a
%   repo-local fallback next to +data/ when userpath() is empty).
%
%   file = data.saveFactorPreset(name, factors, file) points the save at a
%   specific file instead (used by tests so they don't touch the real
%   userpath). Returns the resolved path (string).
%
%   BUILT-IN NAMES ARE PROTECTED: saving under a name already used by
%   data.factorPresets (e.g. "NASA-STD-5020B") errors — built-in presets
%   can never be shadowed or overwritten. Saving under an existing USER
%   preset name overwrites that user preset.
%
%   Example:
%       f = data.saveFactorPreset("My program factors", ...
%               model.Factors(FSU=1.5), string(tempname) + ".json");
%       data.factorPreset("My program factors", f).FSU   % -> 1.5

arguments
    name    (1,1) string
    factors (1,1) model.Factors
    file    (1,1) string = userFactorPresetsPath()
end

built = data.factorPresets();
if isKey(built, char(name))
    error("data:saveFactorPreset:protectedName", ...
        """%s"" is a built-in factor preset name and cannot be overwritten. Choose a different name.", ...
        name);
end

user = loadUserFactorPresets(file);
user(char(name)) = factors;
writeUserFactorPresets(user, file);
end
