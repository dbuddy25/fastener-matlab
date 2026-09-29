function file = writeBulkWorkbook(file, T, opts)
%WRITEBULKWORKBOOK  Fill the styled bulk template.
%   file = report.writeBulkWorkbook(file, T) copies
%   templates/export_bulk.xlsx and writes a Joint Summary sheet
%   (report.bulkJointSummary) and every row of T to Results, under the
%   readable headers of report.bulkHeaders. The template colours and
%   formats margin columns by those headers (its hidden Lists sheet names
%   them), so no Excel is needed and every value is written unrounded. A not-evaluated margin is written as an
%   em dash, never a blank (CONVENTIONS.md A1).
%   Name-value: Notes (string array), Project (struct) for the About sheet.
arguments
    file (1,1) string
    T    table
    opts.Notes (1,:) string = string.empty(1, 0)
    opts.Project struct = struct()
end

[~, ~, ext] = fileparts(file);
if strlength(ext) == 0
    file = file + ".xlsx";
end
tpl = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "templates", "export_bulk.xlsx");
if isfile(file)
    delete(file);
end
copyfile(tpl, file);

vars = string(T.Properties.VariableNames);
margins = [vars(find(vars == "Shear", 1) + 1:find(vars == "WorstMargin", 1) - 1), "WorstMargin"];

w = {'UseExcel', false, 'PreserveFormat', true, 'AutoFitWidth', false};
writeSheet(file, 'Joint Summary', dashes(report.bulkJointSummary(T), margins), w);
writeSheet(file, 'Results', dashes(T, margins), w);
writecell(report.aboutRows(opts.Project, opts.Notes), file, 'Sheet', 'About', ...
    'Range', 'A2', w{:});
end

function writeSheet(file, sheet, T, w)
head = cellstr(report.bulkHeaders(string(T.Properties.VariableNames)));
writecell(head, file, 'Sheet', sheet, 'Range', 'A1', w{:});
writetable(T, file, 'Sheet', sheet, 'Range', 'A2', 'WriteVariableNames', false, w{:});
end

function T = dashes(T, margins)
% Margin columns with NaN written as an em dash.
for v = margins(ismember(margins, string(T.Properties.VariableNames)))
    x = T.(char(v));
    c = num2cell(x);
    c(isnan(x)) = {char(8212)};
    T.(char(v)) = c;
end
end
