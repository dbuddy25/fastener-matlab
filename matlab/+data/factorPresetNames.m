function [names, builtIn] = factorPresetNames(userFile)
%FACTORPRESETNAMES  Every factor-preset name, built-in and user-saved.
%   names = data.factorPresetNames() returns a string row vector of every
%   preset name data.factorPreset can resolve: the built-in names first
%   (data.factorPresets), then the names in the user presets file (default
%   path as in data.saveFactorPreset). The two sets are disjoint — a user
%   preset can never shadow a built-in, because data.saveFactorPreset
%   refuses to write one.
%
%   [names, builtIn] = data.factorPresetNames() also returns a logical row
%   vector, true where the corresponding name is built in. Callers that
%   treat the two differently — a picker that groups them, or a control
%   that protects built-ins from overwrite — read this rather than
%   re-deriving membership from data.factorPresets.
%
%   ... = data.factorPresetNames(userFile) reads user presets from a
%   specific file instead of the default user-area path, mirroring
%   data.factorPreset's second argument (used by tests so they never touch
%   the real userpath).
%
%   WHY THIS EXISTS: the user-preset store is otherwise undiscoverable from
%   outside +data. loadUserFactorPresets and userFactorPresetsPath are
%   private, so a caller could look a user preset up BY NAME but had no way
%   to learn the name existed — a GUI could save a preset and then not be
%   able to list it. This is the read-only enumerator that closes that gap;
%   it computes nothing and owns no state.
%
%   Example:
%       [names, builtIn] = data.factorPresetNames();
%       f = data.factorPreset(names(1));

arguments
    userFile (1,1) string = userFactorPresetsPath()
end

% reshape to a guaranteed row: keys() returns 1x0 for an empty store, and
% concatenating a 0x0 would silently drop the shape.
built = reshape(string(keys(data.factorPresets())), 1, []);
user  = reshape(string(keys(loadUserFactorPresets(userFile))), 1, []);

names   = [built, user];
builtIn = [true(1, numel(built)), false(1, numel(user))];
end
