function f = factorPreset(name, userFile)
%FACTORPRESET  model.Factors for a built-in OR user preset name (Phase 3.7).
%   f = data.factorPreset(name) looks up `name` in the built-in presets
%   (data.factorPresets) first, then the user presets file (default path:
%   userFactorPresetsPath() — see data.saveFactorPreset). A user preset can
%   never shadow a built-in name (data.saveFactorPreset refuses to write
%   one), so the lookup order only matters for which map answers first.
%   Errors clearly, listing every available name, when `name` matches
%   neither.
%
%   f = data.factorPreset(name, userFile) points the user-preset lookup at
%   a specific file instead of the default user-area path (used by tests
%   so they don't touch the real userpath).
%
%   Example:
%       f = data.factorPreset("NASA-STD-5020B");
%       f.FSU   % -> 1.4

arguments
    name     (1,1) string
    userFile (1,1) string = userFactorPresetsPath()
end

built = data.factorPresets();
key = char(name);
if isKey(built, key)
    f = built(key);
    return
end

user = loadUserFactorPresets(userFile);
if isKey(user, key)
    f = user(key);
    return
end

avail = unique([string(keys(built)), string(keys(user))], "stable");
error("data:factorPreset:unknown", ...
    "Unknown factor preset ""%s"". Available: %s", name, strjoin(avail, ", "));
end
