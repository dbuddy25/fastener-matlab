function p = userFactorPresetsPath()
%USERFACTORPRESETSPATH  Default location for the user factor-presets file
%   (Phase 3.7). fullfile(userpath, "fastener_factor_presets.json"); if
%   userpath() is empty (not yet initialized on this MATLAB install), falls
%   back to a repo-local file next to +data/ so the tool still works.
up = userpath();
if isempty(up) || strlength(string(up)) == 0
    dataDir = fileparts(fileparts(mfilename("fullpath")));   % .../+data
    p = string(fullfile(dataDir, "user_factor_presets.json"));
else
    p = string(fullfile(char(up), "fastener_factor_presets.json"));
end
end
