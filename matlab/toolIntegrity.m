function [state, changed, text] = toolIntegrity(opts)
%TOOLINTEGRITY  Is the calculation code the code that was released?
%   [state, changed, text] = toolIntegrity() compares every code file in
%   +engine, +model, +data and the top folder with the fingerprint
%   packageToolbox recorded in integrity.json when it built the release.
%     state    "release"   every file matches
%              "modified"  changed lists the files edited, added or removed
%              "source"    no fingerprint: running from a checkout, where
%                          editing the code is the point
%     text     one line for Help > About and every export's About sheet;
%              "" when running from source, where there is nothing to say
%   toolIntegrity(Write=true) records the fingerprint; packageToolbox is
%   the only caller.
%
%   WHY. The engine files ship as readable .m source, so anyone can edit
%   an equation in the Add-Ons folder and every margin after that uses it,
%   with nothing on record. This does not stop an edit; it makes one
%   visible on screen and on every export.
%
%   The checksum (size plus an Adler-32 style sum) detects edits, not a
%   deliberate forgery.
arguments
    opts.Write (1,1) logical = false
    opts.Root  (1,1) string  = string(fileparts(mfilename("fullpath")))
end
root = opts.Root;
mf = fullfile(root, "integrity.json");
files = codeFiles(root);
rel = extractAfter(files, strlength(root) + 1);
rel = replace(rel, "\", "/");
sums = arrayfun(@checksum, files);
changed = strings(1, 0);

if opts.Write
    fid = fopen(mf, 'w');
    fprintf(fid, '%s', jsonencode(struct('version', toolVersion(), ...
        'files', struct('path', cellstr(rel), 'sum', cellstr(sums))), PrettyPrint=true));
    fclose(fid);
    state = "release";
    text = "Matches release v" + toolVersion();
    return
end

if ~isfile(mf)
    state = "source";
    text = "";
    return
end

m = jsondecode(fileread(mf));
want = string({m.files.path});
wantSum = string({m.files.sum});
for k = 1:numel(want)
    i = find(rel == want(k), 1);
    if isempty(i) || sums(i) ~= wantSum(k)
        changed(end + 1) = want(k); %#ok<AGROW>
    end
end
changed = [changed, rel(~ismember(rel, want))'];
if isempty(changed)
    state = "release";
    text = "Matches release v" + string(m.version);
else
    state = "modified";
    text = "MODIFIED FROM RELEASED VERSION";
end
end

function f = codeFiles(root)
d = [dir(fullfile(root, "*.m")); ...
     dir(fullfile(root, "+engine", "**", "*.m")); ...
     dir(fullfile(root, "+model", "**", "*.m")); ...
     dir(fullfile(root, "+data", "**", "*.m"))];
f = string({d.folder})' + filesep + string({d.name})';
f = f(~endsWith(f, filesep + "runTests.m"));
f = sort(f);
end

function c = checksum(file)
fid = fopen(file, 'r');
b = double(fread(fid, inf, '*uint8'));
fclose(fid);
n = numel(b);
a = mod(1 + sum(b), 65521);
w = mod(n + sum((n:-1:1)' .* b), 65521);
c = string(sprintf('%d-%d-%d', n, a, w));
end
