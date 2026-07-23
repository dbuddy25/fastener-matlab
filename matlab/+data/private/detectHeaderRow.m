function [hdrRow, names] = detectHeaderRow(raw, known, errId, errText)
%DETECTHEADERROW  Find the row whose cells best match a known column-name set.
%   [hdrRow, names] = detectHeaderRow(raw, known, errId, errText) scans the
%   top of a readcell grid (up to 25 rows), scores each row by how many of
%   its cells are (case-insensitive) members of `known`, and returns the
%   winning row index plus that row's cell texts as the column-name array
%   (one entry per grid column; non-text cells -> ""). Data rows start at
%   hdrRow + 1.
%
%   This makes a reader tolerant of decoration rows (titles, friendly-name
%   banners) above the real header — a plain single-header CSV simply
%   scores row 1 best. If no row matches at least 3 known names, the reader
%   errors with error(errId, errText).
%
%   Shared by data.loadJointLibrary and data.loadElements (each passes its
%   own known-column set) so the header tolerance cannot drift between the
%   two table readers.
nScan = min(size(raw, 1), 25);   % the header must live near the top
best = 0;
hdrRow = 0;
for r = 1:nScan
    score = 0;
    for c = 1:size(raw, 2)
        t = cellText(raw{r, c});
        if strlength(t) > 0 && any(strcmpi(known, t))
            score = score + 1;
        end
    end
    if score > best
        best = score;
        hdrRow = r;
    end
end
if best < 3
    error(errId, "%s", errText);
end
names = strings(1, size(raw, 2));
for c = 1:size(raw, 2)
    names(c) = cellText(raw{hdrRow, c});
end
end

function t = cellText(v)
%CELLTEXT  Trimmed string of a readcell cell; "" for non-text/missing.
if ischar(v) || isstring(v)
    t = strtrim(string(v));
    if ismissing(t)
        t = "";
    end
else
    t = "";
end
end
