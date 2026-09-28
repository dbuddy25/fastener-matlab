function m = calculationMap(check)
%CALCULATIONMAP  The functions and equations behind one check, read from the code.
%   m = engine.calculationMap("Slip") returns a struct:
%     Check   the check name
%     Nodes   struct array: Name, File (full path), IsCheck, Equations
%             (struct array: Line, Reference, Formula, Description)
%     Edges   struct array: From, To (From feeds To)
%   names = engine.calculationMap() returns the 15 check names.
%
%   Nothing here is hand-maintained. Equations are the traceability comments
%   CONVENTIONS.md requires at every equation ("% <reference> Eq. N — <formula>");
%   edges are engine.* and +engine/private calls with comments stripped, plus
%   the results engine.analyze passes into each margin function. A function
%   joins a map only if it, or something it calls, carries an equation.
arguments
    check string {mustBeScalarOrEmpty} = string.empty
end

roots = rootTable();
if isempty(check)
    m = string(keys(roots));
    return
end
if ~isKey(roots, char(check))
    error("engine:calculationMap:unknownCheck", ...
        'No check named "%s". Known: %s.', check, strjoin(string(keys(roots)), ", "));
end

% Cached per check until any +engine file changes, so switching checks is
% instant while an edited file is still picked up on the next call.
persistent cache stamp
now = sourceStamp();
if isempty(cache) || ~isequal(stamp, now)
    cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    stamp = now;
end
if isKey(cache, char(check))
    m = cache(char(check));
    return
end

src = sources();
root = string(roots(char(check)));

feeds = analyzeFeeds(src);
start = root;
if isKey(feeds, char(root))
    start = [start, feeds(char(root))];
end

memo = containers.Map('KeyType', 'char', 'ValueType', 'logical');
names = strings(1, 0);
edges = struct('From', {}, 'To', {});
queue = start;
for s = start(2:end)
    edges(end + 1) = struct('From', s, 'To', root); %#ok<AGROW>
end
while ~isempty(queue)
    n = queue(1);
    queue(1) = [];
    if any(names == n)
        continue
    end
    names(end + 1) = n; %#ok<AGROW>
    for c = callsOf(src, n)
        if hasEquations(src, c, memo, strings(1, 0))
            edges(end + 1) = struct('From', c, 'To', n); %#ok<AGROW>
            queue(end + 1) = c; %#ok<AGROW>
        end
    end
end

nodes = struct('Name', {}, 'File', {}, 'IsCheck', {}, 'Equations', {});
for n = names
    nodes(end + 1) = struct('Name', n, 'File', src.file(char(n)), ...
        'IsCheck', n == root, 'Equations', equationsOf(src, n)); %#ok<AGROW>
end
m = struct('Check', check, 'Nodes', nodes, 'Edges', edges);
cache(char(check)) = m;
end

function s = sourceStamp()
here = fileparts(mfilename("fullpath"));
d = [dir(fullfile(here, "*.m")); dir(fullfile(here, "private", "*.m"))];
s = [numel(d), max([d.datenum]), sum([d.bytes])];
end

function t = rootTable()
t = containers.Map( ...
    {'Tension-Ultimate', 'Tension-Yield', 'Shear-Ultimate', 'Interaction', ...
     'Separation', 'Slip', 'Separation-before-rupture', 'Bearing', ...
     'Bearing-under-head', 'Shear-tearout', 'Bolt-thread shear', ...
     'Nut strength', 'Insert internal-thread', 'Insert external-thread', ...
     'Tapped-hole parent-thread'}, ...
    {'marginTensionUlt', 'marginTensionYield', 'marginShearUlt', 'marginInteraction', ...
     'marginSeparation', 'marginSlip', 'separationBeforeRuptureGate', 'marginBearing', ...
     'marginBearingUnderHead', 'marginShearTearout', 'marginBoltThreadShear', ...
     'marginNutStrength', 'marginInsertInternal', 'marginInsert', ...
     'marginTappedParentThread'});
end

function src = sources()
here = fileparts(mfilename("fullpath"));
src.file = containers.Map('KeyType', 'char', 'ValueType', 'any');
src.text = containers.Map('KeyType', 'char', 'ValueType', 'any');
src.private = strings(1, 0);
for d = [dir(fullfile(here, "*.m")); dir(fullfile(here, "private", "*.m"))]'
    [~, n] = fileparts(d.name);
    f = string(fullfile(d.folder, d.name));
    src.file(n) = f;
    src.text(n) = splitlines(string(fileread(f)));
    if endsWith(string(d.folder), "private")
        src.private(end + 1) = n;
    end
end
end

function c = callsOf(src, n)
code = stripped(src.text(char(n)));
c = strings(1, 0);
for t = regexp(code, 'engine\.(\w+)\s*\(', 'tokens')
    name = string(t{1}{1});
    if isKey(src.file, char(name)) && name ~= n && ~any(c == name)
        c(end + 1) = name; %#ok<AGROW>
    end
end
for p = src.private
    if p ~= n && ~any(c == p) && ~isempty(regexp(code, "\<" + p + "\s*\(", 'once'))
        c(end + 1) = p; %#ok<AGROW>
    end
end
end

