function file = writeSingleJointWorkbook(file, v)
%WRITESINGLEJOINTWORKBOOK  Fill the styled single-joint template.
%   file = report.writeSingleJointWorkbook(file, v) copies
%   templates/export_single.xlsx to file and writes the view v into its
%   named ranges (report.exportLayout). No Excel is needed: the template
%   carries every style, and writecell only adds values.
%
%   v fields (cell arrays of char/numbers unless noted):
%     Title, Subtitle, VerdictClass ("fail"|"noteval"|"pass"), Scope  char
%     Inputs   N x 2  label | value                     (N <= 15)
%     Margins  M x 4  check | MS or text | status | eq  (M <= 15)
%     Details  M x 6  check | status | value | method | inputs | detail
%     About    K x 2  item | value                      (K <= 24)
arguments
    file (1,1) string
    v    (1,1) struct
end

[~, ~, ext] = fileparts(file);
if strlength(ext) == 0
    file = file + ".xlsx";
end
tpl = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "templates", "export_single.xlsx");
if isfile(file)
    delete(file);
end
copyfile(tpl, file);

L = report.exportLayout();
put(file, L.SlideTitle,        {v.Title});
put(file, L.SlideSubtitle,     {v.Subtitle});
put(file, L.SlideVerdictClass, {v.VerdictClass});
put(file, L.SlideInputs,       v.Inputs);
put(file, L.SlideMargins,      v.Margins);
put(file, L.SlideScope,        {v.Scope});
put(file, L.DetailRows,        v.Details);
put(file, L.AboutRows,         v.About);
end

function put(file, spec, data)
if isempty(data)
    return
end
if size(data, 1) > spec.Rows || size(data, 2) > spec.Cols
    error("report:writeSingleJointWorkbook:tooBig", ...
        "%s holds %d x %d cells; got %d x %d.", spec.Name, ...
        spec.Rows, spec.Cols, size(data, 1), size(data, 2));
end
% AutoFitWidth off: its default resizes the template's columns.
writecell(data, file, 'Sheet', spec.Sheet, 'Range', spec.TopLeft, ...
    'UseExcel', false, 'PreserveFormat', true, 'AutoFitWidth', false);
end
