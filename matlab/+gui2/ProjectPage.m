classdef ProjectPage < gui2.Page
    %PROJECTPAGE  Project metadata (GUI2_SPEC.md Section 3, "Project").
    %   Analyst / date / program / assembly / part number / environment /
    %   notes. NEVER analyzed — engine.analyze takes no Project input. This
    %   metadata flows only to reports and exports, so nothing here is
    %   required and nothing is validated beyond what the widgets enforce
    %   natively.
    %
    %   Backed by AppState.Project (a plain struct — see AppState's property
    %   block), and every edit fires ProjectChanged through its setter.

    properties (Access = private)
        AnalystField
        DateField
        ProgramField
        AssemblyField
        PartNumberField
        EnvironmentField
        NotesArea
    end

    methods
        function obj = ProjectPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "Project";
        end

        function t = title(~)
            t = "Project";
        end

        function build(obj, parent)
            g = uigridlayout(parent, [2 1]);
            g.RowHeight   = {'fit', '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;
            g.Scrollable  = 'on';

            banner = uilabel(g, 'Text', ['Project metadata — never analyzed. ' ...
                'It flows to reports and exports only; nothing here affects ' ...
                'a margin.']);
            banner.Layout.Row      = 1;
            banner.WordWrap        = 'on';
            banner.BackgroundColor = gui2.palette('bannerInfoBg');
            banner.FontColor       = gui2.palette('bannerInfoFg');

            % Four logical rows, each its own nested grid: Analyst+Date,
            % then Program+Assembly+Part Number, then Environment alone,
            % then Notes. Nesting rather than one wide grid because the
            % rows hold two, three, and one field respectively — a single
            % grid would need a least-common-multiple column count and
            % every field would be placed by arithmetic instead of by name.
            %
            % The cost, stated because it is a real one: label columns are
            % 'fit' per sub-grid, so labels do NOT align vertically between
            % rows. That is inherent to putting three fields on one line,
            % not a consequence of the nesting.
            panel = uipanel(g, 'Title', 'Project');
            panel.Layout.Row = 2;
            pg = uigridlayout(panel, [4 1]);
            pg.ColumnWidth = {'1x'};
            pg.RowHeight   = {'fit', 'fit', 'fit', 100};
            pg.RowSpacing  = 4;
            pg.Padding     = [6 6 6 6];

            % ---- Row 1: Analyst | Date ---------------------------------
            % Date takes a fixed width rather than '1x': a picker stretched
            % across half the panel looks like it accepts more than a date.
            r1 = gui2.ProjectPage.inlineRow(pg, 1, {'fit', '1x', 'fit', 150});
            obj.AnalystField = obj.addText(r1, 1, 'Analyst:', '');

            lb = uilabel(r1, 'Text', 'Date:');
            lb.Layout.Row    = 1;
            lb.Layout.Column = 3;
            % A uidatepicker requires a real datetime Value — there is no
            % supported blank state to carry forward here, so a blank
            % AppState.Project.date displays as today's date until the
            % analyst types something else (matches the proven +gui
            % behavior; the committed value stays "" until an actual edit
            % fires ValueChangedFcn — see collectProject-equivalent below).
            obj.DateField = uidatepicker(r1, 'Value', datetime('today'));
            obj.DateField.Layout.Row    = 1;
            obj.DateField.Layout.Column = 4;
            obj.bindEdit(obj.DateField, @(~, ~) obj.commit());

            % ---- Row 2: Program | Assembly | Part Number ---------------
            r2 = gui2.ProjectPage.inlineRow(pg, 2, ...
                {'fit', '1x', 'fit', '1x', 'fit', '1x'});
            obj.ProgramField    = obj.addText(r2, 1, 'Program:', '');
            obj.AssemblyField   = obj.addText(r2, 3, 'Assembly:', '');
            obj.PartNumberField = obj.addText(r2, 5, 'Part Number:', '');

            % ---- Row 3: Environment, on its own line -------------------
            r3 = gui2.ProjectPage.inlineRow(pg, 3, {'fit', '1x'});
            obj.EnvironmentField = obj.addText(r3, 1, 'Environment:', ...
                ['Loading environment for this analysis — e.g. Quasistatic, ' ...
                 'Random Vibration, Temperature Survival.']);

            % ---- Row 4: Notes ------------------------------------------
            r4 = gui2.ProjectPage.inlineRow(pg, 4, {'fit', '1x'});
            % '1x', not the shared 'fit': this is the one row with a fixed
            % height to fill, and a 'fit' sub-grid would collapse the text
            % area back to a single line inside a 100 px slot.
            r4.RowHeight = {'1x'};
            lb = uilabel(r4, 'Text', 'Notes:');
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            lb.VerticalAlignment = 'top';
            obj.NotesArea = uitextarea(r4);
            obj.NotesArea.Layout.Row    = 1;
            obj.NotesArea.Layout.Column = 2;
            obj.bindEdit(obj.NotesArea, @(~, ~) obj.commit());

            obj.listenTo('ProjectChanged', @() obj.refresh());
        end

        function refresh(obj)
            %REFRESH  AppState.Project -> controls. Never marks dirty — a
            %   File > Open landing on this page while it is active must
            %   repopulate without the app claiming an edit just happened
            %   (GUI2_HARVEST.md A4).
            if ~obj.IsBuilt
                return
            end
            p = obj.State.Project;
            obj.AnalystField.Value     = char(gui2.ProjectPage.fieldStr(p, 'analyst'));
            obj.ProgramField.Value     = char(gui2.ProjectPage.fieldStr(p, 'program'));
            obj.AssemblyField.Value    = char(gui2.ProjectPage.fieldStr(p, 'assembly'));
            obj.PartNumberField.Value  = char(gui2.ProjectPage.fieldStr(p, 'partNumber'));
            obj.EnvironmentField.Value = char(gui2.ProjectPage.fieldStr(p, 'environment'));
            obj.NotesArea.Value = cellstr(splitlines( ...
                gui2.ProjectPage.fieldStr(p, 'notes')));

            txt = gui2.ProjectPage.fieldStr(p, 'date');
            if strlength(txt) == 0
                obj.DateField.Value = datetime('today');
            else
                try
                    obj.DateField.Value = datetime(txt, 'InputFormat', 'yyyy-MM-dd');
                catch
                    obj.DateField.Value = datetime('today');
                end
            end
        end
    end

    % ---- Widget -> AppState -----------------------------------------------
    methods (Access = private)
        function commit(obj)
            %COMMIT  Read every control and write AppState.Project in one shot.
            %   Fired by bindEdit, so markDirty() has already run. Assigning
            %   State.Project fires ProjectChanged, which calls refresh() —
            %   harmless: refresh writes back the same values the controls
            %   already hold, and programmatic Value sets fire no callback,
            %   so there is no re-entrant dirty call.
            p = struct();
            p.analyst = string(obj.AnalystField.Value);
            d = obj.DateField.Value;
            if isnat(d)
                p.date = "";
            else
                p.date = string(d, 'yyyy-MM-dd');
            end
            p.program     = string(obj.ProgramField.Value);
            p.assembly    = string(obj.AssemblyField.Value);
            p.partNumber  = string(obj.PartNumberField.Value);
            p.environment = string(obj.EnvironmentField.Value);
            notesLines = obj.NotesArea.Value;
            if ischar(notesLines)
                notesLines = {notesLines};
            end
            p.notes = string(strjoin(notesLines, newline));
            obj.State.Project = p;
        end

        function [c, lb] = addText(obj, g, col, labelText, tip)
            %ADDTEXT  Label + text field in one inline row of a nested grid.
            %   col is the LABEL's column; the field lands in col + 1. Every
            %   caller sits on row 1 of its own single-row sub-grid, so the
            %   row never has to be threaded through.
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = 1;
            lb.Layout.Column = col;
            c = uieditfield(g, 'text');
            c.Layout.Row    = 1;
            c.Layout.Column = col + 1;
            if strlength(string(tip)) > 0
                c.Tooltip  = tip;
                lb.Tooltip = tip;
            end
            obj.bindEdit(c, @(~, ~) obj.commit());
        end
    end

    methods (Static, Access = private)
        function rg = inlineRow(parent, row, cols)
            %INLINEROW  One-row nested grid holding several label+field pairs.
            %   Zero padding so the sub-grid adds no inset of its own, and
            %   8 px between columns — the inline-row spacing carried
            %   forward from the first build (GUI2_HARVEST.md D).
            rg = uigridlayout(parent, [1 numel(cols)]);
            rg.Layout.Row    = row;
            rg.Layout.Column = 1;
            rg.ColumnWidth   = cols;
            rg.RowHeight     = {'fit'};
            rg.ColumnSpacing = 8;
            rg.Padding       = [0 0 0 0];
        end

        function s = fieldStr(st, name)
            %FIELDSTR  Optional struct field -> string ("" when absent).
            if isstruct(st) && isfield(st, name)
                s = string(st.(name));
            else
                s = "";
            end
        end
    end

    % ---- Test seams ---------------------------------------------------
    %   Public handle getters, same pattern as PlaceholderPage's counters:
    %   tGui2SetupPages drives real matlab.uitest gestures (type/press)
    %   against these controls rather than reaching into private state.
    methods
        function f = analystField(obj)
            f = obj.AnalystField;
        end
    end
end
