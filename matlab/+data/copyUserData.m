function [copied, kept] = copyUserData(from, to)
%COPYUSERDATA  Copy the tool's user data to a new folder, overwriting nothing.
%   [copied, kept] = data.copyUserData(from, to) copies
%   fastener_library.json, fastener_factor_presets.json and every file
%   under fastener_library\ from one data folder to another. A file that
%   already exists in the target is KEPT as it is and listed in kept:
%   the target may be a synced folder another machine has already filled,
%   and its entries must never be replaced. Nothing is deleted from either
%   folder. Returns relative paths.
arguments
    from (1,1) string
    to   (1,1) string
end
copied = strings(1, 0);
kept = strings(1, 0);
rel = ["fastener_library.json", "fastener_factor_presets.json"];
drop = fullfile(from, "fastener_library");
if isfolder(drop)
    for d = dir(fullfile(drop, "**", "*"))'
        if ~d.isdir
            r = extractAfter(string(fullfile(d.folder, d.name)), strlength(string(from)) + 1);
            rel(end + 1) = r; %#ok<AGROW>
        end
    end
end
if ~isfolder(to)
    mkdir(to);
end
for r = rel
    src = fullfile(from, r);
    if ~isfile(src)
        continue
    end
    dst = fullfile(to, r);
    if isfile(dst)
        kept(end + 1) = r; %#ok<AGROW>
        continue
    end
    folder = fileparts(dst);
    if ~isfolder(folder)
        mkdir(folder);
    end
    copyfile(src, dst);
    copied(end + 1) = r; %#ok<AGROW>
end
end
