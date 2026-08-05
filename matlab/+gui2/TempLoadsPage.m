classdef TempLoadsPage < gui2.Page
    %TEMPLOADSPAGE  Global service temperatures (GUI2_SPEC.md Section 3,
    %   "Temp Loads").
    %
    %   GLOBAL, NOT PER-JOINT. Analyses are isothermal soaks — ONE
    %   Nominal/Hot/Cold trio applies to every joint, single-joint and bulk
    %   alike, matching data.loadSettings' NominalTempC/HotTempC/ColdTempC
    %   for the headless path. This page sits in the rail among per-joint
    %   pages (Joint Config, Defined Joints, ...), which is exactly the
    %   layout that makes it easy to misread as scoped to whichever joint is
    %   currently open — hence the banner (GUI2_SPEC.md Section 15,
    %   explicitly called out).
    %
    %   Backed by AppState.Settings (a plain struct — see AppState's
    %   property block), fires SettingsChanged.
    %
    %   Temperatures are degC — engine-native (UNITS.md). There is no
    %   unit-conversion layer in this app, deliberately (GUI2_HARVEST.md D).
    %
    %   VALIDATION AT ENTRY. model.Joint enforces MinTemperature <=
    %   ReferenceTemperature <= MaxTemperature at construction time (the one
    %   place further downstream that would throw); catching a bad ordering
    %   here, with a clear alert and a revert to the last valid trio, beats
    %   surfacing that as a raw constructor error when a joint is finally
    %   analyzed. This mirrors +gui's onServiceTempEdited exactly.

    properties (Access = private)
        NominalField
        HotField
        ColdField
        BannerLabel
        LastValidTemps = [20 20 20]   % [nominal hot cold], always a valid trio
    end

    methods
        function obj = TempLoadsPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "TempLoads";
        end

        function t = title(~)
            t = "Temp Loads";
        end

        function build(obj, parent)
            % Column 2 is a flexible gutter: the panel in column 1 sizes to
            % its content, so three two-digit temperatures do not get a box
            % the width of the window. The banner still spans both columns,
            % because a wrapping warning needs the width.
            g = uigridlayout(parent, [3 2]);
            g.RowHeight   = {'fit', 'fit', '1x'};
            g.ColumnWidth = {'fit', '1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;
            g.Scrollable  = 'on';

            banner = uilabel(g, 'Text', ['GLOBAL — applies to every joint. ' ...
                'This one Nominal/Hot/Cold trio is used for the single-joint ' ...
                'analysis AND every joint in a bulk run; it is not scoped to ' ...
                'whichever joint you last had open.']);
            banner.Layout.Row      = 1;
            banner.Layout.Column   = [1 2];
            banner.WordWrap        = 'on';
            banner.FontWeight      = 'bold';
            banner.BackgroundColor = gui2.palette('bannerWarnBg');
            banner.FontColor       = gui2.palette('bannerWarnFg');
            obj.BannerLabel = banner;

            degC = [char(176) 'C'];   % matches +gui's own degree-symbol idiom
            % No unit in the title: every row now carries its own.
            panel = uipanel(g, 'Title', 'Service Temperatures');
            panel.Layout.Row    = 2;
            panel.Layout.Column = 1;
            pg = uigridlayout(panel, [3 3]);
            % Same shape as the Factors page: fixed name / value columns so
            % the rows read as a table, plus the unit. Temperatures have no
            % symbol worth a column, so the third holds the unit instead —
            % and it belongs after the number, where it is read.
            pg.ColumnWidth = {90, 90, 'fit'};
            pg.RowHeight   = {'fit', 'fit', 'fit'};
            pg.RowSpacing  = 4;
            pg.Padding     = [6 6 6 6];

            tip = ['Global service temperatures, ' degC ' — analyses are ' ...
                'isothermal soaks, so this one trio applies to every joint ' ...
                '(matches data.loadSettings). Nominal = assembly/reference, ' ...
                'Hot = maximum, Cold = minimum. Must satisfy Cold <= ' ...
                'Nominal <= Hot.'];

            obj.NominalField = obj.addTempField(pg, 1, 'Nominal', degC, tip);
            obj.HotField     = obj.addTempField(pg, 2, 'Hot',     degC, tip);
            obj.ColdField    = obj.addTempField(pg, 3, 'Cold',    degC, tip);

            obj.listenTo('SettingsChanged', @() obj.refresh());
        end

        function refresh(obj)
            %REFRESH  AppState.Settings -> controls. Never marks dirty.
            if ~obj.IsBuilt
                return
            end
            s = obj.State.Settings;
            obj.NominalField.Value = s.NominalTempC;
            obj.HotField.Value     = s.HotTempC;
            obj.ColdField.Value    = s.ColdTempC;
            % Only adopt this trio as the revert target when it is actually
            % valid. AppState.Settings has no ordering guard of its own
            % (readCaseFile/parseSettings copies keys verbatim), so a
            % malformed case file could land here with Cold > Hot; showing
            % it is honest (it IS what state holds), but LastValidTemps must
            % stay a trio this page can actually revert TO — never adopt an
            % invalid one.
            if s.ColdTempC <= s.NominalTempC && s.NominalTempC <= s.HotTempC
                obj.LastValidTemps = [s.NominalTempC, s.HotTempC, s.ColdTempC];
            end
        end
    end

    % ---- Widget <-> AppState -----------------------------------------------
    methods (Access = private)
        function c = addTempField(obj, g, row, labelText, unitText, tip)
            %ADDTEMPFIELD  Name | value | unit, one row of the temp grid.
            lb = uilabel(g, 'Text', char(labelText));
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            lb.Tooltip = tip;

            c = uieditfield(g, 'numeric');
            c.Layout.Row    = row;
            c.Layout.Column = 2;
            c.Tooltip = tip;
            obj.bindEdit(c, @(~, ~) obj.onTempEdited());

            un = uilabel(g, 'Text', char(unitText));
            un.Layout.Row    = row;
            un.Layout.Column = 3;
            un.FontColor     = gui2.palette('mutedText');
            un.Tooltip       = tip;
        end

        function onTempEdited(obj)
            %ONTEMPEDITED  Validate Cold <= Nominal <= Hot at entry.
            %   bindEdit has already marked dirty by the time this runs
            %   (GUI2_HARVEST.md A4's unconditional-dirty design) — even on
            %   the revert path below, where AppState.Settings ends up
            %   unchanged. That is a harmless false-positive dirty flag, not
            %   a correctness issue: it costs at most an unnecessary "save?"
            %   prompt, and it can never under-mark a real edit.
            nom  = obj.NominalField.Value;
            hot  = obj.HotField.Value;
            cold = obj.ColdField.Value;
            if cold <= nom && nom <= hot
                obj.LastValidTemps = [nom, hot, cold];
                obj.State.Settings = struct( ...
                    'NominalTempC', nom, 'HotTempC', hot, 'ColdTempC', cold);
            else
                degC = [char(176) 'C'];
                uialert(ancestor(obj.Root, 'figure'), sprintf(['Service ' ...
                    'temperatures must satisfy Cold <= Nominal <= Hot ' ...
                    '(got %g <= %g <= %g ' degC ') — the edit was ' ...
                    'reverted.'], cold, nom, hot), 'Invalid temperatures');
                % Programmatic Value sets fire no callbacks.
                obj.NominalField.Value = obj.LastValidTemps(1);
                obj.HotField.Value     = obj.LastValidTemps(2);
                obj.ColdField.Value    = obj.LastValidTemps(3);
            end
        end
    end

    % ---- Test seams ---------------------------------------------------
    %   Public handle getters, same pattern as PlaceholderPage's counters:
    %   tGui2SetupPages drives real matlab.uitest gestures (type) against
    %   these controls rather than reaching into private state.
    methods
        function f = nominalField(obj)
            f = obj.NominalField;
        end

        function f = hotField(obj)
            f = obj.HotField;
        end

        function f = coldField(obj)
            f = obj.ColdField;
        end

        function lbl = bannerLabel(obj)
            lbl = obj.BannerLabel;
        end
    end
end
