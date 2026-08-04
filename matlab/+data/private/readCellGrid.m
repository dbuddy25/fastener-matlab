function raw = readCellGrid(file, sheet)
%READCELLGRID  readcell with an optional spreadsheet sheet (name or index).
%   raw = readCellGrid(file) reads the file the default way — sheet 1 of a
%   workbook, or the whole text file (.csv).
%   raw = readCellGrid(file, sheet) reads the given sheet of a spreadsheet;
%   `sheet` is a sheet NAME (string/char, e.g. "Elements") or a 1-based
%   INDEX (numeric). [] / "" mean "not specified" (the default read).
%   Text files accept only the default — readcell itself rejects a Sheet
%   argument for .csv.
%
%   Shared by data.loadJointLibrary / data.loadElements / data.loadSettings
%   so all three loaders take the same optional sheet selector (the
%   engine.runWorkbook single-workbook flow reads its Joints / Elements /
%   Settings sheets through this).
if nargin < 2 || isempty(sheet) || ...
        ((ischar(sheet) || isstring(sheet)) && strlength(string(sheet)) == 0)
    raw = readcell(file, "DatetimeType", "text");
else
    raw = readcell(file, "DatetimeType", "text", "Sheet", sheet);
end
end
