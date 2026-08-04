function [el, info] = loadElementWorkbook(file)
%LOADELEMENTWORKBOOK  Read a multi-sheet element-forces workbook (GUI path).
%   el = data.loadElementWorkbook(file) reads EVERY sheet of an .xlsx
%   workbook of FEM element forces — ONE LOAD CASE PER SHEET, where the
%   SHEET NAME (trimmed) IS the load case name. That is the force-import
%   shape because it matches how a NASTRAN export naturally comes out (one
%   sheet per subcase). Each force sheet carries exactly the
%   seven columns (case-insensitive, whitespace-tolerant, header-row
%   auto-detected — the same machinery as data.loadElements):
%
%       element_id, FX, FY, FZ, MX, MY, MZ
%
%   and NOTHING about scale, reversibility, joints or patterns — those are
%   owned by the GUI (per-load-case Scale / Reversible in the Element
%   Forces tab; element -> joint via the Element Mapping tab).
%
%   The return is the SAME struct-array shape as data.loadElements, so
%   every downstream consumer works unchanged:
%       ElementId    (1,1) string  — element identifier (numeric ids are
%                                    stringified, e.g. 1001 -> "1001")
%       JointName    (1,1) string  — always "" (the Element Mapping tab is
%                                    the authority on element -> joint)
%       LoadCaseName (1,1) string  — the sheet name, trimmed
%       PatternId    (1,1) string  — always ""
%       Forces       struct        — FX, FY, FZ (lbf), MX, MY, MZ (in-lbf);
%                                    blank cells -> 0
%       ScaleFactor  (1,1) double  — always 1 (the GUI owns scale)
%       Reversible   (1,1) logical — always false (the GUI owns this too)
%
%   SHEET TRIAGE — a workbook may contain a notes or cover sheet:
%     - A sheet with no recognisable header, or missing any of the seven
%       required columns, is SKIPPED and reported via `info`, never fatal.
%     - A workbook where NO sheet parses errors
%       (data:loadElementWorkbook:noForceSheets) naming what was expected.
%     - Within a parsed sheet, rows with content but a blank element_id
%       are skipped and reported (fully blank padding rows are ignored
%       quietly) — the data.loadElements info convention.
%     - A bad cell VALUE in a recognised force sheet (e.g. text where a
%       number belongs) is a data error and throws
%       (data:loadElementWorkbook:badNumber) — it must not be silently
%       skipped.
%
%   [el, info] = data.loadElementWorkbook(...) also reports, per sheet:
%       info.Sheets — struct array, one entry per workbook sheet, fields:
%           Name            (1,1) string  — sheet name (trimmed)
%           Parsed          (1,1) logical — true when read as a force sheet
%           RowCount        (1,1) double  — element rows read (0 if skipped)
%           SkippedRowCount (1,1) double  — content rows with no element_id
%           SkippedRows     (1,:) double  — their grid row numbers (row 1 =
%                                           first row of the sheet)
%           SkipReason      (1,1) string  — why the sheet was skipped
%                                           ("" when Parsed)
%       info.ParsedSheetCount  (1,1) double
%       info.SkippedSheetCount (1,1) double
%
%   Errors use data:loadElementWorkbook:* identifiers:
%       fileNotFound, badExtension, noForceSheets, badNumber
%
%   Example:
%       [el, inf] = data.loadElementWorkbook("subcase_forces.xlsx");
%       % el(k).LoadCaseName is the name of the sheet row k came from.

arguments
    file (1,1) string
end

if ~isfile(file)
    error("data:loadElementWorkbook:fileNotFound", ...
        "Force workbook not found: %s", file);
end
if ~endsWith(lower(file), [".xlsx", ".xlsm", ".xls"])
    error("data:loadElementWorkbook:badExtension", ...
        ["Force workbook must be a multi-sheet spreadsheet (.xlsx) — " + ...
         "one load case per sheet, the sheet name being the load case " + ...
         "name (got: %s)."], file);
end

el = emptyElements();
sheetInfo = struct("Name", {}, "Parsed", {}, "RowCount", {}, ...
    "SkippedRowCount", {}, "SkippedRows", {}, "SkipReason", {});

