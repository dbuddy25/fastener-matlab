function p = userGuidePath(name)
%USERGUIDEPATH  A file in the bundled HTML user guide.
%   p = gui.userGuidePath() returns the guide's index.html.
%   p = gui.userGuidePath(name) returns userguide/<name>, e.g. "Results.html".
%
%   Resolved from this file's location, the same way data.Library finds
%   +data/library, so it follows the app into the mcc bundle (-a userguide).
arguments
    name (1,1) string = "index.html"
end
p = string(fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "userguide", name));
end
