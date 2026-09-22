function tf = samePath(a, b)
%SAMEPATH  Case-insensitive same-file check; folder-resolves when both exist.
%   tf = samePath(a, b) is TRUE when a and b refer to the same file on
%   disk. When both paths exist, each resolves to its dir() absolute
%   folder+name and the two are compared case-insensitively (so a relative
%   path and its absolute equivalent — or a case difference on a
%   case-insensitive filesystem — are recognized as the same file);
%   otherwise falls back to a plain case-insensitive string compare of the
%   two paths as given.
%
%   SHARED by engine.runWorkbook's and engine.runBulk's outFile-vs-input
%   guards — the one place this comparison lives, so the two entry points
%   cannot drift.
if isfile(a) && isfile(b)
    da = dir(a);
    db = dir(b);
    tf = strcmpi(fullfile(da.folder, da.name), fullfile(db.folder, db.name));
else
    tf = strcmpi(a, b);
end
end
