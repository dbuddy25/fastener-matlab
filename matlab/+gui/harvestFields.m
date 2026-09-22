function f = harvestFields(page)
%HARVESTFIELDS  Every named input on a built page: its group, name, tooltip.
%   f = gui.harvestFields(page) returns a struct array with fields Group,
%   Field and Tooltip (strings), one per input control, in no set order.
%
%   An input's NAME is its own Text for a checkbox; otherwise its column's
%   bold header label in row 1 of a table-style grid; otherwise the uilabel
%   directly to its left in the same grid row. Inputs with none of these
%   are skipped: nothing names them, so a guide cannot either. Read-only text
%   areas are displays, not inputs, and are skipped too.
%
%   Its GROUP is the nearest enclosing collapsible group, titled panel or
%   tab. The userguide field tables are checked against this list by
%   tUserGuide, so the two can never disagree about what a field is.
arguments
    page (1,1) gui.Page
end

f = struct('Group', {}, 'Field', {}, 'Tooltip', {});
root = page.rootContainer();
if isempty(root)
    return
end

inputClasses = ["matlab.ui.control.EditField", ...
                "matlab.ui.control.NumericEditField", ...
                "matlab.ui.control.DropDown", ...
                "matlab.ui.control.CheckBox", ...
                "matlab.ui.control.Spinner", ...
                "matlab.ui.control.ListBox", ...
                "matlab.ui.control.TextArea"];

keys = strings(1, 0);
for h = findall(root)'
    if ~any(class(h) == inputClasses)
        continue
    end
    if isa(h, "matlab.ui.control.TextArea") && ~logical(h.Editable)
        continue
    end
    [name, labelTip] = fieldName(h);
    if name == ""
        continue
    end
    tip = clean(h.Tooltip);
    if tip == ""
        tip = labelTip;
    end
    group = groupOf(h);
    key = group + "|" + name;
    if any(keys == key)
        continue
    end
    keys(end + 1) = key; %#ok<AGROW>
    f(end + 1) = struct('Group', group, 'Field', name, 'Tooltip', tip); %#ok<AGROW>
end
end

function [name, tip] = fieldName(h)
name = "";
tip  = "";
if isa(h, "matlab.ui.control.CheckBox")
    name = clean(h.Text);
end
p = h.Parent;
if name ~= "" || ~isa(p, "matlab.ui.container.GridLayout")
    return
end
row = h.Layout.Row(1);
col = h.Layout.Column(1);
labels = p.Children(arrayfun(@(c) isa(c, "matlab.ui.control.Label"), p.Children));

% A table-style grid: a bold header label in row 1 of this same column.
if row > 1
    for s = labels'
        if s.Layout.Row(1) == 1 && isequal(s.Layout.Column, col) ...
                && strcmp(char(s.FontWeight), 'bold')
            [name, tip] = labelText(s);
            return
        end
    end
end
if isa(h, "matlab.ui.control.CheckBox")
    return
end
for s = labels'
    if s.Layout.Row(1) == row && s.Layout.Column(end) == col - 1
        [name, tip] = labelText(s);
        return
    end
end
end

function [name, tip] = labelText(s)
name = regexprep(clean(s.Text), "\s*:$", "");
tip  = clean(s.Tooltip);
end

function g = groupOf(h)
% The nearest collapsible group (gui.Page.collapsibleGroup: a header
% button whose text starts with a triangle glyph, beside the body panel),
% else the nearest titled panel or tab.
glyphs = [char(9654), char(9660)];
g = "";
p = h.Parent;
while ~isempty(p) && ~isa(p, "matlab.ui.Figure")
    if isa(p, "matlab.ui.container.Panel") ...
            && isa(p.Parent, "matlab.ui.container.GridLayout")
        for s = p.Parent.Children'
            if isa(s, "matlab.ui.control.Button")
                t = clean(s.Text);
                if strlength(t) > 1 && contains(glyphs, extractBefore(t, 2))
                    g = strtrim(extractAfter(t, 1));
                    return
                end
            end
        end
    end
    if (isa(p, "matlab.ui.container.Panel") || isa(p, "matlab.ui.container.Tab")) ...
            && strlength(clean(p.Title)) > 0
        g = clean(p.Title);
        return
    end
    p = p.Parent;
end
end

function s = clean(x)
x = string(x);
if isempty(x)
    s = "";
    return
end
s = strtrim(regexprep(strjoin(x(:)', " "), "\s+", " "));
end
