function p = userFactorPresetsPath()
%USERFACTORPRESETSPATH  Default location for the user factor-presets file
%   (Phase 3.7). fullfile(userpath, "fastener_factor_presets.json"); if
%   userpath() is empty (not yet initialized on this MATLAB install, or
%   running from the packaged .exe), falls back to prefdir() -- per-user
%   and always writable.
up = userpath();
if isempty(up) || strlength(string(up)) == 0
    % PREFDIR, NOT THE INSTALL DIRECTORY -- see data.Library.userPath for
    % the full reasoning. Writing a user's presets beside the source is
    % wrong from a checkout and impossible from the packaged .exe, where
    % that folder lives under ctfroot.
    p = string(fullfile(prefdir(), "fastener_factor_presets.json"));
else
    p = string(fullfile(char(up), "fastener_factor_presets.json"));
end
end
