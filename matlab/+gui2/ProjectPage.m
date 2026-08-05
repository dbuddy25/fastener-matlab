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

            panel = uipanel(g, 'Title', 'Project');
            panel.Layout.Row = 2;
            pg = uigridlayout(panel, [7 2]);
            pg.ColumnWidth = {'fit', '1x'};
            pg.RowHeight   = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 90};
            pg.RowSpacing  = 4;
            pg.Padding     = [6 6 6 6];

            obj.AnalystField = obj.addText(pg, 1, 'Analyst:', '');

            lb = uilabel(pg, 'Text', 'Date:');
            lb.Layout.Row    = 2;
            lb.Layout.Column = 1;
            % A uidatepicker requires a real datetime Value — there is no
            % supported blank state to carry forward here, so a blank
            % AppState.Project.date displays as today's date until the
            % analyst types something else (matches the proven +gui
            % behavior; the committed value stays "" until an actual edit
            % fires ValueChangedFcn — see collectProject-equivalent below).
            obj.DateField = uidatepicker(pg, 'Value', datetime('today'));
            obj.DateField.Layout.Row    = 2;
            obj.DateField.Layout.Column = 2;
            obj.bindEdit(obj.DateField, @(~, ~) obj.commit());

            obj.ProgramField = obj.addText(pg, 3, 'Program:', '');
            obj.AssemblyField = obj.addText(pg, 4, 'Assembly:', '');
            obj.PartNumberField = obj.addText(pg, 5, 'Part Number:', '');
            obj.EnvironmentField = obj.addText(pg, 6, 'Environment:', ...
                ['Loading environment for this analysis — e.g. Quasistatic, ' ...
                 'Random Vibration, Temperature Survival.']);

            lb = uilabel(pg, 'Text', 'Notes:');
            lb.Layout.Row    = 7;
            lb.Layout.Column = 1;
            lb.VerticalAlignment = 'top';
            obj.NotesArea = uitextarea(pg);
            obj.NotesArea.Layout.Row    = 7;
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

        function [c, lb] = addText(obj, g, row, labelText, tip)
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            c = uieditfield(g, 'text');
            c.Layout.Row    = row;
            c.Layout.Column = 2;
            if strlength(string(tip)) > 0
                c.Tooltip  = tip;
                lb.Tooltip = tip;
            end
            obj.bindEdit(c, @(~, ~) obj.commit());
        end
    end

    methods (Static, Access = private)
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
