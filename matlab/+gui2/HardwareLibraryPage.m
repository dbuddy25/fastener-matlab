classdef HardwareLibraryPage < gui2.Page
    %HARDWARELIBRARYPAGE  Browse the hardware/material library (GUI step 9).
    %   Six read-only tabs — Materials, Bolts, Bolt Specs, Nuts, Washers,
    %   Inserts — over data.Library, with an origin filter and every entry's
    %   SOURCE CITATION on screen.
    %
    %   WHY THE SOURCE COLUMN IS THE POINT OF THIS PAGE. Every one of the
    %   186 shipped entries carries a cited source — which standard, which
    %   table, which assumption — and until now none of it was visible from
    %   inside the tool. An analyst looking at a margin could not answer
    %   "where did this allowable come from?" without opening library.json
    %   in a text editor. That is the question a reviewer asks first.
    %
    %   APP-SCOPED, NOT CASE-SCOPED, and this page must never blur that:
    %       Materials & Hardware  = data.Library — baseline plus custom,
    %                               persisted to its own file, shared by
    %                               every case.
    %       Defined Joints        = AppState.JointLibrary — saved inside the
    %                               case file, travels with the analysis.
    %   The rail labels were renamed apart for exactly this reason
    %   (GUI2_SPEC.md §15), and each page states its scope in-page.
    %
    %   IT MUST NOT CALL markDirty(). The hardware library is not part of
    %   the case, so dirtying the case for a library action would stale the
    %   displayed Result and Bulk over an edit that cannot change either,
    %   and would put an asterisk on a title bar for work that is not in the
    %   file being titled. AppState.markDirty's own header says a data
    %   setter never touches IsDirty; this page extends that to its own
    %   actions. Persistence is an explicit act (step 9c), not a side
    %   effect of navigation.
    %
    %   ORIGIN RENDERS AS ASCII, not as the lock/pencil glyphs GUI2_SPEC.md
    %   §16 sketches. Deliberate, and inherited from the first-pass DB tab:
    %   the glyphs are non-ASCII (the lock is outside the Basic Multilingual
    %   Plane), this code is written on a machine that never runs it, and a
    %   font-fallback or file-encoding problem on the Windows target would
    %   silently break the one column that carries the protection state.
    %   A word cannot fail that way.
    %
    %   READ-ONLY BY CONSTRUCTION. Every table sets ColumnEditable = false.
    %   Baseline rows are protected because data.Library refuses to write
    %   them, but a table that LOOKS editable and then reverts teaches the
    %   analyst to distrust the page. Adding and duplicating arrive in step
    %   9c as explicit buttons, which is also where the decision landed:
    %   browse plus add plus duplicate-as-custom, no inline editing.
    %
    %   Test seams at the bottom, including buildCount/refreshCount —
    %   tGui2Shell used PlaceholderPage's counters to pin the shell's
    %   lazy-build and refresh-per-visit contracts, and this page being real
    %   is what retires the last placeholder. Those assertions move here
    %   rather than disappearing.

    properties (Access = private)
        Grid                        % page root uigridlayout
        FilterDropDown              % origin filter: All / Baseline / Custom
        TabGroup                    % the six sections
        Tables      = struct()      % entity token -> uitable handle
        CountLabels = struct()      % entity token -> the "n of m" label
        DetailArea                  % full source text for the selected row
        BuildCount   (1,1) double = 0
        RefreshCount (1,1) double = 0
    end

    methods
        function obj = HardwareLibraryPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            % THE ID IS THE CONTRACT (FastenerApp.pageSpecs). It was
            % "HardwareLibrary" while this page was a placeholder and it
            % stays that, or every navigateTo and tGui2Shell's rail
            % assertion breaks for a rename that buys nothing.
            id = "HardwareLibrary";
        end

        function t = title(~)
            t = "Materials & Hardware";
        end

        function build(obj, parent)
            obj.BuildCount = obj.BuildCount + 1;

            g = uigridlayout(parent, [5 1]);
            g.RowHeight   = {'fit', 32, '1x', 64, 20};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 6;
            obj.Grid = g;

            obj.addBanner(g, 1, 1, ...
                ['APP-SCOPED — this library is shared by every case and is ' ...
                 'not saved in the case file. Baseline entries ship with the ' ...
                 'tool and are read-only; each row shows the source its ' ...
                 'values were taken from.']);

            obj.buildToolbar(g, 2);

            obj.TabGroup = uitabgroup(g);
            obj.TabGroup.Layout.Row    = 3;
            obj.TabGroup.Layout.Column = 1;

            % ONE BUILDER, SIX CALLS. The sections differ only in their
            % column list, so a per-section method would be six copies of
            % one layout drifting apart. buildSection is the whole reason
            % the specs live in a table rather than in code.
            for spec = gui2.HardwareLibraryPage.sectionSpecs()
                obj.buildSection(spec);
            end

            obj.DetailArea = uitextarea(g, 'Editable', 'off');
            obj.DetailArea.Layout.Row    = 4;
            obj.DetailArea.Layout.Column = 1;
            obj.DetailArea.Value = ...
                {'Select a row to see its full source citation.'};
            obj.DetailArea.FontColor = gui2.palette('mutedText');

            % A library edit made anywhere must reach this page. Nothing in
            % +gui2 listened to LibraryChanged before step 9 — the event was
            % declared and fired and had no subscribers at all.
            obj.listenTo('LibraryChanged', @() obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            obj.RefreshCount = obj.RefreshCount + 1;
            if isempty(obj.TabGroup) || ~isvalid(obj.TabGroup)
                return
            end
            for spec = gui2.HardwareLibraryPage.sectionSpecs()
                obj.renderSection(spec);
            end
        end
    end

    % ---- Building ---------------------------------------------------------
    methods (Access = private)
        function buildToolbar(obj, parent, row)
            bar = uigridlayout(parent, [1 3]);
            bar.Layout.Row    = row;
            bar.Layout.Column = 1;
            bar.RowHeight     = {'1x'};
            bar.ColumnWidth   = {50, 130, '1x'};
            bar.Padding       = [0 0 0 0];
            bar.ColumnSpacing = 8;

            lb = uilabel(bar, 'Text', 'Source:');
            lb.Layout.Row = 1;  lb.Layout.Column = 1;
            lb.HorizontalAlignment = 'right';

            % Items are what a user reads; ItemsData is the token
            % data.Library's origin filters actually take ("" = all).
            obj.FilterDropDown = uidropdown(bar, ...
                'Items',     {'All', 'Baseline', 'Custom'}, ...
                'ItemsData', {'', 'baseline', 'custom'}, ...
                'Tooltip',   ['Baseline entries ship with the tool and are ' ...
                              'read-only. Custom entries were added here.']);
            obj.FilterDropDown.Layout.Row    = 1;
            obj.FilterDropDown.Layout.Column = 2;
            obj.FilterDropDown.ValueChangedFcn = @(~, ~) obj.refresh();
        end

        function buildSection(obj, spec)
            tab = uitab(obj.TabGroup, 'Title', spec.Title);

            g = uigridlayout(tab, [2 1]);
            g.RowHeight   = {'1x', 18};
            g.ColumnWidth = {'1x'};
            g.Padding     = [6 6 6 6];
            g.RowSpacing  = 4;

            t = uitable(g);
            t.Layout.Row    = 1;
            t.Layout.Column = 1;
            t.ColumnName    = spec.Columns;
            t.ColumnWidth   = spec.Widths;
            t.RowName       = {};
            % READ-ONLY. See the class header: a table that looks editable
            % and then reverts is worse than one that never invited the
            % edit. Adding and duplicating are buttons, in step 9c.
            t.ColumnEditable  = false;
            t.ColumnSortable  = true;
            t.SelectionType   = 'row';
            t.SelectionChangedFcn = @(~, evt) obj.onRowSelected(spec.Id, evt);
            obj.Tables.(spec.Id) = t;

            c = uilabel(g, 'Text', '');
            c.Layout.Row = 2;  c.Layout.Column = 1;
            c.FontColor  = gui2.palette('mutedText');
            obj.CountLabels.(spec.Id) = c;
        end
    end

    % ---- Rendering --------------------------------------------------------
    methods (Access = private)
        function renderSection(obj, spec)
            t = obj.Tables.(spec.Id);
            if isempty(t) || ~isvalid(t)
                return
            end

            [rows, total] = obj.sectionRows(spec);
            t.Data      = rows;
            t.Selection = [];       % old row indices no longer mean anything
            obj.DetailArea.Value = ...
                {'Select a row to see its full source citation.'};

            shown = size(rows, 1);
            if shown == total
                obj.CountLabels.(spec.Id).Text = ...
                    sprintf('%d %s', total, spec.Noun);
            else
                % THE FILTER MUST ANNOUNCE WHAT IT HID. An empty-looking
                % Custom tab and a library with no custom entries are the
                % same picture otherwise.
                obj.CountLabels.(spec.Id).Text = sprintf( ...
                    '%d of %d %s shown (%s filter)', shown, total, ...
                    spec.Noun, obj.filterLabel());
            end
        end

        function [rows, total] = sectionRows(obj, spec)
            rows  = {};
            total = 0;
            if ~obj.State.LibraryOK || isempty(obj.State.Library)
                return
            end
            % entries() is the ONLY accessor that exposes origin, source and
            % the provenance stamps — the typed getters (material(), nut(),
            % ...) drop all three, so a browse view cannot be built on them.
            try
                list = obj.State.Library.entries(spec.Id);
            catch
                return
            end
            total = numel(list);

            want = string(obj.filterValue());
            keep = true(1, total);
            if strlength(want) > 0
                for i = 1:total
                    keep(i) = strcmp(string(list{i}.origin), want);
                end
            end
            list = list(keep);

            rows = cell(numel(list), numel(spec.Fields));
            for i = 1:numel(list)
                rows(i, :) = gui2.HardwareLibraryPage.entryRow( ...
                    list{i}, spec.Fields);
            end
        end

        function onRowSelected(obj, entityId, evt)
            % The Source column is truncated by its width; the citations are
            % whole sentences and the useful ones are long. The detail area
            % is where the column stops being a preview.
            if isempty(evt.Selection)
                obj.DetailArea.Value = ...
                    {'Select a row to see its full source citation.'};
                return
            end
            spec = gui2.HardwareLibraryPage.specFor(char(entityId));
            data = obj.Tables.(char(entityId)).Data;
            r    = evt.Selection(1);
            if r < 1 || r > size(data, 1)
                return
            end
            keyCol = find(strcmp(spec.Fields, 'key'), 1);
            srcCol = find(strcmp(spec.Fields, 'source'), 1);
            obj.DetailArea.Value = { ...
                char(string(data{r, keyCol})), ...
                '', ...
                char(string(data{r, srcCol}))};
            obj.DetailArea.FontColor = gui2.palette('defaultText');
        end

        function v = filterValue(obj)
            if isempty(obj.FilterDropDown) || ~isvalid(obj.FilterDropDown)
                v = '';
                return
            end
            v = obj.FilterDropDown.Value;
        end

        function s = filterLabel(obj)
            v = string(obj.filterValue());
            if strlength(v) == 0
                s = 'All';
            else
                s = char(v);
            end
        end
    end

    % ---- The section table ------------------------------------------------
    methods (Static, Access = private)
        function specs = sectionSpecs()
            %SECTIONSPECS  One row per library entity type.
            %   Id      data.Library entity token (entries/duplicateAsCustom)
            %   Fields  entry-struct field per column. Column 1 is ALWAYS
            %           origin and column 2 ALWAYS key — step 9c's Duplicate
            %           reads the key out of the selected row by that
            %           position, and onRowSelected finds source by name.
            %   Columns header text, units per UNITS.md
            %   Widths  uitable ColumnWidth
            %   Noun    plural, for the "n of m" count line
            %
            %   Materials, bolts and bolt specs are ported from the
            %   first-pass DB tab. Nuts, washers and inserts never had a
            %   browse section — the old file says so and says each is one
            %   row here when it lands. This is that.
            specs = [ ...
                struct('Id', 'material', 'Title', 'Materials', 'Noun', 'materials', ...
                    'Fields',  {{'origin', 'key', 'ftu', 'fty', 'fsu', ...
                                 'fsy', 'fbru', 'fbry', 'e', 'cte', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Ftu (psi)', 'Fty (psi)', ...
                                 'Fsu (psi)', 'Fsy (psi)', 'Fbru (psi)', ...
                                 'Fbry (psi)', 'E (psi)', 'CTE (1/degC)', 'Source'}}, ...
                    'Widths',  {{62, 120, 75, 75, 75, 75, 75, 75, 90, 90, 'auto'}}), ...
                struct('Id', 'bolt', 'Title', 'Bolts', 'Noun', 'bolts', ...
                    'Fields',  {{'origin', 'key', 'spec', 'type', ...
                                 'nominalDiameter', 'series', 'tpi', ...
                                 'tensileStressArea', 'minorDiameter', ...
                                 'pitchDiameter', 'bodyDiameter', ...
                                 'headBearingDiameter', 'threadLength', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Spec', 'Type', ...
                                 'Nom dia (in)', 'Series', 'TPI', ...
                                 'At (in^2)', 'Minor dia (in)', ...
                                 'Pitch dia (in)', 'Body dia (in)', ...
                                 'Head brg face OD (in)', 'Thread len (in)', 'Source'}}, ...
                    'Widths',  {{62, 110, 165, 60, 80, 50, 40, 70, 82, 82, 80, 100, 90, 'auto'}}), ...
                struct('Id', 'boltSpec', 'Title', 'Bolt Specs', 'Noun', 'bolt specs', ...
                    'Fields',  {{'origin', 'key', 'bolt', 'material', ...
                                 'ratedUltimateLoad', 'ratedYieldLoad', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Bolt', 'Material', ...
                                 'Rated ult (lbf)', 'Rated yield (lbf)', 'Source'}}, ...
                    'Widths',  {{62, 140, 110, 110, 95, 100, 'auto'}}), ...
                struct('Id', 'nut', 'Title', 'Nuts', 'Noun', 'nuts', ...
                    'Fields',  {{'origin', 'key', 'spec', 'thread', ...
                                 'nominalDiameter', 'tpi', 'height', ...
                                 'bearingDiameter', 'material', ...
                                 'ratedUltimateLoad', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Spec', 'Thread', ...
                                 'Nom dia (in)', 'TPI', 'Height (in)', ...
                                 'Bearing dia (in)', 'Material', ...
                                 'Rated ult (lbf)', 'Source'}}, ...
                    'Widths',  {{62, 130, 100, 110, 80, 40, 75, 100, 90, 95, 'auto'}}), ...
                struct('Id', 'washer', 'Title', 'Washers', 'Noun', 'washers', ...
                    ... % Geometry only -- no material and no rated load,
                    ... % which is why there is no strength column here.
                    'Fields',  {{'origin', 'key', 'spec', 'sizeCode', ...
                                 'nominalDiameter', 'innerDiameter', ...
                                 'outerDiameter', 'thickness', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Spec', 'Size code', ...
                                 'Nom dia (in)', 'ID (in)', 'OD (in)', ...
                                 'Thickness (in)', 'Source'}}, ...
                    'Widths',  {{62, 130, 100, 75, 80, 75, 75, 90, 'auto'}}), ...
                struct('Id', 'insert', 'Title', 'Inserts', 'Noun', 'inserts', ...
                    ... % Tapped-hole geometry only -- no strength data
                    ... % exists to seed, because NASM33537 defers to
                    ... % Technical Bulletin 68-2 and 68-2 publishes charts
                    ... % rather than tables.
                    'Fields',  {{'origin', 'key', 'spec', 'thread', ...
                                 'nominalDiameter', 'tpi', ...
                                 'stiPitchDiameterMin', 'stiPitchDiameterMax', ...
                                 'stiMinorDiameterMin', 'stiMinorDiameterMax', ...
                                 'tapMajorDiameterMax', 'countersinkDiameterMin', ...
                                 'countersinkDiameterMax', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Spec', 'Thread', ...
                                 'Nom dia (in)', 'TPI', ...
                                 'STI pitch min (in)', 'STI pitch max (in)', ...
                                 'STI minor min (in)', 'STI minor max (in)', ...
                                 'Tap major max (in)', 'C''sink min (in)', ...
                                 'C''sink max (in)', 'Source'}}, ...
                    'Widths',  {{62, 130, 100, 110, 80, 40, 105, 105, 105, 105, 105, 100, 100, 'auto'}})];
        end

        function spec = specFor(entityId)
            specs = gui2.HardwareLibraryPage.sectionSpecs();
            spec  = specs(strcmp({specs.Id}, entityId));
            spec  = spec(1);
        end

        function row = entryRow(e, fields)
            %ENTRYROW  One library entry struct -> one table row.
            %   Missing and empty optional fields render as an em dash, so
            %   "this entry has no Fbry" and "this entry has Fbry = 0" never
            %   look alike. Numeric values stay NUMERIC rather than being
            %   formatted to char, because uitable right-aligns numbers and
            %   sorts them as numbers — a column of strings sorts 10 before 9.
            row = cell(1, numel(fields));
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(e, f) && ~isempty(e.(f))
                    v = e.(f);
                    if isnumeric(v) && isscalar(v)
                        if isnan(v)
                            row{i} = '—';   % NaN sentinel = unconfigured
                        else
                            row{i} = v;
                        end
                    else
                        row{i} = char(string(v));
                    end
                else
                    row{i} = '—';
                end
            end
        end
    end

    % ---- Test seams -------------------------------------------------------
    methods
        function t = sectionTable(obj, entityId)
            %SECTIONTABLE  One section's uitable, by entity token.
            %   Keyed rather than indexed: the tab order is a private
            %   constant a test cannot reach, and an index would silently
            %   follow a reordering to the wrong table.
            %
            %   char() on every dynamic field access in this block: the
            %   struct keys are char, callers pass string, and mixing the
            %   two is the kind of thing that works until it does not.
            t = obj.Tables.(char(entityId));
        end

        function d = filterDropDown(obj)
            d = obj.FilterDropDown;
        end

        function g = tabGroup(obj)
            g = obj.TabGroup;
        end

        function s = countText(obj, entityId)
            s = obj.CountLabels.(char(entityId)).Text;
        end

        function v = detailText(obj)
            v = obj.DetailArea.Value;
        end

        function selectRow(obj, entityId, row)
            %SELECTROW  Select a row AND run the real selection callback.
            %   Assigning Selection fires nothing, so a test that only set
            %   it would assert against a detail area nobody had updated.
            obj.Tables.(char(entityId)).Selection = row;
            obj.onRowSelected(char(entityId), struct('Selection', row));
        end

        function ids = sectionIds(~)
            specs = gui2.HardwareLibraryPage.sectionSpecs();
            ids   = string({specs.Id});
        end

        function n = buildCount(obj)
            n = obj.BuildCount;
        end

        function n = refreshCount(obj)
            n = obj.RefreshCount;
        end
    end
end
