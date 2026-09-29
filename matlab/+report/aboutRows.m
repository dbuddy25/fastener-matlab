function c = aboutRows(project, notes)
%ABOUTROWS  The About sheet: tool, version, time, standard, project, notes.
arguments
    project struct = struct()
    notes (1,:) string = string.empty(1, 0)
end
[pItem, pValue] = report.projectRows(project);
[~, ~, code] = toolIntegrity();
item  = ["Tool"; "Version"; "Generated"; "Standard"; pItem];
value = ["Fastener Analysis Tool"; toolVersion(); ...
         string(datetime("now", "Format", "yyyy-MM-dd HH:mm")); ...
         "NASA-STD-5020B"; pValue];
if strlength(code) > 0
    % After Version: it qualifies the version. Absent from a checkout.
    item  = [item(1:2); "Calculation code"; item(3:end)];
    value = [value(1:2); code; value(3:end)];
end
for k = 1:numel(notes)
    item(end + 1)  = "Note"; %#ok<AGROW>
    value(end + 1) = notes(k); %#ok<AGROW>
end
c = cellstr([item, value]);
end
