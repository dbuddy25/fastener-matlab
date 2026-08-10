function file = exportResults(T, file, opts)
%EXPORTRESULTS  Write a bulk results table to .xlsx or .csv (Phase 3.6).
%   file = report.exportResults(T, file) writes the engine.analyzeBulk
%   results table T to the given file — .xlsx or .csv, chosen by the file
%   extension (no extension defaults to .xlsx) — and returns the resolved
%   absolute path. The table is already export-ready (writetable-friendly
%   columns straight from analyzeBulk), so this is a thin, stable public
%   entry point:
%
%       T = engine.analyzeBulk(jl, el, factors);
%       report.exportResults(T, "margins.xlsx");
%
%   For .xlsx the workbook gets THREE sheets:
%       Results  — the full results table (one row per element)
%       Summary  — counts: total elements, Pass (WorstMargin >= 0, no
%                  Error), Fail (WorstMargin < 0), Error (nonempty Error
%                  column). Skipped when T lacks WorstMargin/Error columns.
%       About    — tool name, version (toolVersion), run timestamp and the
%                  governing standard, so an exported workbook stays
%                  traceable to the build that produced it. Any strings
%                  passed as Notes are appended here — a scope statement
%                  naming checks that were computed and NOT exported
%                  belongs with the file, not just on the screen it came
%                  from.
%   For .csv only the main table is written (CSV has no sheets, and a
%   metadata banner row would corrupt readtable), so a CSV export carries
%   NO version stamp -- use .xlsx when the version has to travel with it.
%
%   An existing file at the target path is deleted first, so the output is
%   always a clean workbook (no stale sheets/cells from a previous run).
%   An empty (zero-row) table still writes its header row.

arguments
    T    table
    file (1,1) string
    opts.Notes (1,:) string = string.empty(1, 0)
end

[~, ~, ext] = fileparts(file);
if strlength(ext) == 0
    file = file + ".xlsx";
    ext  = ".xlsx";
end

switch lower(ext)
    case ".xlsx"
        isXlsx = true;
    case ".csv"
        isXlsx = false;
    otherwise
        error("report:exportResults:badExtension", ...
            "Unsupported export extension ""%s"" (use .xlsx or .csv).", ext);
end

% Clean slate: never merge into a stale workbook from an earlier run
if isfile(file)
    delete(file);
end

if isXlsx
    writetable(T, file, "Sheet", "Results");

    % Summary sheet (counts) — only when the analyzeBulk columns exist
    vars = string(T.Properties.VariableNames);
    if all(ismember(["WorstMargin", "Error"], vars))
        isErr  = strlength(T.Error) > 0;
        isPass = ~isErr & T.WorstMargin >= 0;
        isFail = ~isErr & T.WorstMargin < 0;
        Metric = ["Total elements"; "Pass (WorstMargin >= 0)"; ...
                  "Fail (WorstMargin < 0)"; "Error"];
        Count  = [height(T); nnz(isPass); nnz(isFail); nnz(isErr)];
        writetable(table(Metric, Count), file, "Sheet", "Summary");
    end

    % About sheet — the tool version and the run time, so a workbook that
    % has been emailed on is still traceable to the build that produced
    % it. A SEPARATE SHEET, not extra columns or a banner row on Results:
    % that sheet is read by writetable/readtable and by whatever the
    % analyst pivots it with, and a metadata row would corrupt every one
    % of them.
    Item  = ["Tool"; "Version"; "Generated"; "Standard"];
    Value = ["Fastener Analysis Tool"; toolVersion(); ...
             string(datetime("now", "Format", "yyyy-MM-dd HH:mm")); ...
             "NASA-STD-5020B"];
    % Caller notes ride on the SAME sheet as the version stamp, because they
    % are the same kind of claim: a scope statement naming checks that are
    % computed and not exported has to travel with the file, or the
    % spreadsheet reads as a complete assessment when it is not.
    for k = 1:numel(opts.Notes)
        Item(end+1)  = "Note"; %#ok<AGROW>
        Value(end+1) = opts.Notes(k); %#ok<AGROW>
    end
    writetable(table(Item, Value), file, "Sheet", "About");
else
    % CSV HAS NO SHEETS, so there is nowhere to put the stamp that would
    % not corrupt the data. Left unstamped deliberately rather than
    % prepending comment lines that readtable would then have to be told
    % to skip -- use .xlsx when the stamp has to travel with the numbers.
    writetable(T, file);
end

% Resolve to the absolute path actually written
d    = dir(file);
file = string(fullfile(d(1).folder, d(1).name));
end
