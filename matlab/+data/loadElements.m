function el = loadElements(file, sheet)
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
%   el = data.loadElements(file, sheet) reads the given SHEET of a workbook
%   — a sheet name (e.g. "Elements") or a 1-based index. Omitted / [] / ""
%   keeps the default read (sheet 1 of an .xlsx, or the CSV). This is how
%   engine.runWorkbook pulls the Elements sheet out of the single
%   multi-sheet workbook.
%
%   HEADER-ROW AUTO-DETECT (same scheme as data.loadJointLibrary): the
%   reader scans the top of the sheet for the row whose cells best match
%   the known element column names (case-insensitive) and treats it as the
%   header; data starts on the next row. Rows ABOVE the header (e.g. the
%   template's friendly-name banner row) are ignored, so both a plain
%   single-header CSV and the decorated data.makeTemplate Elements sheet
%   parse as-is — no cleanup needed.
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
%       el = data.loadElements("elements.csv");
%       lc = engine.loadCaseFromForces(el(1).Forces, joint.BoltAxis, ...
%                Name = el(1).LoadCaseName, ...
%                ScaleFactor = el(1).ScaleFactor, ...
%                Reversible = el(1).Reversible);

arguments
    file (1,1) string
    sheet = []   % optional: sheet name or index (workbooks only)
end

if ~isfile(file)
    error("data:loadElements:fileNotFound", ...
        "Elements file not found: %s", file);
end

raw = readCellGrid(file, sheet);
[hdrRow, names] = detectHeaderRow(raw, knownColumns(), ...
    "data:loadElements:noHeader", sprintf( ...
    "No header row found in %s — no row matches the element-table column names (element_id, joint_name, FX, ...). See templates/elements_template.csv.", ...
    file));

el = struct("ElementId", {}, "JointName", {}, "LoadCaseName", {}, ...
            "PatternId", {}, "Forces", {}, "ScaleFactor", {}, ...
            "Reversible", {});
for r = hdrRow+1:size(raw, 1)
    id    = getText(raw, names, r, "element_id", "");
    joint = getText(raw, names, r, "joint_name", "");
    if strlength(id) == 0 || strlength(joint) == 0
        continue   % not an element row
    end
    F = struct("FX", getNum(raw, names, r, "FX", 0), ...
               "FY", getNum(raw, names, r, "FY", 0), ...
               "FZ", getNum(raw, names, r, "FZ", 0), ...
               "MX", getNum(raw, names, r, "MX", 0), ...
               "MY", getNum(raw, names, r, "MY", 0), ...
               "MZ", getNum(raw, names, r, "MZ", 0));
    el(end+1) = struct( ...
        "ElementId",    id, ...
        "JointName",    joint, ...
        "LoadCaseName", getText(raw, names, r, "load_case", ""), ...
        "PatternId",    getText(raw, names, r, "pattern_id", ""), ...
        "Forces",       F, ...
        "ScaleFactor",  getNum(raw, names, r, "scale", 1), ...
        "Reversible",   getLogical(raw, names, r, "reversible", false)); %#ok<AGROW>
end
end

% =========================================================================
% Header-row auto-detect (the scan itself lives in private/detectHeaderRow)
% =========================================================================

function cols = knownColumns()
%KNOWNCOLUMNS  Every recognized column name (the header-detection set).
cols = ["element_id", "joint_name", "pattern_id", "load_case", ...
        "FX", "FY", "FZ", "MX", "MY", "MZ", "scale", "reversible"];
end

% =========================================================================
% Cell-grid access primitives (case-insensitive columns, blanks -> default)
% =========================================================================

function v = getval(raw, names, r, name, default)
%GETVAL  Raw cell value; `default` when the column is absent or the cell blank.
idx = find(strcmpi(names, name), 1);
if isempty(idx)
    v = default;
    return
end
v = raw{r, idx};
if isa(v, "missing")
    v = default;
    return
end
if ischar(v), v = string(v); end
if isstring(v) && (ismissing(v) || strlength(strtrim(v)) == 0)
    v = default;
elseif isnumeric(v) && isscalar(v) && isnan(v)
    v = default;
end
end

function s = getText(raw, names, r, name, default)
%GETTEXT  Trimmed string value ("" family -> default; numbers stringified).
v = getval(raw, names, r, name, string(default));
s = strtrim(string(v));
if ismissing(s)
    s = string(default);
end
end

function x = getNum(raw, names, r, name, default)
%GETNUM  Numeric value; text cells are str2double'd (bad text errors).
v = getval(raw, names, r, name, default);
if isstring(v)
    x = str2double(v);
    if isnan(x)
        error("data:loadElements:badNumber", ...
            "Column ""%s"": cannot parse ""%s"" as a number.", name, v);
    end
elseif islogical(v)
    x = double(v);
else
    x = double(v);
end
end

function tf = getLogical(raw, names, r, name, default)
%GETLOGICAL  Logical from logical/numeric/text (TRUE/FALSE, yes/no, 1/0).
v = getval(raw, names, r, name, default);
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
