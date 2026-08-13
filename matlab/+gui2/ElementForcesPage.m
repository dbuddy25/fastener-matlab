classdef ElementForcesPage < gui2.Page
    %ELEMENTFORCESPAGE  Imported FE forces, one load case per sheet.
    %   Bulk step 3 of 4 (the rail owns the 1-4 numbering, GUI2_SPEC.md
    %   Section 3).
    %
    %   PARSING IS NOT THIS PAGE'S JOB. data.loadElementWorkbook is the
    %   tested reader and the GUI adds no parsing of its own. What the page
    %   adds is everything a reader has no place to do: Merge vs Replace
    %   against existing data, per-load-case Scale and Reversible (post-load
    %   mutation, and USER INPUT that never comes from the file), the
    %   min/max range preview, and continuous cross-validation against the
    %   Element Mapping — which needs two datasets at once.
    %
    %   THE UNITS BANNER IS PERMANENT, ON PURPOSE. Misread force units are
    %   the highest-consequence silent error in this application: nothing
    %   downstream can detect that a column of newtons was read as pounds,
    %   and every margin comes back confident and wrong. A banner that is
    %   always there is the correct amount of paranoia.
    %
    %   THE MIN/MAX COLUMNS ARE THE SANITY CHECK, not decoration. A units
    %   or column-order error shows instantly as an absurd range — an FZ
    %   range of 1e7 is visible at a glance in a way that a correct-looking
    %   table of numbers is not.
    %
    %   A ROW CARRIES NO JOINT AND NO PATTERN. Both belong to the mapping,
    %   which is the only place a user can set either; the workbook format
    %   has neither column. This page therefore reads Mapping but never
    %   writes it.
    %
    %   Backed by AppState.Elements. Listens to ElementsChanged — which the
    %   mapping fires too, and must, because the cross-check below the
    %   tables is a statement about both datasets and goes stale the moment
    %   either moves.

    properties (Access = private)
        Grid
        SummaryTable
        Banner              % empty-state note, shares the summary's cell
        DetailHeader
        DetailTable
        CrossCheck

        ImportButton
        TemplateButton
        ClearButton

        % Selected load case tracked by NAME, not row index: an import
        % reorders rows and an index would follow the wrong case.
        SelectedCase (1,1) string = ""

        StyleEmptyCase
    end

    properties (Constant, Access = private)
        % Summary columns after the four fixed ones, in Forces field order.
        Components = ["FX", "FY", "FZ", "MX", "MY", "MZ"]

        % Sheets an import is EXPECTED to skip. The exported template ships
        % a README, so treating its absence from the data as a warning
        % would train the user to ignore warnings.
        InstructionSheets = ["README", "Notes", "Instructions"]
    end

    methods
        function obj = ElementForcesPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "ElementForces";
        end

        function t = title(~)
            t = "Element Forces";
        end

        function s = railStatus(obj)
            if isempty(obj.State.Elements.Rows)
                s = "";
            else
                s = "loaded";
            end
        end

        function build(obj, parent)
            g = uigridlayout(parent, [6 1]);
            g.RowHeight   = {'fit', 30, '1x', 22, '1x', 96};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 6;
            obj.Grid = g;

            % The units statement rides in the PAGE banner rather than a
            % second coloured bar of its own: GUI2_SPEC.md Section 12 puts
            % emphasis in the words, not in per-page colours, and two
            % stacked banners cost the tables the height they need.
            obj.addBanner(g, 1, 1, ...
                ['Bulk step 3 of 4. UNITS ARE FIXED: imported forces are ' ...
                 'read as lbf and moments as in-lb — there is no unit ' ...
                 'toggle, so do not import N / N-m data. One load case ' ...
                 'per sheet, and the sheet name becomes the load case ' ...
                 'name. Scale and Reversible are set here, never in the ' ...
                 'file. Forces are saved in the case file.']);

            obj.StyleEmptyCase = uistyle( ...
                'BackgroundColor', gui2.palette('bannerWarnBg'), ...
                'FontColor',       gui2.palette('bannerWarnFg'), ...
                'FontWeight',      'bold');

            obj.buildToolbar(g, 2);
            obj.buildSummary(g, 3);

            obj.DetailHeader = uilabel(g, 'Text', '', 'FontWeight', 'bold');
            obj.DetailHeader.Layout.Row    = 4;
            obj.DetailHeader.Layout.Column = 1;

            obj.buildDetail(g, 5);
            obj.buildCrossCheck(g, 6);

            obj.listenTo('ElementsChanged', @() obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            %REFRESH  Sync the whole page from AppState. The ONLY populate
            %   path. Never marks dirty — repopulating is not editing.
            if isempty(obj.SummaryTable) || ~isvalid(obj.SummaryTable)
                return
            end
            obj.renderSummary();
            obj.renderDetail();
            obj.renderCrossCheck();
        end
    end

    % ---- Construction -----------------------------------------------------
    methods (Access = private)
        function buildToolbar(obj, parent, row)
            bar = uigridlayout(parent, [1 4]);
            bar.Layout.Row    = row;
            bar.Layout.Column = 1;
            bar.RowHeight     = {'1x'};
            bar.ColumnWidth   = {'fit', 'fit', 'fit', '1x'};
            bar.Padding       = [0 0 0 0];
            bar.ColumnSpacing = 8;

            b = uibutton(bar, 'push', 'Text', 'Import Workbook...', ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onImport());
            b.Tooltip = ['Import a force workbook (.xlsx): ONE LOAD CASE ' ...
                'PER SHEET, the sheet name is the load case name. Each ' ...
                'sheet carries element_id, FX FY FZ (lbf), MX MY MZ ' ...
                '(in-lb) and nothing else. Export Template... writes the ' ...
                'shape.'];
            b.Layout.Row = 1;  b.Layout.Column = 1;
            obj.ImportButton = b;

            b = uibutton(bar, 'push', 'Text', 'Export Template...', ...
                'ButtonPushedFcn', @(~, ~) obj.onExportTemplate());
            b.Tooltip = ['Write a correctly-shaped workbook with a README ' ...
                'and two example load-case sheets — the answer to "what ' ...
                'shape does it want?".'];
            b.Layout.Row = 1;  b.Layout.Column = 2;
            obj.TemplateButton = b;

            b = uibutton(bar, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(~, ~) obj.onClearAll());
            b.Tooltip = ['Remove every imported force row and load case, ' ...
                'including their Scale and Reversible settings (asks ' ...
                'first). The element mapping is untouched.'];
            b.Layout.Row = 1;  b.Layout.Column = 3;
            obj.ClearButton = b;
        end

        function buildSummary(obj, parent, row)
            t = uitable(parent);
            t.Layout.Row    = row;
            t.Layout.Column = 1;
            t.ColumnName    = [{'Load Case', 'Scale', 'Rev.', '# Elems'}, ...
                obj.rangeColumnNames()];
            t.RowName       = {};
            t.ColumnFormat  = [{'char', 'numeric', 'logical', 'numeric'}, ...
                repmat({'numeric'}, 1, 12)];
            % Only Scale and Rev. are editable. Everything else is derived
            % from the imported rows, and an editable derived cell is a
            % promise the page cannot keep.
            t.ColumnEditable = [false true true false, false(1, 12)];
            t.ColumnWidth    = [{140, 55, 45, 60}, repmat({68}, 1, 12)];
            t.SelectionType  = 'row';
            t.CellEditCallback     = @(~, evt) obj.onSummaryEdited(evt);
            t.SelectionChangedFcn  = @(~, evt) obj.onSummarySelected(evt);
            t.Tooltip = ['One row per load case. Scale multiplies every ' ...
                'displayed value AND is handed to the engine at bulk-run ' ...
                'time; Rev. means the load can act in both directions (±), ' ...
                'so tension is taken as |axial|. The min/max columns are ' ...
                'the data sanity check — a units or column error shows ' ...
                'instantly as an absurd range. Select a row for its ' ...
                'per-element forces below.'];
            obj.SummaryTable = t;

            banner = uilabel(parent, 'Text', ['No element forces ' ...
                'imported yet. Import a workbook with one load case per ' ...
                'sheet — the sheet name becomes the load case name, and ' ...
                'each sheet lists element_id, FX FY FZ, MX MY MZ, one row ' ...
                'per element. Export Template... writes that shape for ' ...
                'you. Forces are lbf and moments in-lb; Scale and ' ...
                'Reversible are set here per load case after import, ' ...
                'never in the file.']);
            banner.Layout.Row        = row;
            banner.Layout.Column     = 1;
            banner.WordWrap          = 'on';
            banner.VerticalAlignment = 'top';
            banner.BackgroundColor   = gui2.palette('bannerInfoBg');
            banner.FontColor         = gui2.palette('bannerInfoFg');
            banner.Visible           = 'off';
            obj.Banner = banner;
        end

        function buildDetail(obj, parent, row)
            t = uitable(parent);
            t.Layout.Row     = row;
            t.Layout.Column  = 1;
            t.ColumnName     = [{'Element ID'}, cellstr(obj.Components)];
            t.RowName        = {};
            t.ColumnFormat   = [{'char'}, repmat({'numeric'}, 1, 6)];
            t.ColumnEditable = false(1, 7);
            t.ColumnWidth    = [{110}, repmat({'auto'}, 1, 6)];
            t.ColumnSortable = true;
            t.Tooltip = ['Per-element forces for the selected load case, ' ...
                'with that case''s scale already applied (lbf / in-lb). ' ...
                'Click a column header to sort. Read-only: forces come ' ...
                'from the workbook, and editing them here would put a ' ...
                'number in the analysis that is in no file.'];
            obj.DetailTable = t;
        end

        function buildCrossCheck(obj, parent, row)
            ta = uitextarea(parent);
            ta.Layout.Row    = row;
            ta.Layout.Column = 1;
            ta.Editable      = 'off';
            ta.Tooltip = ['Continuous cross-check against the Element ' ...
                'Mapping. This is what catches a mapping and a force file ' ...
                'that do not describe the same model — it updates ' ...
                'whenever either changes.'];
            obj.CrossCheck = ta;
        end
    end

    % ---- Rendering --------------------------------------------------------
    methods (Access = private)
        function renderSummary(obj)
            cases = obj.cases();
            nc    = numel(cases);
            d     = cell(nc, 16);
            emptyRows = zeros(1, 0);

            for i = 1:nc
                c    = cases(i);
                M    = obj.scaledMatrix(c.Name, c.Scale);
                nEl  = size(M, 1);
                if nEl == 0
                    emptyRows(end + 1) = i; %#ok<AGROW>
                    lo = NaN(1, 6);
                    hi = NaN(1, 6);
                else
                    lo = min(M, [], 1);
                    hi = max(M, [], 1);
                end
                span = cell(1, 12);
                span(1:2:end) = num2cell(lo);
                span(2:2:end) = num2cell(hi);
                d(i, :) = [{char(gui2.ElementForcesPage.displayName(c.Name)), ...
                            c.Scale, logical(c.Reversible), nEl}, span];
            end

            obj.SummaryTable.Data      = d;
            obj.SummaryTable.Selection = [];

            % A load case with no element rows — an empty sheet, or every
            % row removed — is amber. A "0" in the count column scans like
            % any other number, and an empty load case must never read as
            % a populated one.
            try
                removeStyle(obj.SummaryTable);
                if ~isempty(emptyRows)
                    addStyle(obj.SummaryTable, obj.StyleEmptyCase, ...
                        'row', emptyRows);
                end
            catch
                % Styling unavailable — the count column still says 0 and
                % the cross-check pane still reports it.
            end

            hasRows = ~isempty(obj.rows());
            obj.SummaryTable.Visible = matlab.lang.OnOffSwitchState(hasRows);
            obj.Banner.Visible       = matlab.lang.OnOffSwitchState(~hasRows);

            % Restore the selection BY NAME, and fall back to the first
            % case so the detail pane below is never blankly unexplained
            % while data exists.
            idx = obj.caseIndex(obj.SelectedCase);
            if isempty(idx) && nc > 0
                idx = 1;
            end
            if isempty(idx)
                obj.SelectedCase = "";
            else
                obj.SelectedCase = cases(idx).Name;
                if hasRows
                    obj.SummaryTable.Selection = idx;
                end
            end
        end

        function renderDetail(obj)
            idx = obj.caseIndex(obj.SelectedCase);
            if isempty(obj.rows()) || isempty(idx)
                if isempty(obj.rows())
                    obj.DetailHeader.Text = ...
                        'No load case to show — import forces first.';
                else
                    obj.DetailHeader.Text = ['Select a load case above ' ...
                        'to see its element forces.'];
                end
                obj.DetailHeader.FontColor = gui2.palette('mutedText');
                obj.DetailTable.Data = cell(0, 7);
                return
            end

            cases = obj.cases();
            c     = cases(idx);
            M     = obj.scaledMatrix(c.Name, c.Scale);
            ids   = obj.caseElementIds(c.Name);
            d     = cell(numel(ids), 7);
            for k = 1:numel(ids)
                d(k, :) = [{char(ids(k))}, num2cell(M(k, :))];
            end
            obj.DetailTable.Data = d;

            rev = '';
            if c.Reversible
                rev = ' (± Reversible)';
            end
            obj.DetailHeader.Text = sprintf( ...
                'Load Case: %s (×%g)%s — %d element(s)', ...
                gui2.ElementForcesPage.displayName(c.Name), c.Scale, ...
                rev, numel(ids));
            obj.DetailHeader.FontColor = gui2.palette('defaultText');
        end

        function renderCrossCheck(obj)
            %RENDERCROSSCHECK  The mapping <-> forces agreement statement.
            %   Four visually distinct outcomes, because the dangerous one
            %   is not "no data" — it is a file that parses perfectly and
            %   describes a different model. That must not read as success.
            [sev, lines] = obj.crossCheckReport();
            obj.CrossCheck.Value = cellstr(lines(:));
            switch sev
                case "error"
                    obj.CrossCheck.BackgroundColor = gui2.palette('bannerErrorBg');
                    obj.CrossCheck.FontColor       = gui2.palette('bannerErrorFg');
                    obj.CrossCheck.FontWeight      = 'bold';
                case "warn"
                    obj.CrossCheck.BackgroundColor = gui2.palette('bannerWarnBg');
                    obj.CrossCheck.FontColor       = gui2.palette('bannerWarnFg');
                    obj.CrossCheck.FontWeight      = 'bold';
                case "info"
                    obj.CrossCheck.BackgroundColor = gui2.palette('bannerInfoBg');
                    obj.CrossCheck.FontColor       = gui2.palette('bannerInfoFg');
                    obj.CrossCheck.FontWeight      = 'normal';
                otherwise   % "ok"
                    obj.CrossCheck.BackgroundColor = gui2.palette('fieldBg');
                    obj.CrossCheck.FontColor       = gui2.palette('mutedText');
                    obj.CrossCheck.FontWeight      = 'normal';
            end
        end
    end

    % ---- The cross-check, as data -----------------------------------------
    methods (Access = private)
        function [sev, lines] = crossCheckReport(obj)
            %CROSSCHECKREPORT  severity + lines. Separated from rendering so
            %   the wording and the escalation are testable without reading
            %   colours off a widget.
            %
            %   ELEMENT IDS ARE COMPARED AS STRINGS. The old build split
            %   force ids into numeric and non-numeric and called the
            %   second group "can never be mapped", because the mapping
            %   keyed on integers. Mapping ids are strings now, so that
            %   category no longer exists — any id in a force file can be
            %   mapped, and an id that appears in one and not the other is
            %   just a gap.
            mapIds = obj.mappedIds();
            fIds   = obj.forceIds();
            cases  = obj.cases();

            if isempty(mapIds) && isempty(fIds)
                sev   = "info";
                lines = "Cross-check vs Element Mapping: nothing to " + ...
                    "compare yet — no mapping rows (step 2) and no " + ...
                    "forces (step 3).";
                return
            end
            if isempty(fIds)
                sev   = "warn";
                lines = string(sprintf(['Cross-check vs Element Mapping: %d ' ...
                    'element(s) are mapped but no forces are imported — ' ...
                    'the bulk run has nothing to analyze until this ' ...
                    'step is done.'], numel(mapIds)));
                return
            end
            if isempty(mapIds)
                sev   = "warn";
                lines = string(sprintf(['Cross-check vs Element Mapping: forces ' ...
                    'cover %d element(s) but the mapping is empty — map ' ...
                    'them on Element Mapping (step 2; "Import IDs from ' ...
                    'Forces" bootstraps it).'], numel(fIds)));
                return
            end

            sev   = "ok";
            lines = strings(1, 0);
            covered = ismember(mapIds, fIds);

            if ~any(covered)
                sev = "error";
                lines(end + 1) = sprintf(['DATA MISMATCH: the imported ' ...
                    'forces cover NONE of the %d mapped element(s) — the ' ...
                    'mapping and the force file do not describe the same ' ...
                    'model. Check the element ID columns.'], numel(mapIds));
            end

            miss = mapIds(~covered);
            if ~isempty(miss) && any(covered)
                lines(end + 1) = sprintf(['%d mapped element(s) have no ' ...
                    'forces (no results for them)%s'], numel(miss), ...
                    gui2.ElementForcesPage.idList(miss));
            end
            extra = fIds(~ismember(fIds, mapIds));
            if ~isempty(extra)
                lines(end + 1) = sprintf(['%d element(s) in the forces ' ...
                    'are not in the mapping (they will be skipped)%s'], ...
                    numel(extra), gui2.ElementForcesPage.idList(extra));
            end
            for i = 1:numel(cases)
                caseIds = obj.caseElementIds(cases(i).Name);
                cmiss   = mapIds(~ismember(mapIds, caseIds));
                if ~isempty(cmiss)
                    lines(end + 1) = sprintf(['load case "%s": missing ' ...
                        '%d mapped element(s)%s'], ...
                        gui2.ElementForcesPage.displayName(cases(i).Name), ...
                        numel(cmiss), ...
                        gui2.ElementForcesPage.idList(cmiss)); %#ok<AGROW>
                end
            end

            if isempty(lines)
                lines = string(sprintf(['Cross-check vs Element Mapping: ' ...
                    'mapping and forces cover the same %d element(s) ' ...
                    'across %d load case(s) — no gaps.'], ...
                    numel(mapIds), numel(cases)));
                return
            end
            if sev == "error"
                return   % DATA MISMATCH leads. See below.
            end
            % The counting header goes in front of a list of GAPS, where no
            % single line is the headline. It must NOT go in front of a
            % DATA MISMATCH: that line says the mapping and the force file
            % describe different models, and pushing a generic "4 issue(s)"
            % above it demotes the one finding that matters to item one of
            % four. Softening the worst message is the failure mode this
            % whole pane exists to prevent.
            sev   = "warn";
            lines = [sprintf('Cross-check vs Element Mapping: %d issue(s):', ...
                numel(lines)), lines];
        end
    end

    % ---- Reading state ----------------------------------------------------
    methods (Access = private)
        function r = rows(obj)
            r = obj.State.Elements.Rows;
        end

        function c = cases(obj)
            c = obj.State.Elements.Cases;
        end

        function idx = caseIndex(obj, name)
            %CASEINDEX  Load-case record index for a name ([] = none).
            %   Case-insensitive, matching the joint-name convention.
            idx = [];
            c = obj.cases();
            if isempty(c) || strlength(name) == 0
                return
            end
            hit = find(strcmpi(string({c.Name}), name), 1);
            if ~isempty(hit)
                idx = hit;
            end
        end

        function mask = caseMask(obj, name)
            r = obj.rows();
            if isempty(r)
                mask = false(1, 0);
                return
            end
            mask = strcmpi(string({r.LoadCaseName}), name);
        end

        function ids = caseElementIds(obj, name)
            r = obj.rows();
            if isempty(r)
                ids = strings(1, 0);
                return
            end
            ids = string({r(obj.caseMask(name)).ElementId});
        end

        function ids = forceIds(obj)
            r = obj.rows();
            if isempty(r)
                ids = strings(1, 0);
                return
            end
            ids = unique(string({r.ElementId}), 'stable');
        end

        function ids = mappedIds(obj)
            m = obj.State.Mapping;
            if isempty(m)
                ids = strings(1, 0);
                return
            end
            ids = unique(string({m.ElementID}), 'stable');
        end

        function M = scaledMatrix(obj, name, scale)
            %SCALEDMATRIX  One load case's rows -> N x 6, times its scale.
            %   THE ONLY place display scaling happens. This is
            %   PRESENTATION, not analysis: the stored rows stay unscaled,
            %   and at bulk-run time the same scale is handed to the engine
            %   as each row's ScaleFactor, which engine.loadCaseFromForces
            %   applies. So the screen matches what the engine will use
            %   without the GUI doing analysis math of its own.
            r   = obj.rows();
            idx = find(obj.caseMask(name));
            M   = zeros(numel(idx), 6);
            for k = 1:numel(idx)
                F = r(idx(k)).Forces;
                M(k, :) = [F.FX, F.FY, F.FZ, F.MX, F.MY, F.MZ];
            end
            M = M * scale;
        end

        function fig = figureHandle(obj)
            fig = ancestor(obj.Root, 'figure');
        end
    end

    % ---- Writing state ----------------------------------------------------
    methods (Access = private)
        function commit(obj, st, statusMsg)
            %COMMIT  THE write path: state, dirty, status.
            %   The summary table reports edits through CellEditCallback,
            %   which Page.bindEdit does not reach, so the dirty flag is
            %   set here rather than by the funnel.
            obj.State.Elements = st;    % fires ElementsChanged -> refresh
            obj.State.markDirty();
            if nargin > 2 && strlength(statusMsg) > 0
                obj.setStatus(statusMsg);
            end
        end
    end

    % ---- Editing ----------------------------------------------------------
    methods (Access = private)
        function onSummaryEdited(obj, evt)
            %ONSUMMARYEDITED  Scale / Reversible -> the load-case record.
            %   Both are real analysis inputs, not display preferences:
            %   they are saved in the case file and handed to the engine.
            st = obj.State.Elements;
            try
                r = evt.Indices(1);
                c = evt.Indices(2);
                if r < 1 || r > numel(st.Cases)
                    error('gui2:ElementForcesPage:staleRow', ...
                        'Stale table row — the view will refresh.');
                end
                switch c
                    case 2
                        v = double(evt.NewData);
                        if ~isscalar(v) || ~isfinite(v)
                            error('gui2:ElementForcesPage:badScale', ...
                                'Scale must be a finite number.');
                        end
                        if v < 0
                            error('gui2:ElementForcesPage:badScale', ...
                                ['Scale must not be negative. Use the ' ...
                                 'Rev. flag for a load that acts both ' ...
                                 'ways — a negative scale would flip the ' ...
                                 'sign of every component instead.']);
                        end
                        st.Cases(r).Scale = v;
                    case 3
                        st.Cases(r).Reversible = ...
                            gui2.ElementForcesPage.isTicked(evt.NewData);
                    otherwise
                        error('gui2:ElementForcesPage:readOnly', ...
                            'Column %d is derived from the imported rows.', c);
                end
                % Keep the detail pane on the row being edited — that is
                % where the user is looking.
                obj.SelectedCase = st.Cases(r).Name;
            catch err
                uialert(obj.figureHandle(), err.message, 'Edit rejected');
                obj.refresh();
                return
            end
            obj.commit(st);
        end

        function onSummarySelected(obj, evt)
            %ONSUMMARYSELECTED  Row selection -> the detail pane.
            %   Selection must never dirty the case (GUI2_HARVEST A4), so
            %   this re-renders the detail only and does not commit.
            sel = evt.Selection;
            if isempty(sel)
                return   % keep the last shown case; never blank the pane
            end
            c = obj.cases();
            r = sel(1);
            if r >= 1 && r <= numel(c)
                obj.SelectedCase = c(r).Name;
                obj.renderDetail();
            end
        end
    end

    % ---- Import / template / clear ----------------------------------------
    methods (Access = private)
        function onImport(obj)
            %ONIMPORT  Pick a file, then hand off. The picker is SEPARATED
            %   from startImport because uigetfile is a blocking native
            %   dialog: a test that pressed this button would hang rather
            %   than fail, so everything worth testing lives past it.
            [f, p] = uigetfile({'*.xlsx', 'Force workbooks (*.xlsx)'}, ...
                'Import Force Workbook');
            if isequal(f, 0)
                return
            end
            obj.startImport(string(fullfile(p, f)));
        end

        function startImport(obj, file)
            [~, name, ext] = fileparts(file);
            f = char(name + ext);
            try
                [el, info] = data.loadElementWorkbook(file);
            catch err
                uialert(obj.figureHandle(), sprintf(['Could not import ' ...
                    '"%s":\n\n%s\n\nExpected a .xlsx workbook with one ' ...
                    'load case per sheet (the sheet name is the load ' ...
                    'case name), each sheet carrying element_id, FX, FY, ' ...
                    'FZ, MX, MY, MZ. Export Template... writes that ' ...
                    'shape. Nothing was changed.'], f, err.message), ...
                    'Import failed');
                return
            end

            notes = gui2.ElementForcesPage.triage(info);

            if isempty(el)
                % Sheets parsed, zero usable rows. THE dangerous case: it
                % did not throw, so nothing else will say it failed.
                msg = sprintf(['"%s" parsed %d force sheet(s) but 0 ' ...
                    'usable rows.\n\nRows with a blank element_id are ' ...
                    'skipped by the reader — check that column.'], ...
                    f, info.ParsedSheetCount);
                if ~isempty(notes.All)
                    msg = sprintf('%s\n\n%s', msg, ...
                        char(strjoin(notes.All, newline)));
                end
                uialert(obj.figureHandle(), msg, ...
                    'Import Force Workbook', 'Icon', 'error');
                return
            end

            if isempty(obj.rows())
                obj.applyImport(el, info, notes, "Merge");
                return
            end
            uiconfirm(obj.figureHandle(), sprintf(['%d force row(s) are ' ...
                'already loaded.\n\nMerge keeps them — and the ' ...
                'per-load-case Scale and Reversible settings — updating ' ...
                'rows that match on element and load case. Replace ' ...
                'clears everything first.'], numel(obj.rows())), ...
                'Import Force Workbook', ...
                'Options',       {'Merge', 'Replace', 'Cancel'}, ...
                'DefaultOption', 'Merge', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.applyImport(el, info, notes, ...
                    string(evt.SelectedOption)));
        end

        function applyImport(obj, el, info, notes, mode)
            if mode == "Cancel"
                return
            end
            if mode == "Replace"
                st = gui2.AppState.emptyElements();
            else
                st = obj.State.Elements;
            end

            added   = 0;
            updated = 0;
            for i = 1:numel(el)
                id = string(el(i).ElementId);
                lc = string(el(i).LoadCaseName);
                hit = [];
                if ~isempty(st.Rows)
                    hit = find(strcmpi(string({st.Rows.ElementId}), id) & ...
                               strcmpi(string({st.Rows.LoadCaseName}), lc), 1);
                end
                row = gui2.AppState.elementRow(id, lc, el(i).Forces);
                if isempty(hit)
                    st.Rows(end + 1) = row; %#ok<AGROW>
                    added = added + 1;
                else
                    st.Rows(hit) = row;
                    updated = updated + 1;
                end
                % A load case seen for the first time starts at the
                % defaults. On Merge an existing record KEEPS its
                % user-edited scale and flag — the file has no say in
                % either, and silently resetting them would change results.
                if isempty(st.Cases) || ...
                        ~any(strcmpi(string({st.Cases.Name}), lc))
                    st.Cases(end + 1) = gui2.AppState.elementCase(lc); %#ok<AGROW>
                end
            end

            obj.commit(st);
            obj.reportImport(added, updated, info, notes);
        end

        function reportImport(obj, added, updated, info, notes)
            msg  = sprintf(['Imported %d row(s) (%d updated) from %d ' ...
                'load-case sheet(s).'], added + updated, updated, ...
                info.ParsedSheetCount);
            icon = 'success';

            % Coverage rides in the import report itself, not only in the
            % cross-check pane: a file that parses cleanly but describes a
            % different model is the failure most likely to be believed.
            mapIds = obj.mappedIds();
            if ~isempty(mapIds)
                nCov = sum(ismember(mapIds, obj.forceIds()));
                if nCov == 0
                    msg = sprintf(['%s\n\nWARNING: these forces cover ' ...
                        'NONE of the %d mapped element(s) — check that ' ...
                        'the element IDs match the mapping.'], ...
                        msg, numel(mapIds));
                    icon = 'warning';
                else
                    msg = sprintf(['%s\nCovers %d of %d mapped ' ...
                        'element(s) — see the cross-check for gaps.'], ...
                        msg, nCov, numel(mapIds));
                end
            end
            if ~isempty(notes.Warnings)
                msg = sprintf('%s\n\n%s', msg, ...
                    char(strjoin(notes.Warnings, newline)));
                icon = 'warning';
            end
            if ~isempty(notes.Neutral)
                msg = sprintf('%s\n\n%s', msg, ...
                    char(strjoin(notes.Neutral, newline)));
            end
            uialert(obj.figureHandle(), msg, 'Import Force Workbook', ...
                'Icon', icon);
        end

        function onExportTemplate(obj)
            [f, p] = uiputfile('*.xlsx', 'Export Force Workbook Template', ...
                'force_workbook_template.xlsx');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));
            try
                gui2.ElementForcesPage.writeTemplate(file);
            catch err
                uialert(obj.figureHandle(), sprintf( ...
                    'Could not write "%s":\n%s', file, err.message), ...
                    'Export failed');
                return
            end
            obj.setStatus(sprintf(['Wrote %s (README + one load case ' ...
                'per sheet).'], file));
        end

        function onClearAll(obj)
            n = numel(obj.rows());
            if n == 0
                obj.setStatus('No element forces are loaded.');
                return
            end
            uiconfirm(obj.figureHandle(), sprintf(['Remove all %d force ' ...
                'row(s) across %d load case(s), including their Scale ' ...
                'and Reversible settings? The element mapping is ' ...
                'untouched.'], n, numel(obj.cases())), ...
                'Clear Element Forces', ...
                'Options',       {'Clear All', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.onClearAllAnswered(evt, n));
        end

        function onClearAllAnswered(obj, evt, n)
            if ~strcmp(evt.SelectedOption, 'Clear All')
                return
            end
            obj.SelectedCase = "";
            obj.commit(gui2.AppState.emptyElements(), ...
                sprintf('Cleared %d force row(s).', n));
        end
    end

    % ---- Pure helpers -----------------------------------------------------
    methods (Static, Access = private)
        function names = rangeColumnNames()
            c = gui2.ElementForcesPage.Components;
            names = cell(1, 12);
            for i = 1:6
                names{2 * i - 1} = char(c(i) + " Min");
                names{2 * i}     = char(c(i) + " Max");
            end
        end

        function s = displayName(name)
            %DISPLAYNAME  Blank load-case name -> "(unnamed)".
            %   Never silently empty: a blank row in the summary reads as a
            %   rendering fault rather than as a sheet with no name.
            s = string(name);
            if strlength(strtrim(s)) == 0
                s = "(unnamed)";
            end
        end

        function s = idList(ids)
            %IDLIST  ": a, b, c" for <= 5 ids, "" beyond.
            %   Listing 200 ids is not a message, it is a wall; past five
            %   the caller's count stands alone.
            if numel(ids) <= 5
                s = ": " + strjoin(string(ids), ", ");
            else
                s = "";
            end
        end

        function tf = isTicked(v)
            tf = isequal(v, true) || ...
                (isnumeric(v) && isscalar(v) && v ~= 0);
        end

        function notes = triage(info)
            %TRIAGE  Per-sheet import notes, split by whether they matter.
            %   An instructions sheet is EXPECTED to be skipped — the
            %   exported template ships a README — so it is mentioned
            %   neutrally and never escalates the icon. Any other skipped
            %   sheet is a warning with its reason, because a load-case
            %   sheet the user misnamed must not vanish looking like
            %   success. A sheet that parsed but carried no rows is the
            %   third category: it still declares a load case, so the
            %   emptiness stays visible instead of being dropped.
            warnings = strings(1, 0);
            neutral  = strings(1, 0);
            empties  = strings(1, 0);
            for i = 1:numel(info.Sheets)
                sh = info.Sheets(i);
                if ~sh.Parsed
                    if any(strcmpi(sh.Name, ...
                            gui2.ElementForcesPage.InstructionSheets))
                        neutral(end + 1) = sprintf(['sheet "%s" is an ' ...
                            'instructions sheet (not imported)'], ...
                            sh.Name); %#ok<AGROW>
                    else
                        warnings(end + 1) = sprintf('sheet "%s" skipped: %s', ...
                            sh.Name, sh.SkipReason); %#ok<AGROW>
                    end
                elseif sh.RowCount == 0
                    empties(end + 1) = sh.Name; %#ok<AGROW>
                elseif sh.SkippedRowCount > 0
                    warnings(end + 1) = sprintf(['sheet "%s": %d row(s) ' ...
                        'skipped (content but no element_id)'], ...
                        sh.Name, sh.SkippedRowCount); %#ok<AGROW>
                end
            end
            if ~isempty(empties)
                warnings(end + 1) = sprintf(['%d sheet(s) declared a load ' ...
                    'case but contained no element rows: %s'], ...
                    numel(empties), strjoin("""" + empties + """", ", "));
            end
            notes = struct('Warnings', [], 'Neutral', [], 'All', []);
            notes.Warnings = warnings;
            notes.Neutral  = neutral;
            notes.All      = [warnings, neutral];
        end

        function writeTemplate(file)
            %WRITETEMPLATE  README + two example load-case sheets.
            %   SHEET NAME = LOAD CASE NAME is the one thing a user has to
            %   know, so the data sheets carry deliberately generic names
            %   that read as the placeholders they are, and the README says
            %   to rename them. Data sheets are pure data — guidance lives
            %   in the README, because a banner row above the header is
            %   exactly what the reader would have to be taught to skip.
            readme = { ...
                'FORCE WORKBOOK TEMPLATE'; ...
                ''; ...
                'One load case per sheet. The SHEET NAME becomes the load case name -'; ...
                'rename "Load Case 1" / "Load Case 2" to your own load case names, and'; ...
                'add one sheet per additional load case.'; ...
                ''; ...
                'Each load-case sheet needs exactly these seven columns in row 1:'; ...
                '    element_id  - FE element ID'; ...
                '    FX, FY, FZ  - forces, in lbf'; ...
                '    MX, MY, MZ  - moments, in in-lb'; ...
                'Units matter: forces are lbf, moments are in-lb.'; ...
                ''; ...
                'Scale factor and reversible (+/-) are NOT set in this file - set them'; ...
                'per load case in the app, on the Element Forces page.'; ...
                ''; ...
                'The joint each element is analyzed as, and the bolt pattern it belongs'; ...
                'to, are set on the Element Mapping page - which is why there is no'; ...
                'joint column and no pattern column here.'; ...
                ''; ...
                'This README sheet is ignored on import.'};
            hdr = {'element_id', 'FX', 'FY', 'FZ', 'MX', 'MY', 'MZ'};
            case1 = [hdr; ...
                {1001, 1560,   0, 5590,  0, 0, 0}; ...
                {1002, -150, 200, -800, 10, 5, 0}];
            case2 = [hdr; ...
                {1001,  50, 120, 400, 0, 0, 0}; ...
                {1002, -25,  80, 150, 0, 0, 0}];
            if isfile(file)
                delete(file);   % start clean: exactly these three sheets
            end
            writecell(readme, file, 'Sheet', 'README');
            writecell(case1,  file, 'Sheet', 'Load Case 1');
            writecell(case2,  file, 'Sheet', 'Load Case 2');
        end
    end

    % ---- Test seams -------------------------------------------------------
    methods
        function t = summaryTable(obj)
            t = obj.SummaryTable;
        end

        function t = detailTable(obj)
            t = obj.DetailTable;
        end

        function l = detailHeader(obj)
            l = obj.DetailHeader;
        end

        function b = emptyBanner(obj)
            b = obj.Banner;
        end

        function a = crossCheckArea(obj)
            a = obj.CrossCheck;
        end

        function b = importButton(obj)
            b = obj.ImportButton;
        end

        function b = templateButton(obj)
            b = obj.TemplateButton;
        end

        function b = clearAllButton(obj)
            b = obj.ClearButton;
        end

        function answerClearAll(obj, choice)
            %ANSWERCLEARALL  Answer the Clear All confirm, as a user would.
            %   choice is 'Clear All' or 'Cancel'.
            %
        %   WHY A SEAM RATHER THAN A TEST THAT ANSWERS THE DIALOG.
        %   matlab.uitest cannot press a button inside a uiconfirm, so a
        %   test can only get as far as "the confirm opened". That leaves
        %   the branch that DOES THE WORK unexercised — and a test that
        %   presses Clear All and then asserts nothing was cleared passes
        %   just as happily when the button is wired to nothing at all.
        %   That is exactly the vacuous shape this file's other guards
        %   exist to avoid, so the continuation gets a seam of its own.
        %
        %   It calls the REAL production continuation with the field
        %   uiconfirm's CloseFcn actually delivers (evt.SelectedOption, a
        %   character vector matching one of Options). Nothing is
        %   re-implemented here: pass 'Cancel' and the same code that runs
        %   when a user cancels runs, so both branches are reachable.
            %
            %   n is recomputed here exactly as onClearAll computes it at
            %   dialog time, so the status line a test reads is the one a
            %   user would have seen.
            arguments
                obj
                choice (1,1) string
            end
            obj.onClearAllAnswered(struct('SelectedOption', char(choice)), ...
                numel(obj.rows()));
        end

        function [sev, lines] = crossCheck(obj)
            %CROSSCHECK  Severity + wording, without reading widget colours.
            [sev, lines] = obj.crossCheckReport();
        end

        function editCell(obj, row, col, value)
            %EDITCELL  Drive one summary cell edit as the widget would.
            obj.onSummaryEdited(struct( ...
                'Indices',      [row col], ...
                'PreviousData', [], ...
                'NewData',      value, ...
                'EditData',     value, ...
                'Error',        []));
        end

        function selectCase(obj, row)
            %SELECTCASE  Drive the summary selection as the widget would.
            %   Assigning Selection fires no callback, so the handler is
            %   called with the event it would have received.
            obj.SummaryTable.Selection = row;
            obj.onSummarySelected(struct('Selection', row));
        end

        function name = selectedCase(obj)
            name = obj.SelectedCase;
        end

        function importWorkbook(obj, file)
            %IMPORTWORKBOOK  Merge a workbook outright, no dialogs at all.
            [el, info] = data.loadElementWorkbook(file);
            obj.applyImport(el, info, ...
                gui2.ElementForcesPage.triage(info), "Merge");
        end

        function beginImport(obj, file)
            %BEGININPORT  The real import path minus the file picker, so a
            %   test can reach the Merge / Replace confirm that only
            %   appears when forces already exist.
            obj.startImport(file);
        end

        function writeTemplateTo(~, file)
            gui2.ElementForcesPage.writeTemplate(file);
        end

        function notes = importNotes(~, file)
            %IMPORTNOTES  The per-sheet triage a workbook would produce.
            %   Split into Warnings and Neutral, which is what decides
            %   whether the import report escalates its icon.
            [~, info] = data.loadElementWorkbook(file);
            notes = gui2.ElementForcesPage.triage(info);
        end
    end
end
