function m = loadUserFactorPresets(file)
%LOADUSERFACTORPRESETS  containers.Map name -> model.Factors read from a
%   user factor-presets JSON file (Phase 3.7). Missing file -> empty map
%   (no user presets saved yet); this is the normal, expected case.
%
%   On-disk shape: {"schemaVersion":1,"presets":[{"name":...,"factors":
%   {...}}, ...]} — a NAME + FACTORS array rather than an object keyed by
%   name, so preset names are free-form strings (e.g. containing "." or
%   "-") without running into MATLAB struct-field-name restrictions.
arguments
    file (1,1) string
end

m = containers.Map();
if ~isfile(file)
    return
end

raw = jsondecode(fileread(file));
if ~isstruct(raw) || ~isfield(raw, "presets") || isempty(raw.presets)
    return
end

p = raw.presets;
n = numel(p);
for i = 1:n
    if iscell(p)
        e = p{i};
    else
        e = p(i);   % jsondecode of a homogeneous JSON array -> struct array
    end
    m(char(string(e.name))) = data.fromStruct(e.factors);
end
end
