function status = exportBulkWorkbook(file, sheets, progressFcn)
%EXPORTBULKWORKBOOK  Write the bulk-results .xlsx (values first, then COM styling).
%   status = gui.exportBulkWorkbook(file, sheets) writes one worksheet per
%   entry of the sheets struct array and then ATTEMPTS conditional
%   formatting via Excel COM automation. The two phases are strictly
%   ordered so a formatting failure can never lose the export:
%
%     1. VALUES (always) — writecell per sheet. If this phase throws, the
%        caller gets the error and no success is claimed.
%     2. FORMATTING (best effort) — Excel COM (actxserver) on Windows only:
%        header fill, pass/fail/na cell fills, bold label rows, alternating
%        row banding on non-margin columns, thin borders, freeze panes,
%        clamped auto-fit column widths. ANY failure here is caught and
%        reported in status — the values-only workbook from phase 1 is
%        already complete on disk.
%
%   This is a FORMATTING layer only: every value and every pass/fail/na
%   cell classification arrives precomputed in the sheets spec — nothing is
%   recomputed or re-thresholded here (no analysis logic in the GUI layer).
%
%   sheets — struct array, one element per worksheet, fields:
%     Name         (1,1) string   worksheet name
%     Cells        cell (R x C)   the full sheet grid (chars/doubles)
%     HeaderRows   Nx2 double     [row lastCol] rows styled as headers
%     LabelRows    1xN double     rows styled bold (titles, block labels)
%     PassCells    Nx2 double     [row col] cells filled pass green
%     FailCells    Nx2 double     [row col] cells filled fail red
%     NaCells      Nx2 double     [row col] cells filled n/a grey
%     DataBlocks   Nx2 double     [firstRow lastRow] data spans (banding)
%     BorderBlocks Nx3 double     [firstRow lastRow lastCol] bordered spans
%     MarginCols   [] | [c1 c2]   margin-column span EXCLUDED from banding
%     NCols        (1,1) double   table width in columns
%     Freeze       (1,1) string   freeze-panes anchor, e.g. "A3" ("" = none)
%
%   status fields:
%     File      (1,1) string   absolute path actually written
%     Formatted (1,1) logical  true only if COM formatting fully succeeded
%     Detail    (1,1) string   "" when formatted; otherwise why not
%
%   NOTE ON COLORS: the hex constants below are Excel FILE-FORMAT values
%   from GUI_PORT_SPEC.md (header #1F3864, pass #C6EFCE, fail #FFC7CE, n/a
%   #D9D9D9, band #F2F2F2, border #B0B0B0) — they are not UI colors and
%   deliberately do NOT go through gui.palette.

arguments
    file        (1,1) string
    sheets      (1,:) struct
    progressFcn (1,1) function_handle = @(msg) []
end

% ---- Phase 1: values (must succeed — errors propagate to the caller) ----
reportProgress(progressFcn, 'Writing workbook values...');

[~, ~, ext] = fileparts(file);
if strlength(ext) == 0
    file = file + ".xlsx";
end
if isfile(file)
    % Clean slate: never merge into a stale workbook from an earlier run.
    delete(file);
end
for i = 1:numel(sheets)
    C = sheets(i).Cells;
    if isempty(C)
        C = {''};
    end
    writecell(C, file, 'Sheet', char(sheets(i).Name));
end

% Resolve the absolute path actually written (COM Open needs it, and the
% completion message should show it).
d    = dir(file);
file = string(fullfile(d(1).folder, d(1).name));

% ---- Phase 2: formatting (best effort — never allowed to lose phase 1) --
reportProgress(progressFcn, 'Applying Excel formatting...');
[ok, why] = tryFormatWorkbook(file, sheets);

status = struct('File', file, 'Formatted', ok, 'Detail', why);
end

% =========================================================================
function reportProgress(progressFcn, msg)
%REPORTPROGRESS  Progress callback wrapper — cosmetic reporting must never be able
%   to abort the export (e.g. a dialog closed underneath the callback).
try
    progressFcn(msg);
catch
end
end

function [ok, why] = tryFormatWorkbook(file, sheets)
%TRYFORMATWORKBOOK  Excel COM styling pass. Returns ok=false + reason on
%   ANY failure; the values-only workbook on disk is left intact (the
%   workbook is closed without save on error, so a partial style pass is
%   discarded rather than half-saved).
ok  = false;
why = "";

if ~ispc
    why = "Excel formatting is Windows-only; this platform gets values only";
    return
end

try
    xl = actxserver('Excel.Application');
catch err
    why = "Excel is not available for formatting (" + ...
        string(err.message) + ")";
    return
end
% Release Excel on EVERY exit path — an abandoned EXCEL.EXE keeps the
% file locked and leaks a process.
cleanupXl = onCleanup(@() quitExcel(xl)); %#ok<NASGU>

wbOpen = false;
try
    xl.Visible       = false;
    xl.DisplayAlerts = false;
    try
        xl.ScreenUpdating = false;   % speed only — cosmetic if it fails
    catch
    end
    wb = xl.Workbooks.Open(char(file));
    wbOpen = true;

    k = styleConstants();
    for i = 1:numel(sheets)
        ws = wb.Sheets.Item(char(sheets(i).Name));
        formatSheet(xl, ws, sheets(i), k);
    end

    wb.Save;
    wb.Close(false);
    wbOpen = false;
    ok = true;
catch err
    if wbOpen
        try
            wb.Close(false);   % discard partial styling; keep phase-1 file
        catch
        end
    end
    why = "Excel formatting failed (" + string(err.message) + ...
        "); the workbook was written values-only";
end
end

function quitExcel(xl)
%QUITEXCEL  Best-effort COM teardown (onCleanup target).
try
    xl.Quit;
catch
end
try
    delete(xl);
catch
end
end

function formatSheet(xl, ws, s, k)
%FORMATSHEET  Apply the full style pass to one worksheet.
%   Order matters only in that banding paints non-margin columns and the
%   pass/fail/na fills paint margin columns — disjoint by construction.
lastL = colLetter(max(s.NCols, 1));

% ---- Alternating row banding (non-margin columns only) ------------------
spans = bandSpans(s.MarginCols, s.NCols);
for b = 1:size(s.DataBlocks, 1)
    r0 = s.DataBlocks(b, 1);
    r1 = s.DataBlocks(b, 2);
    for r = r0 + 1:2:r1                 % 2nd, 4th, ... row of each block
        for sp = 1:size(spans, 1)
            rng = ws.Range(sprintf('%s%d:%s%d', ...
                colLetter(spans(sp, 1)), r, colLetter(spans(sp, 2)), r));
            rng.Interior.Color = k.band;
        end
    end
end

% ---- Pass / fail / n-a cell fills (precomputed classifications) ---------
paintCells(ws, s.PassCells, k.pass);
paintCells(ws, s.FailCells, k.fail);
paintCells(ws, s.NaCells,   k.na);

% ---- Thin borders around each table span --------------------------------
for b = 1:size(s.BorderBlocks, 1)
    try
        rng = ws.Range(sprintf('A%d:%s%d', s.BorderBlocks(b, 1), ...
            colLetter(s.BorderBlocks(b, 3)), s.BorderBlocks(b, 2)));
        bd = rng.Borders;
        bd.LineStyle = 1;               % xlContinuous
        bd.Weight    = 2;               % xlThin
        bd.Color     = k.border;
    catch
        % Borders are decoration — never worth failing the pass over.
    end
end

% ---- Bold label rows (titles, section/block labels) ---------------------
for r = s.LabelRows(:)'
    rng = ws.Range(sprintf('A%d:%s%d', r, lastL, r));
    rng.Font.Bold = true;
end

% ---- Header rows: spec fill, white bold 10pt centred --------------------
for h = 1:size(s.HeaderRows, 1)
    r   = s.HeaderRows(h, 1);
    rng = ws.Range(sprintf('A%d:%s%d', r, ...
        colLetter(s.HeaderRows(h, 2)), r));
    rng.Interior.Color = k.headerFill;
    f = rng.Font;
    f.Color = k.white;
    f.Bold  = true;
    f.Size  = 10;
    rng.HorizontalAlignment = -4108;    % xlCenter
end

% ---- Column widths: auto-fit clamped to [8, 40] -------------------------
try
    ws.UsedRange.EntireColumn.AutoFit;
    for c = 1:s.NCols
        col = ws.Columns.Item(c);
        w   = col.ColumnWidth;
        if isnumeric(w) && isscalar(w)
            if w < k.widthMin
                col.ColumnWidth = k.widthMin;
            elseif w > k.widthMax
                col.ColumnWidth = k.widthMax;
            end
        end
    end
catch
    % Width polish only — defaults are still readable.
end

% ---- Freeze panes -------------------------------------------------------
if strlength(s.Freeze) > 0
    try
        ws.Activate;
        xl.ActiveWindow.FreezePanes = false;
        ws.Range(char(s.Freeze)).Select;
        xl.ActiveWindow.FreezePanes = true;
    catch
        % Freeze is a convenience — skip silently if the window objects.
    end
end
end

function paintCells(ws, cells, color)
%PAINTCELLS  Fill the given [row col] cells, batched into per-column
%   vertical runs (one COM Range call per contiguous run — hundreds of
%   times fewer calls than per-cell on a large all-pass sheet).
if isempty(cells)
    return
end
cells = sortrows(cells, [2 1]);
n  = size(cells, 1);
i0 = 1;
for i = 1:n
    isLast = (i == n);
    if ~isLast && cells(i + 1, 2) == cells(i, 2) && ...
            cells(i + 1, 1) == cells(i, 1) + 1
        continue                        % run extends downward
    end
    L   = colLetter(cells(i0, 2));
    rng = ws.Range(sprintf('%s%d:%s%d', L, cells(i0, 1), L, cells(i, 1)));
    rng.Interior.Color = color;
    i0 = i + 1;
end
end

function spans = bandSpans(marginCols, nCols)
%BANDSPANS  Column spans eligible for banding: everything OUTSIDE the
%   margin-column block (spec: alternating fill on non-margin columns only).
if isempty(marginCols)
    spans = [1, nCols];
    return
end
spans = zeros(0, 2);
if marginCols(1) > 1
    spans(end + 1, :) = [1, marginCols(1) - 1];
end
if marginCols(2) < nCols
    spans(end + 1, :) = [marginCols(2) + 1, nCols];
end
end

function k = styleConstants()
%STYLECONSTANTS  The spec's Excel formatting constants, as BGR-packed
%   doubles (Excel Interior.Color = R + 256*G + 65536*B).
k.headerFill = excelColor('1F3864');    % header fill, dark navy
k.white      = excelColor('FFFFFF');    % header font
k.pass       = excelColor('C6EFCE');    % MS >= 0
k.fail       = excelColor('FFC7CE');    % MS < 0
k.na         = excelColor('D9D9D9');    % not evaluated / ERR
k.band       = excelColor('F2F2F2');    % alternating rows, non-margin cols
k.border     = excelColor('B0B0B0');    % thin borders
k.widthMin   = 8;                       % column-width clamp
k.widthMax   = 40;
end

function c = excelColor(hex)
%EXCELCOLOR  '#RRGGBB' hex -> Excel BGR-packed color double.
r = hex2dec(hex(1:2));
g = hex2dec(hex(3:4));
b = hex2dec(hex(5:6));
c = r + 256 * g + 65536 * b;
end

function s = colLetter(n)
%COLLETTER  1-based column index -> Excel column letters (1->A, 27->AA).
s = '';
while n > 0
    r = mod(n - 1, 26);
    s = [char('A' + r), s]; %#ok<AGROW>
    n = floor((n - 1) / 26);
end
end
