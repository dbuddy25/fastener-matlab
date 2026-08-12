classdef BulkAnalysisPage < gui2.Page
    %BULKANALYSISPAGE  Run every mapped element and read the answer.
    %   Bulk step 4 of 4. The page that closes the workflow: Defined
    %   Joints supplies the joints, Element Mapping says which joint each
    %   element is, Element Forces supplies the loads, and this runs them.
    %
    %   IT COMPUTES NOTHING. One engine call — engine.analyzeBulk — and
    %   everything on screen is a rendering of the table it returns. The
    %   only arithmetic here is display: which rows to show, the worst
    %   value down a column, and how a number is spelled. Formatting and
    %   the ratio/margin distinction live in gui2.MarginView, shared with
    %   the single-joint Results page so the two cannot drift.
    %
    %   MARGIN COLUMNS ARE DISCOVERED, NEVER HARDCODED. Everything between
    %   `Shear` and `WorstMargin` in the results table is a margin, which
    %   is why analyzeBulk puts `Warnings` last: a trailing column is
    %   invisible to this discovery and needs no change here. A new engine
    %   check appears on screen on its own.
    %
    %   THE CORE / SUPPLEMENTAL SPLIT IS ABOUT WHICH DOCUMENT REQUIRES A
    %   CHECK, NOT ABOUT WHAT IS DISPLAYED. Core are the checks 5020B
    %   itself gives equations for; supplemental are the ones it defers to
    %   TM-106943. The verdict line reports them separately so a bearing
    %   failure cannot read as 5020B non-compliance — and counts BOTH
    %   groups regardless of which columns are on screen. "Show
    %   Supplemental" is a width concession in a twenty-column grid, not a
    %   claim about scope.
    %
    %   WHAT MUST NEVER HAPPEN HERE, all of it learned the hard way:
    %     - the interaction ratio tested with a plain < 0. It passes iff
    %       R <= 1, the opposite direction, and a min() envelope across
    %       load cases would take its BEST case and hide a failure.
    %     - counts taken over the filtered view. The verdict is a
    %       statement about the run, not about what is on screen.
    %     - a cancelled run reading as a clean verdict.
    %     - the display filters reaching the export. Row scope and display
    %       scope are separate concerns and conflating them loses data
    %       silently.
    %
    %   Backed by AppState.BulkTable; listens to BulkChanged.

    properties (Access = private)
        Grid
        Banner              % dual role: empty-state info, then amber stale
        VerdictLabel
        TierTabs

        RunButton
        ExportButton
        JointFilter
        FailOnlyCheck
        SuppCheck
        CapCheck
        DrillButton

        SummaryTable        % tier 1
        CaseDropDown        % tier 2
        CaseTable           % tier 2
        ElementTable        % tier 3
        ElementTab          % tier 3's tab, so it can be brought to front

        % "Cancelled — 143 of 312 analyses complete", or "".
        CancelNote (1,1) string = ""

        % Why the last drill-down gave up, or "" if it worked. A button
        % press that does nothing and says nothing is a bug report with no
        % information in it — for the analyst and for the next test run
        % alike.
        DrillReason (1,1) string = ""

        StyleStale
        StyleFail
    end

    properties (Constant, Access = private)
        % The checks NASA-STD-5020B gives equations for. Everything else
        % the table carries is supplemental (TM-106943). InteractionR is
        % forced to the end of the core group: it reads on the opposite
        % scale, so it belongs where a reader meets it last.
        CoreChecks = ["TensionUlt", "TensionYield", "ShearUlt", ...
                      "Separation", "Slip", "InteractionR"]

        % Above this many rows, "Show all" asks first. A paint that large
        % looks like a hang, and the analyst has not asked for one.
        ShowAllConfirmAbove = 5000
    end

    methods
        function obj = BulkAnalysisPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "BulkAnalysis";
        end

        function t = title(~)
            t = "Bulk Analysis";
        end

        function s = railStatus(obj)
            if isempty(obj.State.BulkTable)
                s = "";
            elseif obj.State.BulkStale
                s = "stale";
            else
                s = "loaded";
            end
        end

        function build(obj, parent)
            g = uigridlayout(parent, [4 1]);
            g.RowHeight   = {'fit', 30, 24, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 6;
            obj.Grid = g;

            obj.Banner = uilabel(g, 'WordWrap', 'on', 'Text', '');
            obj.Banner.Layout.Row    = 1;
            obj.Banner.Layout.Column = 1;

            obj.StyleStale = uistyle('FontColor', gui2.palette('mutedText'));
            obj.StyleFail  = uistyle( ...
                'BackgroundColor', gui2.palette('tableFailBg'), ...
                'FontColor',       gui2.palette('statusFail'));

            obj.buildToolbar(g, 2);

            obj.VerdictLabel = uilabel(g, 'Text', '', ...
                'FontWeight', 'bold', 'FontSize', 13);
            obj.VerdictLabel.Layout.Row    = 3;
            obj.VerdictLabel.Layout.Column = 1;

            obj.buildTiers(g, 4);

            obj.listenTo('BulkChanged', @() obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            %REFRESH  Sync from AppState.BulkTable. The ONLY populate path,
            %   and it never marks anything dirty or stale — reading a
            %   stale flag must not set one (A3).
            if isempty(obj.SummaryTable) || ~isvalid(obj.SummaryTable)
                return
            end
            obj.renderBanner();
            obj.renderVerdict();
            obj.renderTiers();
            obj.renderEnables();
        end
    end

    % ---- Construction -----------------------------------------------------
    methods (Access = private)
        function buildToolbar(obj, parent, row)
            tb = uigridlayout(parent, [1 8]);
            tb.Layout.Row    = row;
            tb.Layout.Column = 1;
            tb.RowHeight     = {'1x'};
            tb.ColumnWidth   = {'fit', 'fit', 180, 'fit', 'fit', 'fit', ...
                                '1x', 'fit'};
            tb.Padding       = [0 0 0 0];
            tb.ColumnSpacing = 8;

            obj.RunButton = uibutton(tb, 'Text', 'Run Bulk Analysis', ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onRun());
            obj.RunButton.Layout.Row = 1;  obj.RunButton.Layout.Column = 1;
            obj.RunButton.Tooltip = ['Analyze every mapped element against ' ...
                'every imported load case (engine.analyzeBulk).'];

            obj.ExportButton = uibutton(tb, 'Text', 'Export...', ...
                'ButtonPushedFcn', @(~, ~) obj.onExport());
            obj.ExportButton.Layout.Row = 1;  obj.ExportButton.Layout.Column = 2;

            obj.JointFilter = uidropdown(tb, 'Items', {'All Joints'}, ...
                'ValueChangedFcn', @(~, ~) obj.renderAfterFilter());
            obj.JointFilter.Layout.Row = 1;  obj.JointFilter.Layout.Column = 3;
            obj.JointFilter.Tooltip = 'Narrow every tier to one joint (display only).';

            obj.FailOnlyCheck = uicheckbox(tb, 'Text', 'Failures Only', ...
                'Value', true, ...
                'ValueChangedFcn', @(~, ~) obj.onFailOnlyToggled());
            obj.FailOnlyCheck.Layout.Row = 1;  obj.FailOnlyCheck.Layout.Column = 4;
            obj.FailOnlyCheck.Tooltip = ['On by default: nobody scans ' ...
                'thousands of rows hunting a negative margin. Display ' ...
                'only — the counts above and the export are unaffected.'];

            obj.SuppCheck = uicheckbox(tb, 'Text', 'Show Supplemental', ...
                'Value', false, ...
                'ValueChangedFcn', @(~, ~) obj.renderAfterFilter());
            obj.SuppCheck.Layout.Row = 1;  obj.SuppCheck.Layout.Column = 5;
            obj.SuppCheck.Tooltip = ['Also show the TM-106943 columns ' ...
                '(bearing, tearout, thread checks). A WIDTH concession, ' ...
                'not a scope one — the counts include them either way, ' ...
                'and so does the export.'];

            obj.CapCheck = uicheckbox(tb, 'Text', 'Cap MS > 5', ...
                'Value', true, ...
                'ValueChangedFcn', @(~, ~) obj.renderAfterFilter());
            obj.CapCheck.Layout.Row = 1;  obj.CapCheck.Layout.Column = 6;
            obj.CapCheck.Tooltip = ['Display only — shows ">+5" so the eye ' ...
                'lands on near-failure margins. Does not affect the ' ...
                'analysis or the export.'];

            obj.DrillButton = uibutton(tb, ...
                'Text', 'Show in Single Joint Analysis', ...
                'ButtonPushedFcn', @(~, ~) obj.onDrillDown());
            obj.DrillButton.Layout.Row = 1;  obj.DrillButton.Layout.Column = 8;
            obj.DrillButton.Tooltip = ['Select a row on By Element to ' ...
                're-run that one element as a single joint and open it on ' ...
                'the Results page.'];
        end

        function buildTiers(obj, parent, row)
            obj.TierTabs = uitabgroup(parent);
            obj.TierTabs.Layout.Row    = row;
            obj.TierTabs.Layout.Column = 1;
            obj.TierTabs.SelectionChangedFcn = @(~, ~) obj.renderEnables();

            t1 = uitab(obj.TierTabs, 'Title', 'Joint Summary');
            obj.SummaryTable = gui2.BulkAnalysisPage.fillTable(t1);
            obj.SummaryTable.Tooltip = ['One row per joint: the worst value ' ...
                'of each check across that joint''s load cases. Click a ' ...
                'column header to rank by it.'];

            t2 = uitab(obj.TierTabs, 'Title', 'By Load Case');
            g2 = uigridlayout(t2, [2 1]);
            g2.RowHeight   = {26, '1x'};
            g2.ColumnWidth = {'1x'};
            g2.Padding     = [0 0 0 0];
            g2.RowSpacing  = 4;
            hg = uigridlayout(g2, [1 3]);
            hg.Layout.Row = 1;  hg.Layout.Column = 1;
            hg.RowHeight   = {'1x'};
            hg.ColumnWidth = {'fit', 220, '1x'};
            hg.Padding     = [0 0 0 0];
            lb = uilabel(hg, 'Text', 'Load Case:');
            lb.Layout.Row = 1;  lb.Layout.Column = 1;
            obj.CaseDropDown = uidropdown(hg, 'Items', {'-'}, ...
                'ValueChangedFcn', @(~, ~) obj.renderAfterFilter());
            obj.CaseDropDown.Layout.Row = 1;  obj.CaseDropDown.Layout.Column = 2;
            obj.CaseTable = uitable(g2);
            obj.CaseTable.Layout.Row    = 2;
            obj.CaseTable.Layout.Column = 1;
            obj.CaseTable.RowName       = {};
            obj.CaseTable.SelectionType = 'row';

            t3 = uitab(obj.TierTabs, 'Title', 'By Element');
            obj.ElementTab   = t3;
            obj.ElementTable = gui2.BulkAnalysisPage.fillTable(t3);
            obj.ElementTable.SelectionChangedFcn = @(~, ~) obj.renderEnables();
            obj.ElementTable.Tooltip = ['One row per element and load case. ' ...
                'Select a row and press Show in Single Joint Analysis to ' ...
                'see why it came out that way.'];
        end
    end

    % ---- Rendering --------------------------------------------------------
    methods (Access = private)
        function renderBanner(obj)
            rh = obj.Grid.RowHeight;
            if isempty(obj.State.BulkTable)
                obj.Banner.Text = ['No bulk results yet. 1 define joints ' ...
                    '(Defined Joints), 2 map element IDs to them (Element ' ...
                    'Mapping), 3 import forces (Element Forces), then ' ...
                    'press Run Bulk Analysis here.'];
                obj.Banner.BackgroundColor = gui2.palette('bannerInfoBg');
                obj.Banner.FontColor       = gui2.palette('bannerInfoFg');
                obj.Banner.FontWeight      = 'normal';
                obj.Banner.Visible         = 'on';
                rh{1} = 'fit';
            elseif obj.State.BulkStale
                obj.Banner.Text = ['STALE - an input has changed since ' ...
                    'this run. These numbers describe the case as it was, ' ...
                    'not as it is now. Run again to refresh them.'];
                obj.Banner.BackgroundColor = gui2.palette('bannerWarnBg');
                obj.Banner.FontColor       = gui2.palette('bannerWarnFg');
                obj.Banner.FontWeight      = 'bold';
                obj.Banner.Visible         = 'on';
                rh{1} = 'fit';
            else
                obj.Banner.Visible = 'off';
                rh{1} = 0;
            end
            obj.Grid.RowHeight = rh;
        end

        function renderVerdict(obj)
            %RENDERVERDICT  The split count, over the FULL result set.
            T = obj.State.BulkTable;
            if isempty(T)
                obj.VerdictLabel.Text = '';
                return
            end
            [core, supp] = obj.marginGroups();
            [coreFail, suppFail, errRows] = obj.failureMasks(T, core, supp);
            n = height(T);

            txt = sprintf(['%d joint(s) %s %d load case(s) = %d analyses ' ...
                '%s 5020B: %d PASS, %d FAIL | Supplemental: %d PASS, %d FAIL'], ...
                numel(unique(T.JointName)), char(215), ...
                numel(unique(T.LoadCase)), n, char(8212), ...
                nnz(~coreFail & ~errRows), nnz(coreFail), ...
                nnz(~suppFail & ~errRows), nnz(suppFail));
            if nnz(errRows) > 0
                txt = sprintf('%s | %d ERROR', txt, nnz(errRows));
            end
            if strlength(obj.CancelNote) > 0
                txt = sprintf('%s  [%s]', txt, obj.CancelNote);
            end
            obj.VerdictLabel.Text = txt;

            if obj.State.BulkStale
                obj.VerdictLabel.FontColor = gui2.palette('mutedText');
            elseif any(coreFail) || any(suppFail) || any(errRows)
                obj.VerdictLabel.FontColor = gui2.palette('statusFail');
            elseif strlength(obj.CancelNote) > 0
                % All-pass but INCOMPLETE. Amber, never green: a partial
                % run must not read as a clean full verdict.
                obj.VerdictLabel.FontColor = gui2.palette('statusWarn');
            else
                obj.VerdictLabel.FontColor = gui2.palette('statusPass');
            end
        end

        function renderAfterFilter(obj)
            %RENDERAFTERFILTER  A display control moved. Tables only.
            %   Emphatically NOT a refresh: filters never touch the verdict
            %   counts, and a display interaction must never dirty or stale
            %   anything (A4).
            obj.renderTiers();
            obj.renderEnables();
        end

        function onFailOnlyToggled(obj)
            %ONFAILONLYTOGGLED  Confirm before painting a very large table.
            T = obj.State.BulkTable;
            if obj.FailOnlyCheck.Value || isempty(T) || ...
                    height(T) <= obj.ShowAllConfirmAbove
                obj.renderAfterFilter();
                return
            end
            obj.FailOnlyCheck.Value = true;   % held until answered
            uiconfirm(obj.figureHandle(), sprintf( ...
                ['Show all %d rows?\n\nA table this size takes a moment ' ...
                 'to paint, and the failing rows are already in view.'], ...
                height(T)), 'Show all rows', ...
                'Options',       {'Show all', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.onShowAllAnswered(evt));
        end

        function onShowAllAnswered(obj, evt)
            if strcmp(evt.SelectedOption, 'Show all')
                obj.FailOnlyCheck.Value = false;
            end
            obj.renderAfterFilter();
        end

        function renderTiers(obj)
            T = obj.State.BulkTable;
            if isempty(T)
                obj.SummaryTable.Data = cell(0, 1);
                obj.CaseTable.Data    = cell(0, 1);
                obj.ElementTable.Data = cell(0, 1);
                obj.JointFilter.Items = {'All Joints'};
                obj.CaseDropDown.Items = {'-'};
                return
            end

            joints = unique(T.JointName, 'stable');
            obj.syncItems(obj.JointFilter, ...
                [{'All Joints'}, cellstr(joints(:)')]);
            cases = unique(T.LoadCase, 'stable');
            obj.syncItems(obj.CaseDropDown, cellstr(cases(:)'));

            shown  = obj.shownColumns();
            ratioM = gui2.MarginView.isRatio(shown);
            obj.renderElementTier(T, shown, ratioM);
            obj.renderSummaryTier(T, shown, ratioM);
            obj.renderCaseTier(T, shown, ratioM);
        end

        function renderElementTier(obj, T, shown, ratioM)
            keep = obj.jointMask(T);
            M    = obj.marginMatrix(T, shown);
            err  = obj.errorMask(T);
            [~, failM] = gui2.MarginView.passFail(M, ratioM);
            rowFail = any(failM, 2) | err;
            if obj.FailOnlyCheck.Value
                keep = keep & rowFail;
            end
            idx = find(keep);

            d = cell(numel(idx), 5 + numel(shown) + 1);
            for k = 1:numel(idx)
                r = idx(k);
                d(k, 1:5) = {char(T.ElementId(r)), char(T.JointName(r)), ...
                    char(T.LoadCase(r)), round(T.Axial(r), 1), ...
                    round(T.Shear(r), 1)};
                for c = 1:numel(shown)
                    if err(r)
                        d{k, 5 + c} = 'ERR';
                    else
                        d{k, 5 + c} = gui2.MarginView.cellText( ...
                            M(r, c), ratioM(c), obj.CapCheck.Value);
                    end
                end
                d{k, end} = char(T.Error(r));
            end
            obj.ElementTable.ColumnName = [ ...
                {'Element', 'Joint', 'Load Case', 'Axial', 'Shear'}, ...
                gui2.MarginView.headerText(shown), {'Error'}];
            obj.ElementTable.ColumnWidth = [{90, 140, 120, 70, 70}, ...
                repmat({100}, 1, numel(shown)), {'auto'}];
            obj.ElementTable.Data = d;
            obj.styleTable(obj.ElementTable, d, 6:5 + numel(shown));
        end

        function renderSummaryTier(obj, T, shown, ratioM)
            joints = unique(T.JointName, 'stable');
            keep   = obj.jointMask(T);
            M      = obj.marginMatrix(T, shown);
            err    = obj.errorMask(T);

            d = {};
            for j = 1:numel(joints)
                mask = keep & (T.JointName == joints(j));
                if ~any(mask)
                    continue
                end
                env = gui2.MarginView.envelope(M(mask, :), ratioM);
                [~, envFail] = gui2.MarginView.passFail(env, ratioM);
                hasErr = any(err(mask));
                if obj.FailOnlyCheck.Value && ~any(envFail) && ~hasErr
                    continue
                end
                row = cell(1, 3 + numel(shown) + 1);
                row(1:3) = {char(joints(j)), ...
                    round(max(T.Axial(mask), [], 'omitnan'), 1), ...
                    round(max(T.Shear(mask), [], 'omitnan'), 1)};
                for c = 1:numel(shown)
                    row{3 + c} = gui2.MarginView.cellText( ...
                        env(c), ratioM(c), obj.CapCheck.Value);
                end
                row{end} = char(obj.drivingCase(T, mask));
                d(end + 1, :) = row; %#ok<AGROW>
            end
            obj.SummaryTable.ColumnName = [{'Joint', 'Max Axial', 'Max Shear'}, ...
                gui2.MarginView.headerText(shown), {'Driving Load Case'}];
            obj.SummaryTable.ColumnWidth = [{160, 80, 80}, ...
                repmat({100}, 1, numel(shown)), {140}];
            obj.SummaryTable.Data = d;
            obj.styleTable(obj.SummaryTable, d, 4:3 + numel(shown));
        end

        function renderCaseTier(obj, T, shown, ratioM)
            sel    = string(obj.CaseDropDown.Value);
            joints = unique(T.JointName, 'stable');
            keep   = obj.jointMask(T) & (T.LoadCase == sel);
            M      = obj.marginMatrix(T, shown);
            err    = obj.errorMask(T);

            d = {};
            for j = 1:numel(joints)
                mask = keep & (T.JointName == joints(j));
                if ~any(mask)
                    continue
                end
                env = gui2.MarginView.envelope(M(mask, :), ratioM);
                [~, envFail] = gui2.MarginView.passFail(env, ratioM);
                if obj.FailOnlyCheck.Value && ~any(envFail) && ~any(err(mask))
                    continue
                end
                row = cell(1, 1 + numel(shown));
                row{1} = char(joints(j));
                for c = 1:numel(shown)
                    row{1 + c} = gui2.MarginView.cellText( ...
                        env(c), ratioM(c), obj.CapCheck.Value);
                end
                d(end + 1, :) = row; %#ok<AGROW>
            end
            obj.CaseTable.ColumnName = [{'Joint'}, ...
                gui2.MarginView.headerText(shown)];
            obj.CaseTable.ColumnWidth = [{160}, ...
                repmat({100}, 1, numel(shown))];
            obj.CaseTable.Data = d;
            obj.styleTable(obj.CaseTable, d, 2:1 + numel(shown));
        end

        function styleTable(obj, t, d, marginCols)
            %STYLETABLE  removeStyle first, then ONE batched addStyle per
            %   group (A8). Wrapped: styling is cosmetic and is never
            %   allowed to break the numbers.
            try
                removeStyle(t);
                if isempty(d)
                    return
                end
                if obj.State.BulkStale
                    % Muted throughout rather than pass/fail coloured — a
                    % stale table must not present a confident verdict.
                    addStyle(t, obj.StyleStale);
                    return
                end
                cells = zeros(0, 2);
                for c = marginCols
                    for r = 1:size(d, 1)
                        if gui2.BulkAnalysisPage.readsAsFailure(d{r, c})
                            cells(end + 1, :) = [r, c]; %#ok<AGROW>
                        end
                    end
                end
                if ~isempty(cells)
                    addStyle(t, obj.StyleFail, 'cell', cells);
                end
            catch
                % Styling unavailable — the verdict line and the banner
                % still say what happened.
            end
        end

        function renderEnables(obj)
            fresh = ~isempty(obj.State.BulkTable) && ~obj.State.BulkStale;
            obj.ExportButton.Enable = matlab.lang.OnOffSwitchState(fresh);
            if fresh
                obj.ExportButton.Tooltip = ['Write the COMPLETE result ' ...
                    'set. On-screen filters and the display cap never ' ...
                    'narrow the export.'];
            else
                obj.ExportButton.Tooltip = 'Run the bulk analysis first.';
            end
            obj.DrillButton.Enable = matlab.lang.OnOffSwitchState( ...
                fresh && ~isempty(obj.selectedElementRow()));
        end

        function syncItems(~, dd, items)
            %SYNCITEMS  Replace a dropdown's items, keeping the selection
            %   when it survives. Programmatic sets fire no callback.
            prev = dd.Value;
            dd.Items = items;
            if any(strcmp(items, prev))
                dd.Value = prev;
            end
        end
    end

    % ---- Reading the results table ----------------------------------------
    methods (Access = private)
        function [core, supp] = marginGroups(obj)
            %MARGINGROUPS  Discover the margin columns POSITIONALLY.
            %   Everything between Shear and WorstMargin. Never a hardcoded
            %   list, so an engine check added tomorrow shows up here on
            %   its own — which is exactly why analyzeBulk documents
            %   Warnings as a trailing column.
            core = strings(1, 0);
            supp = strings(1, 0);
            T = obj.State.BulkTable;
            if isempty(T)
                return
            end
            vars = string(T.Properties.VariableNames);
            iS = find(vars == "Shear", 1);
            iW = find(vars == "WorstMargin", 1);
            if isempty(iS) || isempty(iW) || iW <= iS + 1
                return
            end
            mv   = vars(iS + 1:iW - 1);
            isCore = ismember(mv, gui2.BulkAnalysisPage.CoreChecks);
            core = mv(isCore);
            % InteractionR last: it reads on the opposite scale, so a
            % reader should meet it after the margins, not among them.
            core = [core(core ~= "InteractionR"), core(core == "InteractionR")];
            supp = mv(~isCore);
        end

        function cols = shownColumns(obj)
            [core, supp] = obj.marginGroups();
            if obj.SuppCheck.Value
                cols = [core, supp];
            else
                cols = core;
            end
        end

        function M = marginMatrix(~, T, cols)
            M = zeros(height(T), numel(cols));
            for c = 1:numel(cols)
                M(:, c) = T.(char(cols(c)));
            end
        end

        function mask = errorMask(~, T)
            mask = strlength(string(T.Error)) > 0;
        end

        function mask = jointMask(obj, T)
            sel = string(obj.JointFilter.Value);
            if sel == "All Joints"
                mask = true(height(T), 1);
            else
                mask = (T.JointName == sel);
            end
        end

        function [coreFail, suppFail, errRows] = failureMasks(obj, T, core, supp)
            %FAILUREMASKS  Per-row failure, by group, over the WHOLE table.
            errRows  = obj.errorMask(T);
            coreFail = obj.groupFailure(T, core) & ~errRows;
            suppFail = obj.groupFailure(T, supp) & ~errRows;
        end

        function f = groupFailure(obj, T, cols)
            if isempty(cols)
                f = false(height(T), 1);
                return
            end
            M = obj.marginMatrix(T, cols);
            [~, failM] = gui2.MarginView.passFail(M, ...
                gui2.MarginView.isRatio(cols));
            f = any(failM, 2);
        end

        function name = drivingCase(~, T, mask)
            %DRIVINGCASE  The load case with the worst margin for a joint.
            %   From the engine's own WorstMargin column, not re-derived
            %   from the shown subset — a minimum over what happens to be
            %   on screen can overstate the margin.
            wm  = T.WorstMargin(mask);
            lcs = T.LoadCase(mask);
            if all(isnan(wm))
                name = "-";
                return
            end
            [~, k] = min(wm, [], 'omitnan');
            name = lcs(k);
        end

        function r = selectedElementRow(obj)
            %SELECTEDELEMENTROW  Index into the CURRENT By Element view.
            r = [];
            if isempty(obj.ElementTable) || ~isvalid(obj.ElementTable)
                return
            end
            sel = obj.ElementTable.Selection;
            if isempty(sel) || isempty(obj.ElementTable.Data)
                return
            end
            r = sel(1);
        end

        function fig = figureHandle(obj)
            fig = ancestor(obj.Root, 'figure');
        end
    end

    % ---- The gate and the assembly ----------------------------------------
    methods (Access = private)
        function [problems, pages] = gateProblems(obj)
            %GATEPROBLEMS  Every reason the run cannot start, each with the
            %   page that fixes it. The workflow's ONLY hard gate: order is
            %   suggested everywhere else and enforced only here, at the
            %   moment of truth, always pointing at the fix.
            problems = strings(1, 0);
            pages    = strings(1, 0);

            lib = obj.State.JointLibrary;
            m   = gui2.AppState.normalizeMapping(obj.State.Mapping);
            el  = obj.State.Elements;

            if isempty(lib)
                problems(end + 1) = "No joints are defined — save at least " + ...
                    "one named joint on Defined Joints (step 1).";
                pages(end + 1) = "DefinedJoints";
            end
            if isempty(m)
                problems(end + 1) = "The element mapping is empty — map FE " + ...
                    "element IDs to joints on Element Mapping (step 2).";
                pages(end + 1) = "ElementMapping";
            end
            if isempty(el.Rows)
                problems(end + 1) = "No element forces are imported — " + ...
                    "import a force workbook on Element Forces (step 3).";
                pages(end + 1) = "ElementForces";
            end
            if isempty(m) || isempty(lib)
                return
            end

            names = string({m.JointName});
            blank = strlength(strtrim(names)) == 0;
            if any(blank)
                problems(end + 1) = sprintf(['%d mapping row(s) have no ' ...
                    'joint assigned — assign one on Element Mapping.'], nnz(blank));
                pages(end + 1) = "ElementMapping";
            end
            libNames = string({lib.Name});
            unknown  = unique(names(~blank & ~ismember(lower(names), lower(libNames))));
            if ~isempty(unknown)
                problems(end + 1) = sprintf(['%d mapped joint name(s) are ' ...
                    'not in the joint library — define them or fix the ' ...
                    'mapping.'], numel(unknown));
                pages(end + 1) = "DefinedJoints";
            end
        end

        function [elements, missing, skipped] = assemble(obj)
            %ASSEMBLE  Mapping x forces -> engine.analyzeBulk's contract.
            %   THE MAPPING IS THE AUTHORITY on both the joint and the bolt
            %   pattern; the force row supplies only the loads. Scale and
            %   Reversible come from the row's load-case record, which is
            %   where the user set them.
            elements = struct('ElementId', {}, 'JointName', {}, ...
                'LoadCaseName', {}, 'PatternId', {}, 'Forces', {}, ...
                'ScaleFactor', {}, 'Reversible', {});
            m  = gui2.AppState.normalizeMapping(obj.State.Mapping);
            el = obj.State.Elements;

            mapIds = string({m.ElementID});
            skipped = strings(1, 0);
            for r = 1:numel(el.Rows)
                row = el.Rows(r);
                k = find(mapIds == row.ElementId, 1);   % first row wins
                if isempty(k)
                    skipped(end + 1) = row.ElementId; %#ok<AGROW>
                    continue
                end
                c = obj.caseRecord(el, row.LoadCaseName);
                elements(end + 1) = struct( ...
                    'ElementId',    row.ElementId, ...
                    'JointName',    m(k).JointName, ...
                    'LoadCaseName', row.LoadCaseName, ...
                    'PatternId',    m(k).PatternId, ...
                    'Forces',       row.Forces, ...
                    'ScaleFactor',  c.Scale, ...
                    'Reversible',   c.Reversible); %#ok<AGROW>
            end
            skipped = unique(skipped, 'stable');

            forceIds = strings(1, 0);
            if ~isempty(el.Rows)
                forceIds = unique(string({el.Rows.ElementId}));
            end
            missing = mapIds(~ismember(mapIds, forceIds));
        end

        function c = caseRecord(~, el, name)
            c = gui2.AppState.elementCase(name);   % defaults 1 / false
            if isempty(el.Cases)
                return
            end
            k = find(strcmpi(string({el.Cases.Name}), name), 1);
            if ~isempty(k)
                c = el.Cases(k);
            end
        end
    end

    % ---- Running ----------------------------------------------------------
    methods (Access = private)
        function onRun(obj)
            [problems, pages] = obj.gateProblems();
            if ~isempty(problems)
                obj.showGate(problems, pages);
                return
            end
            [elements, missing, skipped] = obj.assemble();
            if isempty(elements)
                obj.showGate("The imported forces cover NONE of the mapped " + ...
                    "elements — the mapping and the force file do not " + ...
                    "describe the same model. Check the element ID columns.", ...
                    ["ElementMapping", "ElementForces"]);
                return
            end

            warn = strings(1, 0);
            if ~isempty(missing)
                warn(end + 1) = sprintf(['%d mapped element(s) have no ' ...
                    'force data — they will produce no results.'], numel(missing));
            end
            if ~isempty(skipped)
                warn(end + 1) = sprintf(['%d force element(s) are not in ' ...
                    'the mapping — they will be skipped.'], numel(skipped));
            end
            if isempty(warn)
                obj.runElements(elements);
                return
            end
            uiconfirm(obj.figureHandle(), sprintf('%s\n\nContinue with %d analyses?', ...
                strjoin(warn, newline), numel(elements)), ...
                'Bulk Analysis — data gaps', ...
                'Options',       {'Continue', 'Cancel'}, ...
                'DefaultOption', 'Continue', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.onGapsAnswered(elements, evt));
        end

        function onGapsAnswered(obj, elements, evt)
            if strcmp(evt.SelectedOption, 'Continue')
                obj.runElements(elements);
            end
        end

        function showGate(obj, problems, pages)
            %SHOWGATE  Every problem, plus a way to go fix it.
            %   Continuation-passing: the option string names a page and
            %   the CloseFcn navigates. A blocking confirm here would
            %   deadlock the test suite rather than fail it.
            pages = unique(pages, 'stable');
            labels = cell(1, numel(pages) + 1);
            for i = 1:numel(pages)
                labels{i} = char("Go to " + ...
                    gui2.BulkAnalysisPage.pageLabel(pages(i)));
            end
            labels{end} = 'Close';
            % sprintf, not `newline + newline`: those are CHARS, and
            % adding them gives char(20), not a blank line.
            uiconfirm(obj.figureHandle(), ...
                char(strjoin(problems, sprintf('\n\n'))), ...
                'Cannot run the bulk analysis', ...
                'Options',       labels, ...
                'DefaultOption', numel(labels), ...
                'CancelOption',  numel(labels), ...
                'CloseFcn', @(~, evt) obj.onGateAnswered(pages, labels, evt));
        end

        function onGateAnswered(obj, pages, labels, evt)
            k = find(strcmp(labels, evt.SelectedOption), 1);
            if ~isempty(k) && k <= numel(pages)
                obj.goToPage(pages(k));
            end
        end

        function runElements(obj, elements, progress)
            %RUNELEMENTS  Slice, run, reassemble, commit.
            %   SLICED PURELY FOR PROGRESS AND CANCELLATION. The key is
            %   (load case, pattern) — analyzeBulk's OWN pattern key — so a
            %   slice never splits a joint-slip aggregation group, and the
            %   result is reassembled in the original element order. The
            %   sliced run is numerically identical to one call; every
            %   number still comes from the engine.
            %
            %   No arguments block: an `arguments` default cannot refer to
            %   another input, and the real progress dialog needs the
            %   element count to size itself.
            if nargin < 3
                progress = obj.progressDialog(numel(elements));
            end
            jl = obj.stampedLibrary();
            if isempty(jl)
                return
            end
            n    = numel(elements);
            grp  = gui2.BulkAnalysisPage.sliceKeys(elements);
            nGrp = max(grp);

            parts   = {};
            partIdx = {};
            done    = 0;
            cancelled = false;
            try
                for s = 1:nGrp
                    if progress.Cancelled()
                        cancelled = true;
                        break
                    end
                    idx = reshape(find(grp == s), 1, []);
                    parts{end + 1}   = engine.analyzeBulk(jl, ...
                        elements(idx), obj.State.Factors); %#ok<AGROW>
                    partIdx{end + 1} = idx; %#ok<AGROW>
                    done = done + numel(idx);
                    progress.Update(done, n);
                end
            catch err
                % A failed run must not leave a confident verdict on
                % screen: flag the previous table stale rather than
                % replacing or clearing it (A3).
                obj.State.markBulkStale();
                uialert(obj.figureHandle(), err.message, 'Bulk analysis failed');
                return
            end

            if isempty(parts)
                obj.setStatus(sprintf(['Cancelled before any analyses ran ' ...
                    '(0 of %d) — previous results, if any, are unchanged.'], n));
                return
            end

            allIdx   = [partIdx{:}];
            Tall     = vertcat(parts{:});
            [~, ord] = sort(allIdx);
            if cancelled
                obj.CancelNote = string(sprintf( ...
                    'Cancelled — %d of %d analyses complete', done, n));
            else
                obj.CancelNote = "";
            end
            obj.State.setBulkTable(Tall(ord, :));   % fires BulkChanged
            obj.setStatus(char(obj.VerdictLabel.Text));
        end

        function p = progressDialog(obj, n)
            %PROGRESSDIALOG  The real, cancellable progress reporter.
            %   Returned as a pair of closures rather than the dialog
            %   itself so a test can hand runElements a silent one — a
            %   stray modal dialog blocks every gesture that follows.
            d = uiprogressdlg(obj.figureHandle(), 'Title', 'Bulk Analysis', ...
                'Message', sprintf('0/%d analyses', n), 'Value', 0, ...
                'Cancelable', 'on');
            closer = onCleanup(@() delete(d(isvalid(d))));
            p = struct( ...
                'Update',    @(done, total) gui2.BulkAnalysisPage.tick(d, done, total), ...
                'Cancelled', @() isvalid(d) && d.CancelRequested, ...
                'Closer',    closer);
        end

        function jl = stampedLibrary(obj)
            %STAMPEDLIBRARY  The defined joints with the GLOBAL service
            %   temperatures on them. Skipping this is how the thermal
            %   preload term silently went to zero on the single-joint path
            %   once already.
            jl = obj.State.JointLibrary;
            try
                for i = 1:numel(jl)
                    jl(i).Joint = engine.applyTemperatures( ...
                        jl(i).Joint, obj.State.Settings);
                end
            catch err
                uialert(obj.figureHandle(), err.message, ...
                    'Service temperatures rejected');
                jl = [];
            end
        end
    end

    % ---- Export and drill-down --------------------------------------------
    methods (Access = private)
        function onExport(obj)
            T = obj.State.BulkTable;
            if isempty(T) || obj.State.BulkStale
                return
            end
            [f, p] = uiputfile({'*.xlsx', 'Excel workbook'; '*.csv', 'CSV'}, ...
                'Export Bulk Results', 'bulk-margins.xlsx');
            if isequal(f, 0)
                return
            end
            try
                % T, not the filtered view. The on-screen filters and the
                % display cap are screen concessions; the workbook is the
                % record.
                written = report.exportResults(T, string(fullfile(p, f)), ...
                    Notes = obj.runNotes());
            catch err
                uialert(obj.figureHandle(), err.message, 'Export failed');
                return
            end
            uialert(obj.figureHandle(), sprintf(['Exported the COMPLETE ' ...
                'result set — %d row(s) — to:\n%s\n\nOn-screen filters ' ...
                'and the display cap do not narrow the export.'], ...
                height(T), written), 'Export complete', 'Icon', 'success');
            obj.setStatus(sprintf('Wrote %s', written));
        end

        function [joint, lc] = singleJointInputs(~, joint, e, elements)
            %SINGLEJOINTINPUTS  One element's joint and load case, exactly
            %   as the batch built them.
            %
            %   THE JOINT-MODE SLIP STEP IS WHY THIS EXISTS. Eq. 84 needs
            %   the whole bolt PATTERN's totals, and engine.analyze refuses
            %   to run a SlipMode.Joint joint without them — so a
            %   drill-down that handed it one element's loads threw, and
            %   the button did nothing. Rebuilding the pattern here (and
            %   applying the same nf check, and the same downgrade when it
            %   fails) is what makes the drill-down show the row it was
            %   opened from rather than a different analysis of it.
            %
            %   model.Joint is a value class, so the SlipMode downgrade
            %   below touches this copy only; the library is untouched.
            lc = engine.loadCaseFromForces(e.Forces, joint.BoltAxis, ...
                Name = e.LoadCaseName, ScaleFactor = e.ScaleFactor, ...
                Reversible = e.Reversible);
            if joint.SlipMode ~= model.SlipMode.Joint
                return
            end
            mask = gui2.BulkAnalysisPage.patternMask(elements, e);
            if nnz(mask) == joint.BoltCount
                [PtJ, PsJ] = engine.jointPatternTotals( ...
                    elements(mask), joint.BoltAxis);
                lc.JointTensileLimitLoad = PtJ;
                lc.JointShearLimitLoad   = PsJ;
            else
                % Same nf mismatch the batch reports: slip stays
                % NotEvaluated rather than being computed on a pattern the
                % elements do not describe.
                joint.SlipMode = model.SlipMode.Ignored;
            end
        end

        function giveUpDrilling(obj, why)
            %GIVEUPDRILLING  Record it, show it, and stop.
            obj.DrillReason = string(why);
            uialert(obj.figureHandle(), char("Cannot open that element: " + ...
                obj.DrillReason + "."), 'Show in Single Joint Analysis');
            obj.setStatus("Could not open that element: " + obj.DrillReason);
        end

        function notes = runNotes(obj)
            %RUNNOTES  What the workbook says about the run that made it.
            T = obj.State.BulkTable;
            notes = sprintf(['Bulk run: %d analyses over %d joint(s) and ' ...
                '%d load case(s).'], height(T), ...
                numel(unique(T.JointName)), numel(unique(T.LoadCase)));
            if strlength(obj.CancelNote) > 0
                notes = [notes, "PARTIAL RUN — " + obj.CancelNote + ...
                    ". Elements not analyzed are absent from this file."];
            end
            notes = [string(notes), ...
                "All 15 computed checks are exported. NOT a complete " + ...
                "NASA-STD-5020B assessment: yield and separation under " + ...
                "COMBINED loading (TFSR 11) are required and not implemented."];
        end

        function onDrillDown(obj)
            %ONDRILLDOWN  Re-run one element as a single joint.
            %   Rebuilt from the CURRENT inputs rather than kept from the
            %   run — which is safe precisely because this is disabled
            %   while the results are stale, so the two agree.
            %
            %   EVERY EXIT RECORDS WHY. A button that does nothing and says
            %   nothing is a bug report with no information in it — the
            %   analyst gets no reason and neither does a failing test.
            obj.DrillReason = "";
            r = obj.selectedElementRow();
            if isempty(r)
                obj.giveUpDrilling("no row is selected on By Element");
                return
            end
            d  = obj.ElementTable.Data;
            id = string(d{r, 1});
            lc = string(d{r, 3});

            try
                [elements, ~, ~] = obj.assemble();
                k = find(string({elements.ElementId}) == id & ...
                         string({elements.LoadCaseName}) == lc, 1);
                if isempty(k)
                    obj.giveUpDrilling(sprintf(['element %s / load case %s ' ...
                        'is no longer in the mapping and forces'], id, lc));
                    return
                end
                e  = elements(k);
                jl = obj.stampedLibrary();
                if isempty(jl)
                    obj.giveUpDrilling("the service temperatures were rejected");
                    return
                end
                j = find(strcmpi(string({jl.Name}), e.JointName), 1);
                if isempty(j)
                    obj.giveUpDrilling(sprintf( ...
                        'joint "%s" is no longer defined', e.JointName));
                    return
                end

                [joint, lc] = obj.singleJointInputs(jl(j).Joint, e, elements);
                inputs = struct('Joint', joint, 'LoadCase', lc, ...
                    'Factors', obj.State.Factors);
                res = engine.analyze(inputs.Joint, inputs.LoadCase, inputs.Factors);
            catch err
                % Wrapped WIDE on purpose: an uncaught error in a button
                % callback prints to the Command Window and looks, from the
                % app, exactly like the button doing nothing.
                obj.giveUpDrilling(string(err.message));
                return
            end
            % DELIBERATELY does not write State.Joint / State.LoadCase.
            % Results renders from the Result and its recorded inputs, so
            % nothing here needs them — and writing them would silently
            % replace whatever the analyst had on Joint Config, which is
            % the loss Defined Joints' Load asks about before doing.
            obj.State.setResult(res, inputs);
            obj.goToPage("Results");
            obj.setStatus(sprintf('Element %s, load case %s.', id, lc));
        end
    end

    % ---- Pure helpers -----------------------------------------------------
    methods (Static, Access = private)
        function t = fillTable(parent)
            g = uigridlayout(parent, [1 1]);
            g.RowHeight   = {'1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [0 0 0 0];
            t = uitable(g);
            t.Layout.Row     = 1;
            t.Layout.Column  = 1;
            t.RowName        = {};
            t.SelectionType  = 'row';
            t.ColumnSortable = true;   % free criticality ranking
        end

        function grp = sliceKeys(elements)
            %SLICEKEYS  Group index per element: (load case, pattern key),
            %   the pattern key being PatternId falling back to JointName —
            %   analyzeBulk's own rule. Grouping for identity only.
            sep = string(char(30));   % unit separator; never in a name
            n = numel(elements);
            keys = strings(1, n);
            for k = 1:n
                keys(k) = string(elements(k).LoadCaseName) + sep + ...
                    gui2.BulkAnalysisPage.patternKey(elements(k));
            end
            [~, ~, grp] = unique(keys, 'stable');
        end

        function mask = patternMask(elements, e)
            %PATTERNMASK  The bolt pattern one element belongs to.
            %   analyzeBulk's own three conditions: same pattern key
            %   (PatternId, falling back to JointName), same joint, same
            %   load case. Written out rather than reusing sliceKeys
            %   because that one deliberately omits the joint — it groups
            %   for progress, where a collision costs nothing, and this
            %   groups for a MARGIN, where it would be wrong.
            n = numel(elements);
            mask = false(1, n);
            key = gui2.BulkAnalysisPage.patternKey(e);
            for i = 1:n
                mask(i) = gui2.BulkAnalysisPage.patternKey(elements(i)) == key ...
                    && string(elements(i).JointName)    == string(e.JointName) ...
                    && string(elements(i).LoadCaseName) == string(e.LoadCaseName);
            end
        end

        function k = patternKey(e)
            k = string(e.PatternId);
            if strlength(k) == 0
                k = string(e.JointName);
            end
        end

        function tick(d, done, total)
            if ~isvalid(d)
                return
            end
            d.Value   = min(1, done / max(1, total));
            d.Message = sprintf('%d/%d analyses', done, total);
            drawnow limitrate
        end

        function tf = readsAsFailure(txt)
            %READSASFAILURE  Does this rendered cell say "fail"?
            %   Reads the TEXT the engine's number produced rather than
            %   re-thresholding the number: the cell was formatted by
            %   MarginView from a value already classified there, and a
            %   second threshold here is exactly the drift A2 forbids.
            s = string(txt);
            tf = s == "ERR" || startsWith(s, "-");
            if startsWith(s, "R = ")
                v = str2double(extractBetween(s, "R = ", " ("));
                tf = isscalar(v) && ~isnan(v) && v > 1;
            end
        end

        function s = pageLabel(pageId)
            switch pageId
                case "DefinedJoints",  s = "Defined Joints";
                case "ElementMapping", s = "Element Mapping";
                case "ElementForces",  s = "Element Forces";
                otherwise,             s = pageId;
            end
        end
    end

    % ---- Test seams -------------------------------------------------------
    methods
        function t = summaryTable(obj)
            t = obj.SummaryTable;
        end

        function t = caseTable(obj)
            t = obj.CaseTable;
        end

        function t = elementTable(obj)
            t = obj.ElementTable;
        end

        function l = verdictLabel(obj)
            l = obj.VerdictLabel;
        end

        function b = banner(obj)
            b = obj.Banner;
        end

        function b = runButton(obj)
            b = obj.RunButton;
        end

        function b = exportButton(obj)
            b = obj.ExportButton;
        end

        function b = drillButton(obj)
            b = obj.DrillButton;
        end

        function c = failOnlyCheck(obj)
            c = obj.FailOnlyCheck;
        end

        function c = suppCheck(obj)
            c = obj.SuppCheck;
        end

        function c = capCheck(obj)
            c = obj.CapCheck;
        end

        function d = jointFilter(obj)
            d = obj.JointFilter;
        end

        function d = caseDropDown(obj)
            d = obj.CaseDropDown;
        end

        function [problems, pages] = gate(obj)
            [problems, pages] = obj.gateProblems();
        end

        function [elements, missing, skipped] = assembled(obj)
            [elements, missing, skipped] = obj.assemble();
        end

        function [core, supp] = groups(obj)
            [core, supp] = obj.marginGroups();
        end

        function runSilently(obj)
            %RUNSILENTLY  The run path with NO progress dialog.
            %   uiprogressdlg is modal, and a stray one blocks every
            %   gesture that follows — the same hazard as a file picker.
            %   Tests drive the run through here; one test presses the
            %   real button to prove the gate is wired.
            [problems, ~] = obj.gateProblems();
            if ~isempty(problems)
                return
            end
            elements = obj.assemble();
            if isempty(elements)
                return
            end
            obj.runElements(elements, gui2.BulkAnalysisPage.nullProgress());
        end

        function cancelAfter(obj, nSlices)
            %CANCELAFTER  Run, cancelling once nSlices have completed.
            %   For the partial-run verdict, which has no other way in.
            elements = obj.assemble();
            counter  = struct('n', 0);
            p = struct( ...
                'Update',    @(done, total) [], ...
                'Cancelled', @() bump());
            obj.runElements(elements, p);
            function tf = bump()
                tf = counter.n >= nSlices;
                counter.n = counter.n + 1;
            end
        end

        function n = cancelNote(obj)
            n = obj.CancelNote;
        end

        function notes = exportNotes(obj)
            notes = obj.runNotes();
        end

        function selectElement(obj, row)
            %SELECTELEMENT  Select a By Element row, as a user would.
            %   Brings that tier to the front FIRST. A user cannot select a
            %   row on a tab they are not looking at, and a control on an
            %   unselected tab is not in a visible hierarchy — which is
            %   also what matlab.uitest refuses to drive.
            obj.TierTabs.SelectedTab = obj.ElementTab;
            obj.ElementTable.Selection = row;
            obj.renderEnables();
        end

        function tf = drillEnabled(obj)
            tf = logical(obj.DrillButton.Enable);
        end

        function why = drillReason(obj)
            %DRILLREASON  Why the last drill-down gave up, "" if it worked.
            why = obj.DrillReason;
        end

        function n = elementRowCount(obj)
            n = size(obj.ElementTable.Data, 1);
        end
    end

    methods (Static)
        function p = nullProgress()
            %NULLPROGRESS  A progress reporter that shows nothing and never
            %   cancels. Public so tests can hand it to runElements.
            p = struct('Update', @(done, total) [], 'Cancelled', @() false);
        end
    end
end
