function el = loadElements(file)
%LOADELEMENTS  Read an element + forces table (FEM mapping) (Phase 3.5b).
%   el = data.loadElements(file) reads a table (.csv or .xlsx) of FEM
%   element forces — one row per (element, load case) — and returns a
%   struct array with fields:
%       ElementId    (1,1) string  — element identifier (numeric ids are
%                                    stringified, e.g. 1001 -> "1001")
%       JointName    (1,1) string  — key into the joint library
%                                    (data.loadJointLibrary row Name)
%       LoadCaseName (1,1) string  — load case label (default "")
%       PatternId    (1,1) string  — bolt-pattern (physical joint instance)
%                                    identifier for joint-slip aggregation
%                                    (default "" -> engine.analyzeBulk falls
%                                    back to JointName, i.e. one joint name
%                                    = one physical pattern)
%       Forces       struct        — FX, FY, FZ (lbf), MX, MY, MZ (in-lbf);
%                                    missing columns/blanks -> 0. Feed to
%                                    engine.resolveForces / loadCaseFromForces.
%       ScaleFactor  (1,1) double  — applied before resolution (default 1)
%       Reversible   (1,1) logical — load can act in both directions
%                                    (default false)
%
%   Column schema (case-insensitive; template with exact headers at
%   templates/elements_template.csv):
%       element_id, joint_name, pattern_id (optional), load_case (optional),
%       FX, FY, FZ, MX (opt), MY (opt), MZ (opt), scale (opt),
%       reversible (opt)
%
%   Rows with a blank element_id or joint_name are skipped. Extra columns
%   are ignored.
%
%   Example:
%       el = data.loadElements("my_elements.csv");
%       lc = engine.loadCaseFromForces(el(1).Forces, joint.BoltAxis, ...
%                Name = el(1).LoadCaseName, ...
%                ScaleFactor = el(1).ScaleFactor, ...
%                Reversible = el(1).Reversible);

arguments
    file (1,1) string
end

if ~isfile(file)
    error("data:loadElements:fileNotFound", ...
        "Elements file not found: %s", file);
end

T = readtable(file, "TextType", "string");
names = string(T.Properties.VariableNames);

el = struct("ElementId", {}, "JointName", {}, "LoadCaseName", {}, ...
            "PatternId", {}, "Forces", {}, "ScaleFactor", {}, ...
            "Reversible", {});
for r = 1:height(T)
    id    = getText(T, names, r, "element_id", "");
    joint = getText(T, names, r, "joint_name", "");
    if strlength(id) == 0 || strlength(joint) == 0
        continue   % not an element row
    end
    F = struct("FX", getNum(T, names, r, "FX", 0), ...
               "FY", getNum(T, names, r, "FY", 0), ...
               "FZ", getNum(T, names, r, "FZ", 0), ...
               "MX", getNum(T, names, r, "MX", 0), ...
               "MY", getNum(T, names, r, "MY", 0), ...
               "MZ", getNum(T, names, r, "MZ", 0));
    el(end+1) = struct( ...
        "ElementId",    id, ...
        "JointName",    joint, ...
        "LoadCaseName", getText(T, names, r, "load_case", ""), ...
        "PatternId",    getText(T, names, r, "pattern_id", ""), ...
        "Forces",       F, ...
        "ScaleFactor",  getNum(T, names, r, "scale", 1), ...
        "Reversible",   getLogical(T, names, r, "reversible", false)); %#ok<AGROW>
end
end

% =========================================================================
% Table access primitives (case-insensitive columns, blanks -> default)
% =========================================================================

function v = getval(T, names, r, name, default)
%GETVAL  Raw cell value; `default` when the column is absent or the cell blank.
idx = find(strcmpi(names, name), 1);
if isempty(idx)
    v = default;
    return
end
v = T{r, idx};
if iscell(v), v = v{1}; end
if ischar(v), v = string(v); end
if isstring(v) && (ismissing(v) || strlength(strtrim(v)) == 0)
    v = default;
elseif isnumeric(v) && isscalar(v) && isnan(v)
    v = default;
end
end

function s = getText(T, names, r, name, default)
%GETTEXT  Trimmed string value ("" family -> default; numbers stringified).
v = getval(T, names, r, name, string(default));
s = strtrim(string(v));
if ismissing(s)
    s = string(default);
end
end

function x = getNum(T, names, r, name, default)
%GETNUM  Numeric value; text cells are str2double'd (bad text errors).
v = getval(T, names, r, name, default);
if isstring(v)
    x = str2double(v);
    if isnan(x)
        error("data:loadElements:badNumber", ...
            "Column ""%s"": cannot parse ""%s"" as a number.", name, v);
    end
else
    x = double(v);
end
end

function tf = getLogical(T, names, r, name, default)
%GETLOGICAL  Logical from logical/numeric/text (TRUE/FALSE, yes/no, 1/0).
v = getval(T, names, r, name, default);
if islogical(v)
    tf = v;
elseif isnumeric(v)
    if isnan(v)
        tf = logical(default);
    else
        tf = v ~= 0;
    end
elseif isstring(v)
    s = lower(strtrim(v));
    if any(s == ["true", "t", "yes", "y", "1"])
        tf = true;
    elseif any(s == ["false", "f", "no", "n", "0"])
        tf = false;
    else
        error("data:loadElements:badLogical", ...
            "Column ""%s"": cannot parse ""%s"" as a logical (use TRUE/FALSE).", name, v);
    end
else
    tf = logical(default);
end
end
