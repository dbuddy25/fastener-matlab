function printCalculationMaps(check)
%PRINTCALCULATIONMAPS  Print engine.calculationMap as text, one check or all.
%   printCalculationMaps              every check
%   printCalculationMaps("Slip")      one
%   Each file:line is a link: click it to open the editor at that line.
arguments
    check string {mustBeScalarOrEmpty} = string.empty
end
addpath(fileparts(fileparts(mfilename("fullpath"))));
names = check;
if isempty(names)
    names = engine.calculationMap();
end
for name = names
    m = engine.calculationMap(name);
    fprintf("\n==== %s\n", m.Check);
    for node = m.Nodes
        [~, f] = fileparts(node.File);
        mark = "";
        if node.IsCheck
            mark = "   <- the check";
        end
        fprintf("  %s%s\n", f, mark);
        for e = node.Equations
            fprintf('    <a href="matlab:opentoline(''%s'',%d)">%s:%d</a>  %s — %s\n', ...
                node.File, e.Line, f, e.Line, e.Reference, e.Formula);
        end
    end
    for e = m.Edges
        fprintf("  %s -> %s\n", e.From, e.To);
    end
end
end