names = sheetnames(file);
for s = 1:numel(names)
    caseName = strtrim(string(names(s)));
    rec = struct("Name", caseName, "Parsed", false, "RowCount", 0, ...
        "SkippedRowCount", 0, "SkippedRows", zeros(1, 0), ...
        "SkipReason", "");

    % ---- Header triage: skip gracefully, never fatally ------------------
    % readCellGrid / detectHeaderRow are the shared +data/private helpers
    % (same auto-detect as data.loadElements): decoration rows above the
    % real header are tolerated; a sheet whose best row matches fewer than
    % 3 known names has no recognisable header.
    try
        raw = readCellGrid(file, names(s));
        [hdrRow, colNames] = detectHeaderRow(raw, requiredColumns(), ...
            "data:loadElementWorkbook:noHeader", "no recognisable header");
    catch
        rec.SkipReason = "no recognisable force-table header " + ...
            "(expected columns: " + strjoin(requiredColumns(), ", ") + ")";
        sheetInfo(end+1) = rec; %#ok<AGROW>
        continue
    end

    % All seven columns are REQUIRED on a force sheet — a header that
    % matches some but not all is not a force sheet; skip it and say what
    % is missing.
    missingCols = strings(1, 0);
    for c = requiredColumns()
        if ~any(strcmpi(colNames, c))
            missingCols(end+1) = c; %#ok<AGROW>
        end
    end
    if ~isempty(missingCols)
        rec.SkipReason = "missing required column(s): " + ...
            strjoin(missingCols, ", ");
        sheetInfo(end+1) = rec; %#ok<AGROW>
        continue
    end

    % ---- Rows (a bad cell VALUE from here on is fatal, not a skip) ------
    for r = hdrRow+1:size(raw, 1)
        id = getText(raw, colNames, r, "element_id", "");
        if strlength(id) == 0
            % Padding rows are ignored quietly; a row WITH content but no
            % element_id is reported so it cannot vanish silently (the
            % data.loadElements convention).
            if ~rowIsBlank(raw, r)
                rec.SkippedRows(end+1) = r; %#ok<AGROW>
            end
            continue
        end
        F = struct("FX", getNum(raw, colNames, r, "FX", 0), ...
                   "FY", getNum(raw, colNames, r, "FY", 0), ...
                   "FZ", getNum(raw, colNames, r, "FZ", 0), ...
                   "MX", getNum(raw, colNames, r, "MX", 0), ...
                   "MY", getNum(raw, colNames, r, "MY", 0), ...
                   "MZ", getNum(raw, colNames, r, "MZ", 0));
        el(end+1) = struct( ...
            "ElementId",    id, ...
            "JointName",    "", ...          % the Element Mapping tab maps
            "LoadCaseName", caseName, ...    % THE SHEET NAME
            "PatternId",    "", ...
            "Forces",       F, ...
            "ScaleFactor",  1, ...           % the GUI owns scale
            "Reversible",   false); %#ok<AGROW> % ...and reversibility
        rec.RowCount = rec.RowCount + 1;
    end
    rec.Parsed = true;
    rec.SkippedRowCount = numel(rec.SkippedRows);
    sheetInfo(end+1) = rec; %#ok<AGROW>
end

parsed = [sheetInfo.Parsed];
if ~any(parsed)
    detail = "";
    for i = 1:numel(sheetInfo)
        detail = detail + sprintf("\n  sheet ""%s"": %s", ...
            sheetInfo(i).Name, sheetInfo(i).SkipReason);
    end
    error("data:loadElementWorkbook:noForceSheets", ...
        ["No sheet of %s parses as a force table. Expected one load " + ...
         "case per sheet (the sheet name is the load case name), each " + ...
         "sheet with columns: %s.%s"], ...
        file, strjoin(requiredColumns(), ", "), detail);
end

info = struct("Sheets", sheetInfo, ...
              "ParsedSheetCount",  sum(parsed), ...
              "SkippedSheetCount", sum(~parsed));
end

% =========================================================================
% Schema
% =========================================================================

function cols = requiredColumns()
%REQUIREDCOLUMNS  The seven required force-sheet columns (also the
%   header-detection set): element_id, fx, fy, fz, mx, my, mz — matched
%   case-insensitively.
cols = ["element_id", "FX", "FY", "FZ", "MX", "MY", "MZ"];
end

function el = emptyElements()
%EMPTYELEMENTS  0x0 struct array in the data.loadElements field order.
el = struct("ElementId", {}, "JointName", {}, "LoadCaseName", {}, ...
            "PatternId", {}, "Forces", {}, "ScaleFactor", {}, ...
            "Reversible", {});
end

% =========================================================================
% Row triage + cell-grid access primitives
% -------------------------------------------------------------------------
% These mirror the file-local helpers in data.loadElements (which cannot be
% called from a sibling file). Duplicated deliberately rather than moving
% loadElements' locals into private/ — loadElements is a shipped, tested
% interface and stays untouched. Keep the two copies in step.
% =========================================================================

function tf = rowIsBlank(raw, r)
%ROWISBLANK  True when EVERY cell in row r is missing/blank (padding row).
tf = true;
for c = 1:size(raw, 2)
    v = raw{r, c};
    if isa(v, "missing")
        continue
    end
    if ischar(v), v = string(v); end
    if isstring(v)
        if isscalar(v) && (ismissing(v) || strlength(strtrim(v)) == 0)
            continue
        end
    elseif isnumeric(v) && isscalar(v) && isnan(v)
        continue
    end
    tf = false;
    return
end
end

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
        error("data:loadElementWorkbook:badNumber", ...
            "Column ""%s"": cannot parse ""%s"" as a number.", name, v);
    end
elseif islogical(v)
    x = double(v);
else
    x = double(v);
end
end
