function [item, value] = projectRows(project)
%PROJECTROWS  The Project page's fields as report rows.
%   [item, value] = report.projectRows(project) returns two string column
%   vectors: Analyst, Program, Assembly, Part number and Environment
%   always (a blank one reads as an em dash, so an unfilled field is
%   visibly unfilled), then Notes only when there are any.
%
%   project is gui.AppState.Project, or struct() for none.
arguments
    project struct = struct()
end

names  = ["analyst", "program", "assembly", "partNumber", "environment"];
item   = ["Analyst"; "Program"; "Assembly"; "Part number"; "Environment"];
value  = repmat("—", numel(names), 1);
for k = 1:numel(names)
    v = fieldText(project, names(k));
    if v ~= ""
        value(k) = v;
    end
end

notes = fieldText(project, "notes");
if notes ~= ""
    item(end + 1)  = "Notes";
    value(end + 1) = notes;
end
end

function v = fieldText(s, name)
v = "";
if ~isfield(s, name)
    return
end
x = string(s.(name));
if isempty(x)
    return
end
v = strtrim(strjoin(x(:)', " "));
end
