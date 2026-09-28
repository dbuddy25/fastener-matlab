function c = aboutRows(project, notes)
%ABOUTROWS  The About sheet: tool, version, time, standard, project, notes.
arguments
    project struct = struct()
    notes (1,:) string = string.empty(1, 0)
end
[pItem, pValue] = report.projectRows(project);
item  = ["Tool"; "Version"; "Generated"; "Standard"; pItem];
value = ["Fastener Analysis Tool"; toolVersion(); ...
         string(datetime("now", "Format", "yyyy-MM-dd HH:mm")); ...
         "NASA-STD-5020B"; pValue];
for k = 1:numel(notes)
    item(end + 1)  = "Note"; %#ok<AGROW>
    value(end + 1) = notes(k); %#ok<AGROW>
end
c = cellstr([item, value]);
end
