classdef ResultsPage < gui2.Page
    %RESULTSPAGE  Render one engine.Result (GUI2_SPEC.md Section 8).
    %   THIS PAGE COMPUTES NOTHING. Every number, every pass/fail and every
    %   citation comes off the Result; the view formats and colours. That is
    %   the engine contract (Section 6) and it is what makes the displayed
    %   margins trustworthy: there is no second implementation to disagree
    %   with the first.
    %
    %   TWO ROWS ARE NOT MARGINS, and both are handled specially.
    %
    %   Separation-before-rupture carries NO NUMBER — it records which
    %   branch the tension check took (5020B Fig. 8). Listing it among
    %   margins is a category error the first build made; it leads the
    %   Analysis decisions section instead (Section 8.2).
    %
    %   Interaction reports a RATIO R, passing iff R <= 1 — the OPPOSITE
    %   direction from MS >= 0. It is last in the table and rendered with
    %   its criterion attached, "R = 0.86 (<= 1)", so the number can never
    %   be read as a margin. It is excluded from every comparison.
    %
    %   NO WORST-MARGIN HEADLINE. Result.WorstMargin and GoverningCheck span
    %   all fifteen checks, so either could name a row that is not in an
    %   eight-row table. Neither is displayed, and the view never recomputes
    %   a minimum over the displayed subset — that would be the view
    %   deriving a number, and it could overstate the margin (Section 2).
    %
    %   Backed by AppState.Result. Repaints on ResultChanged, which fires
    %   both for a fresh result and for markResultStale.

    properties (Constant, Access = private)
        % The eight table rows, in solver order, INTERACTION LAST.
        % Separation-before-rupture is deliberately absent: see the class
        % note and Section 8.2.
        TableRows = ["Tension-Ultimate", "Tension-Yield", "Shear-Ultimate", ...
                     "Separation", "Slip", "Bearing", "Shear-tearout", ...
                     "Interaction"]

        % The ninth displayed check. A decision, not a margin.
        DecisionRow = "Separation-before-rupture"

        % Computed by the engine, deliberately not displayed (Section 2).
        % Named in the scope footer, because a margin table that reads as
        % complete when it is not is a compliance problem.
        HiddenChecks = ["Bearing-under-head", "Bolt-thread shear", ...
                        "Nut strength", "Insert internal-thread", ...
                        "Insert external-thread", "Tapped-hole parent-thread"]

        % Above this, a capped margin renders ">+5". Display only.
        CapThreshold = 5
    end

    properties (Access = private)
        EmptyLabel
        VerdictLabel
        CapCheck
        StaleBanner
        Table
        DetailArea
        DecisionArea
        WarningArea
        ScopeLabel
    end

    methods
        function obj = ResultsPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "Results";
        end

        function t = title(~)
            t = "Single Joint Results";
        end

        function s = railStatus(obj)
            %RAILSTATUS  Amber dot while the shown result is out of date.
            if obj.State.ResultStale
                s = "stale";
            elseif ~isempty(obj.State.Result)
                s = "loaded";
            else
                s = "";
            end
        end

        function build(obj, parent)
            g = uigridlayout(parent, [6 2]);
            g.RowHeight     = {'fit', 'fit', 'fit', '1x', 'fit', 'fit'};
            g.ColumnWidth   = {'2x', '1x'};
            g.Padding       = [8 8 8 8];
            g.RowSpacing    = 8;
            g.ColumnSpacing = 10;
            g.Scrollable    = 'on';

            obj.addBanner(g, 1, [1 2], ...
                ['What the engine concluded for the joint on Joint Config. ' ...
                 'Nothing here is recomputed - every number, status and ' ...
                 'citation comes straight off the analysis.']);

            obj.buildHeaderRow(g, 2);

            % Amber, and hidden until it has something to say. Stale means
            % the form has moved on since this result was computed; the
            % numbers stay readable because they were true when produced
            % (A3), but they no longer describe what is on Joint Config.
            obj.StaleBanner = uilabel(g, 'WordWrap', 'on', 'Text', ...
                ['STALE - an input has changed since this was run. These ' ...
                 'numbers describe the joint as it was, not as it is now. ' ...
                 'Analyze again to refresh them.']);
            obj.StaleBanner.Layout.Row    = 3;
            obj.StaleBanner.Layout.Column = [1 2];
            obj.StaleBanner.BackgroundColor = gui2.palette('bannerWarnBg');
            obj.StaleBanner.FontColor       = gui2.palette('bannerWarnFg');
            obj.StaleBanner.FontWeight      = 'bold';
            obj.StaleBanner.Visible         = 'off';

            obj.buildTable(g, 4);
            obj.buildSidePanels(g, 4);
            obj.buildDetailPanel(g, 5);

            % PERMANENT, never Visible-toggled. A margin table that reads as
            % a complete 5020B assessment when six checks are missing is a
            % compliance problem, so the statement is always on screen.
            obj.ScopeLabel = uilabel(g, 'WordWrap', 'on', ...
                'Text', obj.scopeFooterText());
            obj.ScopeLabel.Layout.Row    = 6;
            obj.ScopeLabel.Layout.Column = [1 2];
            obj.ScopeLabel.FontColor     = gui2.palette('mutedText');

            obj.listenTo('ResultChanged', @() obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            %REFRESH  AppState.Result -> the page. Never marks dirty (A4).
            if ~obj.IsBuilt
                return
            end
            hasResult = ~isempty(obj.State.Result);

            % Empty state and table share one grid cell; only one is ever
            % visible (A12). An empty table with column headers looks like
            % a result of nothing, which is not the same as no result.
            obj.EmptyLabel.Visible = matlab.lang.OnOffSwitchState(~hasResult);
            obj.Table.Visible      = matlab.lang.OnOffSwitchState(hasResult);

            if ~hasResult
                obj.VerdictLabel.Text     = 'No analysis yet.';
                obj.VerdictLabel.FontColor = gui2.palette('mutedText');
                obj.StaleBanner.Visible   = 'off';
                obj.DetailArea.Value      = {''};
                obj.DecisionArea.Value    = {'Nothing decided yet - run Analyze on Joint Config.'};
                obj.WarningArea.Value     = {''};
                return
            end

            r = obj.State.Result;
            obj.StaleBanner.Visible = matlab.lang.OnOffSwitchState(obj.State.ResultStale);

            obj.renderTable();
            obj.selectDefaultRow();
            obj.renderVerdict();
            obj.renderDecisions();
            obj.renderWarnings();
            obj.updateDetail();

            obj.setStatus(sprintf('Showing results for "%s".', ...
                gui2.ResultsPage.orPlaceholder(r.JointName, 'untitled joint')));
        end
    end

    % ---- Layout -----------------------------------------------------------
    methods (Access = private)
        function buildHeaderRow(obj, g, row)
            %BUILDHEADERROW  The scope-qualified verdict, and the cap toggle.
            h = uigridlayout(g, [1 2]);
            h.Layout.Row    = row;
            h.Layout.Column = [1 2];
            h.ColumnWidth   = {'1x', 'fit'};
            h.RowHeight     = {'fit'};
            h.Padding       = [0 0 0 0];

            obj.VerdictLabel = uilabel(h, 'WordWrap', 'on', 'Text', '');
            obj.VerdictLabel.Layout.Row    = 1;
            obj.VerdictLabel.Layout.Column = 1;
            obj.VerdictLabel.FontWeight    = 'bold';
            obj.VerdictLabel.FontSize      = 13;

            % NOT bindEdit. The cap is a DISPLAY control: toggling it must
            % never mark the case dirty or stale a result (A4), so it gets
            % a plain callback rather than the dirty funnel every real edit
            % goes through.
            obj.CapCheck = uicheckbox(h, 'Text', 'Cap MS > 5', 'Value', true);
            obj.CapCheck.Layout.Row    = 1;
            obj.CapCheck.Layout.Column = 2;
            obj.CapCheck.Tooltip = ['DISPLAY ONLY - changes nothing that ' ...
                'was computed. A margin above 5 renders ">+5", because a ' ...
                'table of +47.30, +112.80, -0.14 buries the only number ' ...
                'that matters.'];
            obj.CapCheck.ValueChangedFcn = @(~, ~) obj.onCapToggled();
        end

        function buildTable(obj, g, row)
            % Both children take the SAME cell and toggle Visible - the
            % empty-state pattern from A12.
            obj.EmptyLabel = uilabel(g, 'WordWrap', 'on', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'center', 'Text', ...
                ['No analysis yet.' newline newline ...
                 'Fill in the joint on Joint Config and press ' ...
                 'Analyze Single Joint. The margins appear here.']);
            obj.EmptyLabel.Layout.Row    = row;
            obj.EmptyLabel.Layout.Column = 1;
            obj.EmptyLabel.FontColor     = gui2.palette('mutedText');

            obj.Table = uitable(g);
            obj.Table.Layout.Row    = row;
            obj.Table.Layout.Column = 1;
            obj.Table.ColumnName    = {'Check', 'Value', 'Status'};
            obj.Table.ColumnWidth   = {220, 150, 130};
            obj.Table.RowName       = {};
            obj.Table.ColumnEditable = [false false false];
            obj.Table.SelectionType = 'row';
            % Display only - selection must never dirty the case (A4).
            obj.Table.SelectionChangedFcn = @(~, ~) obj.updateDetail();
        end

        function buildSidePanels(obj, g, row)
            side = uigridlayout(g, [2 1]);
            side.Layout.Row    = row;
            side.Layout.Column = 2;
            side.ColumnWidth   = {'1x'};
            side.RowHeight     = {'1x', '1x'};
            side.Padding       = [0 0 0 0];
            side.RowSpacing    = 8;

            % Named for DECISIONS, not for a path: these are choices with
            % consequences - which branch ran, which allowable governed -
            % not a trace of what happened (Section 8.2).
            p1 = uipanel(side, 'FontWeight', 'bold', 'FontSize', 13, ...
                'Title', 'Analysis decisions');
            p1.Layout.Row = 1;
            g1 = uigridlayout(p1, [1 1]);
            g1.RowHeight   = {'1x'};
            g1.ColumnWidth = {'1x'};
            g1.Padding     = [6 6 6 6];
            obj.DecisionArea = uitextarea(g1, 'Editable', 'off', 'Value', {''});

            p2 = uipanel(side, 'FontWeight', 'bold', 'FontSize', 13, ...
                'Title', 'Warnings');
            p2.Layout.Row = 2;
            g2 = uigridlayout(p2, [1 1]);
            g2.RowHeight   = {'1x'};
            g2.ColumnWidth = {'1x'};
            g2.Padding     = [6 6 6 6];
            obj.WarningArea = uitextarea(g2, 'Editable', 'off', 'Value', {''});
        end

        function buildDetailPanel(obj, g, row)
            p = uipanel(g, 'FontWeight', 'bold', 'FontSize', 13, ...
                'Title', 'Selected check');
            p.Layout.Row    = row;
            p.Layout.Column = [1 2];
            pg = uigridlayout(p, [1 1]);
            pg.RowHeight   = {90};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [6 6 6 6];
            obj.DetailArea = uitextarea(pg, 'Editable', 'off', 'Value', {''});
        end
    end

    % ---- Rendering --------------------------------------------------------
    methods (Access = private)
        function renderTable(obj)
            %RENDERTABLE  The eight rows, then their colours.
            rows = obj.tableMargins();
            capOn = logical(obj.CapCheck.Value);

            data = cell(numel(rows), 3);
            for i = 1:numel(rows)
                data{i, 1} = char(rows(i).Name);
                data{i, 2} = gui2.ResultsPage.formatValue(rows(i), capOn);
                data{i, 3} = gui2.ResultsPage.statusText(rows(i).Status);
            end
            obj.Table.Data = data;

            obj.applyStyles(rows);
        end

        function applyStyles(obj, rows)
            %APPLYSTYLES  Colour from Status. Never re-thresholded (A2).
            %   removeStyle FIRST, then one addStyle per group with an Nx2
            %   index matrix - never a call per cell (A8). Styles otherwise
            %   accumulate, which costs render time and produces wrong
            %   colours, and a remote session multiplies both.
            %
            %   Wrapped: styling is cosmetic and is never allowed to break
            %   the numbers. If it fails the table still reads correctly and
            %   the stale banner still says what it needs to.
            if isempty(rows)
                return
            end
            try
                removeStyle(obj.Table);

                if obj.State.ResultStale
                    % Muted throughout rather than pass/fail coloured: a
                    % stale table must not present a confident verdict.
                    idx = gui2.ResultsPage.cellIndex(1:numel(rows), 1:3);
                    addStyle(obj.Table, ...
                        uistyle('BackgroundColor', gui2.palette('tableNaBg'), ...
                                'FontColor', gui2.palette('mutedText')), ...
                        'cell', idx);
                    return
                end

                status = string({rows.Status});
                pass    = find(status == "Pass");
                fail    = find(status == "Fail");
                notEval = find(status == "NotEvaluated");

                if ~isempty(pass)
                    addStyle(obj.Table, ...
                        uistyle('BackgroundColor', gui2.palette('tablePassBg')), ...
                        'cell', gui2.ResultsPage.cellIndex(pass, 3));
                end

                % ASYMMETRIC EMPHASIS: a failure paints the whole row, a
                % pass only its status chip. A failure has to be findable
                % at a glance in a table where most rows pass.
                if ~isempty(fail)
                    addStyle(obj.Table, ...
                        uistyle('BackgroundColor', gui2.palette('tableFailBg'), ...
                                'FontWeight', 'bold'), ...
                        'cell', gui2.ResultsPage.cellIndex(fail, 1:3));
                end

                % A1: unknown must never look like fine. Amber, not the
                % muted grey that reads as "nothing to report" - the check
                % did not run, and that is something to report.
                if ~isempty(notEval)
                    addStyle(obj.Table, ...
                        uistyle('BackgroundColor', gui2.palette('tableNotEvalBg')), ...
                        'cell', gui2.ResultsPage.cellIndex(notEval, 1:3));
                end
            catch
                % Styling unavailable - the numbers and the banner still
                % carry the result.
            end
        end

        function renderVerdict(obj)
            %RENDERVERDICT  Scope-qualified, always. Never "ALL CHECKS PASS".
            %   Counts all NINE displayed checks, not the eight in the
            %   table: Separation-before-rupture has a real Pass/Fail status
            %   and counting only the table would let a failed Fig. 8 gate
            %   escape the verdict entirely.
            shown = obj.displayedMargins();
            if isempty(shown)
                % A Result carrying none of the nine names is not a pass -
                % it is a Result this page cannot read (A1).
                obj.VerdictLabel.Text = ...
                    'This result carries none of the displayed checks.';
                obj.VerdictLabel.FontColor = gui2.palette('statusWarn');
                return
            end
            status = string({shown.Status});
            nFail  = sum(status == "Fail");
            nEval  = sum(status == "NotEvaluated");
            nTotal = numel(shown);
            nHid   = numel(gui2.ResultsPage.HiddenChecks);

            if nFail > 0
                txt = sprintf('%d of %d displayed checks FAIL', nFail, nTotal);
                col = gui2.palette('statusFail');
                % The verdict counts nine and the table shows eight, so a
                % failing Fig. 8 gate would otherwise be a failure the
                % analyst cannot find. Point at where it actually lives.
                decision = obj.marginNamed(gui2.ResultsPage.DecisionRow);
                if ~isempty(decision) && decision.Status == "Fail"
                    txt = [txt ' - including the separation-before-rupture ' ...
                           'decision, shown under Analysis decisions below'];
                end
            elseif nEval > 0
                % A1 forbids an unqualified pass while anything is
                % unevaluated - it would overstate what the engine
                % concluded.
                txt = sprintf('%d displayed checks pass, %d NOT EVALUATED', ...
                    nTotal - nEval, nEval);
                col = gui2.palette('statusWarn');
            else
                txt = sprintf('All %d displayed checks pass', nTotal);
                col = gui2.palette('statusPass');
            end

            obj.VerdictLabel.Text = sprintf('%s - %d more computed, not shown.', ...
                txt, nHid);
            obj.VerdictLabel.FontColor = col;
        end

        function renderDecisions(obj)
            %RENDERDECISIONS  Which branches ran, and on what authority.
            %   Everything here is surfaced VERBATIM from the Result. The
            %   shear-plane line in particular reads the Method citations
            %   rather than AppState.Joint.ShearPlane, because the joint on
            %   screen may already have moved on from the joint that
            %   produced this result.
            r = obj.State.Result;
            lines = {};

            sbr = obj.marginNamed(gui2.ResultsPage.DecisionRow);
            if ~isempty(sbr)
                lines{end+1} = sprintf('SEPARATION BEFORE RUPTURE: %s', ...
                    gui2.ResultsPage.statusText(sbr.Status)); %#ok<AGROW>
                if strlength(sbr.Method) > 0
                    lines{end+1} = sprintf('  %s', sbr.Method); %#ok<AGROW>
                end
            end
            if strlength(r.Narrative) > 0
                lines{end+1} = sprintf('  %s', r.Narrative); %#ok<AGROW>
            end

            lines{end+1} = ''; %#ok<AGROW>
            lines{end+1} = 'BOLT BENDING: not included (fbu = 0).'; %#ok<AGROW>
            lines{end+1} = ['  NASA-STD-5020B 4.4.4 exemption ASSUMED, ' ...
                            'not verified - close fit assumed.']; %#ok<AGROW>

            su = obj.marginNamed("Shear-Ultimate");
            ia = obj.marginNamed("Interaction");
            if ~isempty(su) || ~isempty(ia)
                lines{end+1} = ''; %#ok<AGROW>
                lines{end+1} = 'SHEAR PLANE - the equations that actually ran:'; %#ok<AGROW>
                if ~isempty(su)
                    lines{end+1} = sprintf('  %s', su.Method); %#ok<AGROW>
                end
                if ~isempty(ia)
                    lines{end+1} = sprintf('  %s', ia.Method); %#ok<AGROW>
                end
            end

            % Section 2's "Allowable from" requirement. The Tension-Ultimate
            % Detail already carries the system-allowable trace naming the
            % governing mode, so it is surfaced whole rather than parsed -
            % the hidden 4.4.1 rows must not hide their effect on the
            % tension number.
            tu = obj.marginNamed("Tension-Ultimate");
            if ~isempty(tu) && strlength(tu.Detail) > 0
                lines{end+1} = ''; %#ok<AGROW>
                lines{end+1} = 'FASTENING-SYSTEM ALLOWABLE (5020B 4.4.1):'; %#ok<AGROW>
                lines{end+1} = sprintf('  %s', tu.Detail); %#ok<AGROW>
            end

            obj.DecisionArea.Value = lines;
        end

        function renderWarnings(obj)
            %RENDERWARNINGS  Rebuilt from scratch, never accumulated (A3).
            %   Never scope-filtered: warnings are joint-level and are not
            %   tied to any margin row, so hiding six checks hides no
            %   warning (Section 2).
            w = obj.State.Result.Warnings;
            if isempty(w)
                obj.WarningArea.Value = {'No warnings raised.'};
                return
            end
            lines = cell(1, 0);
            for i = 1:numel(w)
                lines{end+1} = sprintf('[%s] %s', ...
                    upper(char(w(i).Severity)), char(w(i).Message)); %#ok<AGROW>
                if strlength(w(i).Method) > 0
                    lines{end+1} = sprintf('  %s', w(i).Method); %#ok<AGROW>
                end
                if strlength(w(i).Detail) > 0
                    lines{end+1} = sprintf('  %s', w(i).Detail); %#ok<AGROW>
                end
                lines{end+1} = ''; %#ok<AGROW>
            end
            obj.WarningArea.Value = lines;
        end

        function updateDetail(obj)
            %UPDATEDETAIL  Method and Detail for the selected row.
            if isempty(obj.State.Result)
                obj.DetailArea.Value = {''};
                return
            end
            rows = obj.tableMargins();
            k = obj.Table.Selection;
            if isempty(k) || k(1) < 1 || k(1) > numel(rows)
                obj.DetailArea.Value = ...
                    {'Select a row to see the governing equation and its detail.'};
                return
            end
            m = rows(k(1));
            lines = {sprintf('%s - %s', char(m.Name), ...
                             gui2.ResultsPage.statusText(m.Status))};
            if strlength(m.Method) > 0
                lines{end+1} = char(m.Method); %#ok<AGROW>
            end
            if strlength(m.Detail) > 0
                lines{end+1} = ''; %#ok<AGROW>
                lines{end+1} = char(m.Detail); %#ok<AGROW>
            end
            obj.DetailArea.Value = lines;
        end

        function selectDefaultRow(obj)
            %SELECTDEFAULTROW  Land on the first failure, else the top.
            %   Section 8.3. A table where most rows pass makes the one that
            %   does not the thing worth landing on; with nothing failing,
            %   row 1 is a neutral start rather than an implied verdict.
            rows = obj.tableMargins();
            if isempty(rows)
                return
            end
            k = find(string({rows.Status}) == "Fail", 1);
            if isempty(k)
                k = 1;
            end
            obj.selectRow(k);
        end

        function onCapToggled(obj)
            %ONCAPTOGGLED  Redraw only. NEVER dirties, never stales (A4).
            if isempty(obj.State.Result)
                return
            end
            obj.renderTable();
            obj.updateDetail();
        end
    end

    % ---- Reading the Result -----------------------------------------------
    methods (Access = private)
        function m = marginNamed(obj, name)
            %MARGINNAMED  One Margins row by name, or empty if absent.
            m = [];
            if isempty(obj.State.Result)
                return
            end
            all = obj.State.Result.Margins;
            if isempty(all)
                return
            end
            k = find(string({all.Name}) == name, 1);
            if ~isempty(k)
                m = all(k);
            end
        end

        function rows = tableMargins(obj)
            %TABLEMARGINS  The eight table rows, in the declared order.
            rows = obj.marginsNamed(gui2.ResultsPage.TableRows);
        end

        function rows = displayedMargins(obj)
            %DISPLAYEDMARGINS  All NINE displayed checks - the table's eight
            %   plus the decision row, which carries a real Pass/Fail and so
            %   belongs in the verdict count.
            rows = obj.marginsNamed( ...
                [gui2.ResultsPage.TableRows, gui2.ResultsPage.DecisionRow]);
        end

        function rows = marginsNamed(obj, names)
            rows = [];
            for i = 1:numel(names)
                m = obj.marginNamed(names(i));
                if isempty(m)
                    continue
                end
                if isempty(rows)
                    rows = m;
                else
                    rows(end + 1) = m; %#ok<AGROW>
                end
            end
        end

        function t = scopeFooterText(~)
            t = sprintf(['SCOPE: 9 of 15 checks shown. %d computed and NOT ' ...
                'displayed: %s. This is not a complete NASA-STD-5020B ' ...
                'assessment.'], numel(gui2.ResultsPage.HiddenChecks), ...
                strjoin(cellstr(gui2.ResultsPage.HiddenChecks), ', '));
        end
    end

    % ---- Formatting -------------------------------------------------------
    methods (Static, Access = private)
        function s = formatValue(m, capOn)
            %FORMATVALUE  The Value cell for one row.
            %   Interaction is the exception and stays one: it reports a
            %   RATIO on the opposite scale, so its criterion is rendered
            %   with it and can never be read as a margin.
            if m.Name == "Interaction"
                if isnan(m.R)
                    s = char(8212);
                else
                    s = sprintf('R = %.2f (<= 1)', m.R);
                end
                return
            end
            if isnan(m.MS)
                % A1: an em dash, never a blank and never a zero.
                s = char(8212);
            elseif isinf(m.MS)
                s = '+inf';
            elseif capOn && m.MS > gui2.ResultsPage.CapThreshold
                s = '>+5';
            else
                s = sprintf('%+.2f', m.MS);
            end
        end

        function s = statusText(status)
            %STATUSTEXT  Engine status -> what the analyst reads.
            switch string(status)
                case "Pass"
                    s = 'Pass';
                case "Fail"
                    s = 'FAIL';
                otherwise
                    s = 'Not evaluated';
            end
        end

        function idx = cellIndex(rows, cols)
            %CELLINDEX  Nx2 [row col] matrix for addStyle (A8).
            rows = rows(:);
            cols = cols(:)';
            idx = [repelem(rows, numel(cols), 1), ...
                   repmat(cols', numel(rows), 1)];
        end

        function s = orPlaceholder(value, placeholder)
            s = char(strtrim(string(value)));
            if isempty(s)
                s = placeholder;
            end
        end
    end

    % ---- Public surface ---------------------------------------------------
    methods
        function selectRow(obj, k)
            %SELECTROW  Select a table row and repaint the detail panel.
            %   Public because assigning Selection programmatically does NOT
            %   fire SelectionChangedFcn - anything that wants to drive the
            %   selection (this page's own default, a later "go to the
            %   governing check" action, a test) has to go through here or
            %   the detail panel silently disagrees with the highlight.
            %
            %   Display only: selecting a row never dirties the case (A4).
            if isempty(obj.Table) || ~isvalid(obj.Table) || k < 1
                return
            end
            obj.Table.Selection = k;
            obj.updateDetail();
        end
    end

    % ---- Test seams -------------------------------------------------------
    methods
        function t = marginTable(obj)
            t = obj.Table;
        end

        function l = verdictLabel(obj)
            l = obj.VerdictLabel;
        end

        function c = capCheck(obj)
            c = obj.CapCheck;
        end

        function l = staleBanner(obj)
            l = obj.StaleBanner;
        end

        function l = emptyLabel(obj)
            l = obj.EmptyLabel;
        end

        function a = decisionArea(obj)
            a = obj.DecisionArea;
        end

        function a = warningArea(obj)
            a = obj.WarningArea;
        end

        function a = detailArea(obj)
            a = obj.DetailArea;
        end

        function l = scopeLabel(obj)
            l = obj.ScopeLabel;
        end
    end
end