function code = stripped(lines)
lines = regexprep(lines, "'[^'\n]*'|""[^""\n]*""", "''");
lines = regexprep(lines, "%.*$", "");
code = strjoin(lines(:)', newline);
end

function tf = hasEquations(src, n, memo, seen)
if isKey(memo, char(n))
    tf = memo(char(n));
    return
end
if any(seen == n)
    tf = false;
    return
end
tf = ~isempty(equationsOf(src, n));
if ~tf
    for c = callsOf(src, n)
        if hasEquations(src, c, memo, [seen, n])
            tf = true;
            break
        end
    end
end
memo(char(n)) = tf;
end

function eqs = equationsOf(src, n)
lines = src.text(char(n));
% Non-capturing inner groups: MATLAB returns only the two outer tokens.
refs = "(?:NASA-STD-5020B|NASA TM-106943|TM-106943|NASA RP-1228|RP-1228|Shigley|ASME B1\.1|NASM\d+)";
pat = "^\s*%\s*(" + refs + "[^=]*?)\s+(?:—|–|-)\s+(.*=.*)$";
eqs = struct('Line', {}, 'Reference', {}, 'Formula', {}, 'Description', {});
k = headerEnd(lines);
while k < numel(lines)
    k = k + 1;
    tok = regexp(lines(k), pat, 'tokens', 'once');
    if isempty(tok)
        continue
    end
    formula = strtrim(tok(2));
    % A formula that wraps continues on the following comment lines.
    j = k;
    while j < numel(lines) && j < k + 3
        nxt = lines(j + 1);
        if isempty(regexp(nxt, "^\s*%\s+\S", 'once')) || ...
                ~isempty(regexp(nxt, "^\s*%\s*" + refs, 'once'))
            break
        end
        formula = formula + " " + strtrim(regexprep(nxt, "^\s*%\s*", ""));
        j = j + 1;
    end
    ref = strtrim(regexprep(tok(1), "\s*\(DABJ[^)]*\)", ""));
    eqs(end + 1) = struct('Line', k, 'Reference', ref, 'Formula', formula, ...
        'Description', describe(formula)); %#ok<AGROW>
end
end

function k = headerEnd(lines)
% The line index just before the first code after the function's help block.
k = find(startsWith(strtrim(lines), ["function", "classdef"]), 1);
if isempty(k)
    k = 0;
    return
end
while k < numel(lines) && (startsWith(strtrim(lines(k + 1)), "%") || strtrim(lines(k + 1)) == "")
    k = k + 1;
end
end

function feeds = analyzeFeeds(src)
% Which earlier results engine.analyze passes into each margin function.
code = stripped(src.text('analyze'));
producers = containers.Map('KeyType', 'char', 'ValueType', 'any');
for t = regexp(code, '(\w+)\s*=\s*engine\.(\w+)\s*\(', 'tokens')
    producers(t{1}{1}) = string(t{1}{2});
end
feeds = containers.Map('KeyType', 'char', 'ValueType', 'any');
for t = regexp(code, '\w+\s*=\s*engine\.(\w+)\s*\(([^;]*)\)\s*;', 'tokens')
    fn = string(t{1}{1});
    ups = strings(1, 0);
    for a = strtrim(split(string(t{1}{2}), ","))'
        if isKey(producers, char(a)) && producers(char(a)) ~= fn
            ups(end + 1) = producers(char(a)); %#ok<AGROW>
        end
    end
    feeds(char(fn)) = ups;
end
end

function d = describe(formula)
% A short name for what an equation computes, from its left-hand side. A
% relation (<=, >=) is a gate condition rather than a quantity.
tok = regexp(formula, "^\s*(.+?)\s*(<=|>=|=)", 'tokens', 'once');
d = "";
if isempty(tok)
    return
end
lhs = strtrim(tok(1));
if tok(2) ~= "="
    gates = dictionary(["PpMax", "n", "e/D"], ...
        ["Fig. 8 preload gate", "Fig. 8 loading-plane gate", "Edge-distance gate"]);
    if isKey(gates, lhs)
        d = gates(lhs);
    end
    return
end
names = dictionary( ...
    ["MS", "Pb", "PbYield", "Lmin", "Pty_allow", "Ptu_allow", "Psu_allow", ...
     "design load", "Abr", "D_minor,int", "As", "Pult", "allowable pull-out", ...
     "Rt", "Rs", "Rb", "Capacity", "Demand", "P'tu", "P'ty", "Ppi_nom", ...
     "c_max", "Ppi_max", "Ppi_min", "Pth", "PpMax", "PpMin", "fbu", "Fsy", "phi"], ...
    ["Margin of safety", "Bolt design load", "Bolt design load (yield)", ...
     "Minimum bolt length", "Tension yield allowable", "Tension ultimate allowable", ...
     "Shear allowable", "Design loads", "Bearing area", ...
     "Internal-thread minor diameter", "Shear area", "Ultimate allowable", ...
     "Insert pull-out allowable", "Tension ratio", "Shear ratio", "Bending ratio", ...
     "Friction capacity", "Slip demand", "Allowable applied tension (rupture)", ...
     "Allowable applied tension (yield)", "Nominal initial preload", ...
     "Torque-tolerance factors", "Max initial preload", "Min initial preload", ...
     "Thermal preload change", "Max preload", "Min preload", "Bending stress", ...
     "Shear yield strength", "Load factor"]);
if isKey(names, lhs)
    d = names(lhs);
end
end

