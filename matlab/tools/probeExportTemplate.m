function out = probeExportTemplate()
%PROBEEXPORTTEMPLATE  Does a styled template survive MATLAB filling it?
%   Temporary probe for EXPORTS_PRD.md phase (a). Copies
%   templates/export_probe.xlsx, writes values into it without Excel
%   (UseExcel=false, PreserveFormat=true), then unzips the result and checks
%   that the styling is still there. Prints OK/FAIL per check and the file
%   path, so the workbook can also be opened in Excel and looked at.

here = fileparts(mfilename("fullpath"));
src  = fileparts(here);
tpl  = fullfile(src, "templates", "export_probe.xlsx");
out  = string(fullfile(tempdir, "export_probe_filled.xlsx"));
if isfile(out)
    delete(out);
end
copyfile(tpl, out);

opts = {'Sheet', 'Slide', 'UseExcel', false, 'PreserveFormat', true};
writecell({'DABJ 9 - worst margin -0.65 (Slip), 1 FAIL'}, out, 'Range', 'A1', opts{:});
rows = { ...
    'Tension-Ultimate', 0.69,  'Pass',          'NASA-STD-5020B Eq. 6'; ...
    'Slip',             -0.65, 'FAIL',          'NASA-STD-5020B Eq. 84'; ...
    'Nut strength',     '—',   'Not evaluated', 'No rating and no area'};
writecell(rows, out, 'Range', 'A4', opts{:});

x = string(tempname);
unzip(out, x);
cleanup = onCleanup(@() rmdir(x, 's'));
sheets = "";
for f = dir(fullfile(x, "xl", "worksheets", "*.xml"))'
    sheets = sheets + string(fileread(fullfile(f.folder, f.name)));
end
styles   = string(fileread(fullfile(x, "xl", "styles.xml")));
workbook = string(fileread(fullfile(x, "xl", "workbook.xml")));

check("pass/fail colour rules kept", contains(sheets, "<conditionalFormatting"));
check("fail colour kept in styles", contains(styles, "FFC7C7"));
check("gridlines still off", contains(sheets, 'showGridLines="0"'));
check("title merge kept", contains(sheets, 'A1:D1'));
check("column widths kept", contains(sheets, 'width="26'));
check("named range kept", contains(workbook, "MarginTable"));
b5 = regexp(sheets, '<c r="B5"[^>]*>', 'match', 'once');
check("written cell B5 kept its style", contains(b5, ' s="') && ~contains(b5, ' s="0"'));

back = readcell(out, 'Sheet', 'Slide', 'Range', 'A4:C6');
check("values read back", isequal(back{2, 1}, 'Slip') && back{2, 2} == -0.65 ...
    && strcmp(back{3, 3}, 'Not evaluated'));

fprintf("\nFilled workbook: %s\nOpen it in Excel: title bold, grid off, Slip row red, Nut row amber, MS as +0.69 / -0.65.\n", out);
end

function check(label, ok)
if ok
    fprintf("  OK    %s\n", label);
else
    fprintf("  FAIL  %s\n", label);
end
end
