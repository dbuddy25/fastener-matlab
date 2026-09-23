function bisectExportapp()
%BISECTEXPORTAPP  Find what on the Hardware Library page breaks exportapp.
%   Temporary diagnostic. Run once and paste the output:
%       bisectExportapp
%   Prints OK or FAIL for each step. Nothing is saved except scratch PNGs
%   in a temp folder.

here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
out = tempname;
mkdir(out);

app = gui.FastenerApp();
closer = onCleanup(@() delete(app));
scr = get(groot, "ScreenSize");
app.Fig.Position = [20 50 min(1250, scr(3) - 40) min(820, scr(4) - 110)];
figure(app.Fig);

fprintf("MATLAB %s, screen %dx%d, window %dx%d\n", version, scr(3), scr(4), ...
    app.Fig.Position(3), app.Fig.Position(4));

section("1. Baseline");
app.navigateTo("Project");
attempt(app.Fig, "Project page");
app.navigateTo("HardwareLibrary");
attempt(app.Fig, "Hardware Library, as built");

page = app.page("HardwareLibrary");
grid = page.rootContainer().Children(1);
parts = flip(grid.Children)';

section("2. Hide one part of the page at a time");
for c = parts
    was = c.Visible;
    c.Visible = "off";
    attempt(app.Fig, "without " + describe(c));
    c.Visible = was;
end
section("   Hide everything except one part");
for c = parts
    others = parts(parts ~= c);
    was = arrayfun(@(o) o.Visible, others, "UniformOutput", false);
    set(others, "Visible", "off");
    attempt(app.Fig, "only " + describe(c));
    for k = 1:numel(others)
        others(k).Visible = was{k};
    end
end

tg = findall(grid, "Type", "uitabgroup");
tables = findall(grid, "Type", "uitable");
if ~isempty(tg)
    section("3. Each tab selected");
    for t = flip(tg.Children)'
        tg.SelectedTab = t;
        attempt(app.Fig, "tab " + t.Title);
    end
    tg.SelectedTab = tg.Children(end);

    section("   Each table emptied (all others kept)");
    for t = tables'
        d = t.Data;
        t.Data = {};
        attempt(app.Fig, "empty table in tab " + t.Parent.Parent.Title);
        t.Data = d;
    end
    section("   All tables emptied");
    saved = arrayfun(@(t) t.Data, tables, "UniformOutput", false);
    set(tables, "Data", {});
    attempt(app.Fig, "all six tables empty");
    for k = 1:numel(tables)
        tables(k).Data = saved{k};
    end
end

section("4. Each table alone in a fresh window");
for t = tables'
    f = uifigure("Position", [60 60 900 500]);
    g = uigridlayout(f, [1 1]);
    u = uitable(g, "Data", t.Data, "ColumnName", t.ColumnName, ...
        "RowName", {}, "ColumnSortable", t.ColumnSortable);
    u.ColumnWidth = t.ColumnWidth;
    attempt(f, sprintf("%s alone (%dx%d, class %s)", t.Parent.Parent.Title, ...
        size(t.Data, 1), size(t.Data, 2), class(t.Data)));
    delete(f);
end

fprintf("\nDone. Scratch files in %s\n", out);

    function attempt(fig, label)
        drawnow
        pause(0.5)
        try
            exportapp(fig, char(fullfile(out, "x.png")));
            fprintf("  OK    %s\n", label);
        catch err
            fprintf("  FAIL  %s  (%s)\n", label, err.message);
        end
    end
end

function section(t)
fprintf("\n%s\n", t);
end

function s = describe(c)
s = string(class(c));
s = extractAfter(s, find(char(s) == '.', 1, 'last'));
if isprop(c, "Text") && strlength(string(c.Text)) > 0
    s = s + " """ + extractBefore(string(c.Text) + "                              ", 30) + """";
end
s = s + " (row " + c.Layout.Row(1) + ")";
end
