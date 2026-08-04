function file = exportResults(T, file)
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
%   For .xlsx the workbook gets TWO sheets:
%       Results  — the full results table (one row per element)
%       Summary  — counts: total elements, Pass (WorstMargin >= 0, no
%                  Error), Fail (WorstMargin < 0), Error (nonempty Error
%                  column). Skipped when T lacks WorstMargin/Error columns.
%   For .csv only the main table is written (CSV has no sheets).
%
%   An existing file at the target path is deleted first, so the output is
%   always a clean workbook (no stale sheets/cells from a previous run).
%   An empty (zero-row) table still writes its header row.

arguments
    T    table
    file (1,1) string
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
else
    writetable(T, file);
end

% Resolve to the absolute path actually written
d    = dir(file);
file = string(fullfile(d(1).folder, d(1).name));
end
