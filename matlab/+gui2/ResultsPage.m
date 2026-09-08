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
    %   ten-row table. Neither is displayed, and the view never recomputes
    %   a minimum over the displayed subset — that would be the view
    %   deriving a number, and it could overstate the margin (Section 2).
    %
    %   THE READOUT ROW carries Result.Preload and Result.DesignLoads — the
    %   nine numbers the margins were computed FROM. Both come straight off
    %   the Result; neither is recomputed here, and in particular this page
    %   never calls engine.preload. It could: the function is pure. But it
    %   would then be answering for the joint currently on Joint Config
    %   rather than the joint that produced this Result, so a stale result
    %   would show fresh preload — exactly what the stale banner exists to
    %   prevent. (engine.preload also lets stiffness errors propagate rather
    %   than returning NotEvaluated, so a live readout would throw on a
    %   half-filled joint.)
    %
    %   The readout panels are PERMANENT, never Visible-toggled: they render
    %   em dashes when the Result carries no preload block, so the layout
    %   does not jump between "no analysis" and "analysis". Both structs
    %   default to struct() with NO fields, so absent-field is the normal
    %   case, not an error case.
    %
    %   Backed by AppState.Result. Repaints on ResultChanged, which fires
    %   both for a fresh result and for markResultStale.

    properties (Constant, Access = private)
        % The ten table rows, in solver order, INTERACTION LAST.
        % Separation-before-rupture is deliberately absent: see the class
        % note and Section 8.2.
        %
        % Bearing-under-head and Bolt-thread shear were hidden here for no
        % reason anyone could state. Bearing-under-head is REQUIRED -
        % NASA-STD-5020B 4.4.2 calls for margins on the joint members and
        % prints no member-strength equations, so TM-106943 Eq. 74/75
        % supply them - and it was computed on every run and shown nowhere.
        % Bolt-thread shear is a real failure mode that 5020B defers on
        % (TM-106943 Eq. 63) and, unlike the four remaining hidden rows, is
        % NOT folded into Ptu_allow: those are the INTERNAL threads.
        TableRows = ["Tension-Ultimate", "Tension-Yield", "Shear-Ultimate", ...
                     "Separation", "Slip", "Bearing", "Bearing-under-head", ...
                     "Shear-tearout", "Bolt-thread shear", "Nut strength", ...
                     "Insert internal-thread", "Insert external-thread", ...
                     "Tapped-hole parent-thread", "Interaction"]

        % The ninth displayed check. A decision, not a margin.
        DecisionRow = "Separation-before-rupture"

        % NOTHING IS HIDDEN ANY MORE, and the reasoning that hid the four
        % §4.4.1 threaded-member modes was wrong. It claimed a margin row
        % for them would "report one fact twice", because whichever mode
        % applies sets Ptu_allow and so governs Tension-Ultimate. They are
        % not one fact. The modes carry their own margins against a
        % DIFFERENT design load -- engine.boltDesignLoad's preload-included
        % Eq. 8 form, Pb = PpMax + FFU*FSU*n*phi*PtL -- while
        % Tension-Ultimate divides by Ptu = FSU*FFU*PtL with no preload and
        % no n*phi. A nut-strength MS is therefore not recoverable from the
        % Tension-Ultimate row, and hiding it meant four computed margins
        % appeared nowhere while the scope footer asserted that nothing was
        % omitted.
        %
        % All fifteen checks are now displayed: fourteen margin rows plus
        % the Fig. 8 gate, which leads Analysis decisions because it is a
        % branch selection rather than a margin (see the class note).
        %
        % Only one threaded-member mode applies to any given joint, so the
        % other three come back NotEvaluated and render amber. That is the
        % honest outcome and the table already handles it: Slip does the
        % same whenever mu = 0.

        % (The ">+5" display cap moved to gui2.MarginView with the
        % formatting it belongs to. NOT aliased back here: a Constant
        % initialised from another class's Constant is evaluated once at
        % class load and then silently keeps a stale copy — the same trap
        % that shipped a wrong version string on a PDF.)

        % The readout rows: field name on Result.Preload, the gloss, and the
        % citation + written equation. Columns 2 and 3 become the tooltip, so
        % the equation behind each number is one hover away (CLAUDE.md's
        % traceability rule: reference, number, and the equation written out).
        %
        % Field names are shown VERBATIM rather than prettified, because they
        % are the names engine.summary, the reports and the case JSON all use
        % - an analyst cross-referencing this panel against a report must be
        % able to match rows by eye.
        PreloadRows = [ ...
            "PpiMax", "Maximum initial (installation) preload", ...
              "NASA-STD-5020B Eq. 3 - PpiMax = c_max*(1 + Gamma)*Ppi_nom"; ...
            "PpiMin", "Minimum initial (installation) preload", ...
              "NASA-STD-5020B Eq. 4 (separation-critical) - " + ...
              "PpiMin = c_min*(1 - Gamma)*Ppi_nom; otherwise Eq. 5 - " + ...
              "PpiMin = c_min*(1 - Gamma/sqrt(nf))*Ppi_nom"; ...
            "ThermalDelta", "Thermal preload change - MAXIMUM SIDE ONLY", ...
              "NASA TM-106943 (Chambers) Eq. 10 - " + ...
              "Pth = (Kb*Kc/(Kb + Kc))*L*dT*(alpha_j - alpha_b). " + ...
              "This is the GAIN added to PpMax. The minimum-side thermal " + ...
              "LOSS is a different number: the engine folds it into PpMin " + ...
              "and does not return it separately, so it cannot be shown here."; ...
            "PpMax", "Maximum in-service preload", ...
              "NASA-STD-5020B Eq. 1 - PpMax = PpiMax + Pth_max"; ...
            "PpMin", "Minimum in-service preload", ...
              "NASA-STD-5020B Eq. 2 - " + ...
              "PpMin = (1 - relaxation)*PpiMin - creep - Pth_min"]

        % Field name on Result.DesignLoads, gloss, formula. These are limit
        % loads factored up; no 5020B equation number attaches to them.
        DesignLoadRows = [ ...
            "Ptu",  "Design ultimate tension", ...
              "Ptu = FSU * FFU * BoltTensileLimitLoad"; ...
            "Pty",  "Design yield tension", ...
              "Pty = FSY * FFY * BoltTensileLimitLoad"; ...
            "Psu",  "Design ultimate shear", ...
              "Psu = FSU * FFU * BoltShearLimitLoad"; ...
            "Psep", "Design separation load", ...
              "Psep = FSSep * FFSep * BoltTensileLimitLoad"]
    end

    properties (Access = private)
        EmptyLabel
        VerdictLabel
        CapCheck
        StaleBanner
        ReportButton
        ExportButton
        PreloadValues       % 1x5 gobjects, in PreloadRows order
        DesignLoadValues    % 1x4 gobjects, in DesignLoadRows order
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
            g = uigridlayout(parent, [7 2]);
            % Rows 5 and 6 SHARE the height. The table has ten fixed rows
            % and the detail panel grows with its citation, so giving the
            % table all the slack left a tall band of empty grid under the
            % rows while the detail sat squeezed at the bottom.
            %
            % Row 4 (the preload / design-loads readout) is 'fit' and spans
            % both columns. It sits ABOVE the table because it is the input
            % side of the story - these are the loads the margins were
            % computed from - and because column 2 has no free cell: the
            % decisions/warnings panel deliberately spans both content rows.
            g.RowHeight     = {'fit', 'fit', 'fit', 'fit', '1x', '1x', 'fit'};
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

            obj.buildReadoutRow(g, 4);
            obj.buildTable(g, 5);
            obj.buildSidePanels(g, 5);
            obj.buildDetailPanel(g, 6);

            % PERMANENT, never Visible-toggled. A margin table that reads as
            % a complete 5020B assessment when six checks are missing is a
            % compliance problem, so the statement is always on screen.
            obj.ScopeLabel = uilabel(g, 'WordWrap', 'on', ...
                'Text', obj.scopeFooterText());
            obj.ScopeLabel.Layout.Row    = 7;
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

            % Export needs a Result; the PDF additionally needs the inputs
            % that produced it, which a Result staged directly (a test, a
            % future case-file load) does not carry. Disabled beats writing
            % a report about the wrong joint.
            obj.ExportButton.Enable = matlab.lang.OnOffSwitchState(hasResult);
            obj.ReportButton.Enable = matlab.lang.OnOffSwitchState( ...
                hasResult && ~isempty(obj.State.ResultInputs));

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
                % Painted here too, not skipped: the readout must return to
                % em dashes when a case is closed, or it would keep showing
                % the previous joint's preload under an empty margin table.
                obj.renderReadouts();
                return
            end

            r = obj.State.Result;
            obj.StaleBanner.Visible = matlab.lang.OnOffSwitchState(obj.State.ResultStale);

            obj.renderReadouts();
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
            h = uigridlayout(g, [1 4]);
            h.Layout.Row    = row;
            h.Layout.Column = [1 2];
            h.ColumnWidth   = {'1x', 'fit', 'fit', 'fit'};
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

            % HERE, not on the File menu. The thing being exported is the
            % Result on this page, and an analyst who has just read a
            % verdict should not have to go looking elsewhere to hand it to
            % someone. Both stay disabled until there is something to write.
            obj.ReportButton = uibutton(h, 'push', 'Text', 'Save PDF Report...', ...
                'ButtonPushedFcn', @(~, ~) obj.onSaveReport());
            obj.ReportButton.Layout.Row    = 1;
            obj.ReportButton.Layout.Column = 3;
            obj.ReportButton.Tooltip = ['Write the full single-joint report ' ...
                'as a PDF - inputs, preload, design loads, every margin ' ...
                'and its citation - stamped with the tool version and the ' ...
                'time of the run.'];

            obj.ExportButton = uibutton(h, 'push', 'Text', 'Export Table...', ...
                'ButtonPushedFcn', @(~, ~) obj.onExportTable());
            obj.ExportButton.Layout.Row    = 1;
            obj.ExportButton.Layout.Column = 4;
            obj.ExportButton.Tooltip = ['Write the displayed checks to ' ...
                '.xlsx or .csv. The scope statement travels with them, so ' ...
                'the six computed-but-not-shown checks cannot be lost.'];
        end

        function onSaveReport(obj)
            %ONSAVEREPORT  The PDF, from the inputs that produced this Result.
            %   report.singleJointReport RE-RUNS engine.analyze rather than
            %   taking a Result, so it is handed AppState.ResultInputs - the
            %   joint as it was when Analyze ran - and never the current
            %   form. Handed the form it would document a different analysis
            %   from the one on screen whenever the case had been edited
            %   since, which is precisely what ResultStale flags.
            in = obj.State.ResultInputs;
            if isempty(in)
                obj.setStatus(['This result was not produced by a run in ' ...
                    'this session, so its inputs are unknown - re-run ' ...
                    'Analyze before reporting.']);
                return
            end

            [f, p] = uiputfile('*.pdf', 'Save Report As', 'joint-report.pdf');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));

            % Its own try/catch inside its own callback (Section 11), and
            % the Report Generator is the slowest thing this app does, so
            % the status bar says so before it starts.
            obj.setStatus('Writing the PDF report...');
            try
                written = report.singleJointReport(in.Joint, in.LoadCase, ...
                    in.Factors, file);
            catch err
                uialert(ancestor(obj.Root, 'figure'), err.message, ...
                    'Report failed');
                obj.setStatus('Report failed.');
                return
            end
            obj.setStatus(sprintf('Wrote %s', written));
        end

        function onExportTable(obj)
            %ONEXPORTTABLE  The DISPLAYED checks, with the scope statement.
            %   Section 2: exports carry the same nine checks the page
            %   shows, and the statement naming the six that are computed
            %   and not shown travels WITH them. A spreadsheet that reads as
            %   a complete 5020B assessment is the same compliance problem
            %   on disk as it is on screen.
            r = obj.State.Result;
            if isempty(r)
                return
            end
            [f, p] = uiputfile({'*.xlsx', 'Excel workbook'; '*.csv', 'CSV'}, ...
                'Export Table As', 'joint-margins.xlsx');
            if isequal(f, 0)
                return
            end

            try
                written = report.exportResults(obj.displayedTable(), ...
                    string(fullfile(p, f)), Notes = obj.scopeFooterText());
            catch err
                uialert(ancestor(obj.Root, 'figure'), err.message, ...
                    'Export failed');
                return
            end
            obj.setStatus(sprintf('Wrote %s', written));
        end

        function T = displayedTable(obj)
            %DISPLAYEDTABLE  The nine displayed checks as a table.
            %   Built from the SAME tableMargins the grid is built from, so
            %   the file and the screen cannot show different rows, and the
            %   gate is appended because it is the ninth displayed check
            %   even though it carries no margin.
            rows = [obj.tableMargins(), obj.marginsNamed(gui2.ResultsPage.DecisionRow)];
            Check  = strings(numel(rows), 1);
            Value  = strings(numel(rows), 1);
            Status = strings(numel(rows), 1);
            Method = strings(numel(rows), 1);
            for i = 1:numel(rows)
                Check(i)  = rows(i).Name;
                % The cap is a DISPLAY convenience and has no place in a
                % file someone will do arithmetic on, so the export always
                % writes the real number.
                Value(i)  = string(gui2.ResultsPage.formatValue(rows(i), false));
                Status(i) = gui2.ResultsPage.statusText(rows(i).Status);
                Method(i) = rows(i).Method;
            end
            T = table(Check, Value, Status, Method);
        end

        function buildReadoutRow(obj, g, row)
            %BUILDREADOUTROW  Preload and design loads, side by side.
            %   Two panels rather than one: they come from two different
            %   engine functions and one is an installation quantity while
            %   the other is a factored load. Merging them into a single
            %   nine-row list would invite reading PpMax against Ptu as if
            %   they were the same kind of number.
            strip = uigridlayout(g, [1 2]);
            strip.Layout.Row    = row;
            strip.Layout.Column = [1 2];
            strip.ColumnWidth   = {'1x', '1x'};
            strip.RowHeight     = {'fit'};
            strip.Padding       = [0 0 0 0];
            strip.ColumnSpacing = 10;

            obj.PreloadValues = obj.buildReadoutPanel(strip, 1, ...
                'Preload (engine.preload, lbf)', ...
                gui2.ResultsPage.PreloadRows);
            obj.DesignLoadValues = obj.buildReadoutPanel(strip, 2, ...
                'Design loads (engine.designLoads, lbf)', ...
                gui2.ResultsPage.DesignLoadRows);
        end

        function vals = buildReadoutPanel(~, parent, col, titleText, spec)
            %BUILDREADOUTPANEL  One label/value panel. Returns the value labels.
            p = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, ...
                'Title', titleText);
            p.Layout.Row    = 1;
            p.Layout.Column = col;

            n = size(spec, 1);
            b = uigridlayout(p, [n 2]);
            % Fixed label column: the two panels are siblings and an analyst
            % reads across them, so 'fit' - which would size each panel's
            % labels independently - puts the two value columns at different
            % x positions and the row of numbers stops scanning as a row.
            b.ColumnWidth   = {104, '1x'};
            b.RowHeight     = repmat({20}, 1, n);
            b.Padding       = [6 4 6 4];
            b.RowSpacing    = 2;

            vals = gobjects(1, n);
            for i = 1:n
                tip = char(spec(i, 2) + " - " + spec(i, 3));

                lb = uilabel(b, 'Text', char(spec(i, 1)), 'Tooltip', tip);
                lb.Layout.Row    = i;
                lb.Layout.Column = 1;

                % Right-aligned: these are magnitudes read against each
                % other, and ragged-left digits defeat that comparison.
                v = uilabel(b, 'Text', char(8212), 'Tooltip', tip, ...
                    'HorizontalAlignment', 'right');
                v.Layout.Row    = i;
                v.Layout.Column = 2;
                vals(i) = v;
            end
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
            % The last column takes the slack. Fixed widths summing to less
            % than the cell left a dead strip inside the table's own border,
            % which reads as a rendering fault rather than as spare room.
            obj.Table.ColumnWidth   = {240, 150, '1x'};
            obj.Table.RowName       = {};
            obj.Table.ColumnEditable = [false false false];
            obj.Table.SelectionType = 'row';
            % Display only - selection must never dirty the case (A4).
            obj.Table.SelectionChangedFcn = @(~, ~) obj.updateDetail();
        end

        function buildSidePanels(obj, g, row)
            side = uigridlayout(g, [2 1]);
            % Spans BOTH content rows: the decisions text is the longest
            % thing on the page and was scrolling inside half the height it
            % could have had.
            side.Layout.Row    = [row row + 1];
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
            % Column 1 ONLY. The decisions/warnings panel spans both content
            % rows in column 2, so spanning [1 2] here put two widgets in
            % the same cell - they stack rather than error, which is worse.
            p.Layout.Column = 1;
            pg = uigridlayout(p, [1 1]);
            % '1x', not a fixed 90: the row is now '1x' and a fixed inner
            % height was why the citation sat squeezed at the bottom of a
            % panel with room to spare.
            pg.RowHeight   = {'1x'};
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

        function renderReadouts(obj)
            %RENDERREADOUTS  Result.Preload and Result.DesignLoads -> labels.
            %   Reads fields off the Result and formats them. Computes
            %   nothing, derives nothing, and never falls back to calling
            %   engine.preload - see the class note.
            r = obj.State.Result;
            if isempty(r)
                pre  = struct();
                load = struct();
            else
                pre  = r.Preload;
                load = r.DesignLoads;
            end

            % Muted while stale, matching the table: a number that no longer
            % describes the joint on screen must not read as current.
            stale = ~isempty(r) && obj.State.ResultStale;

            obj.fillReadout(obj.PreloadValues, ...
                gui2.ResultsPage.PreloadRows(:, 1), pre, stale);
            obj.fillReadout(obj.DesignLoadValues, ...
                gui2.ResultsPage.DesignLoadRows(:, 1), load, stale);
        end

        function fillReadout(~, labels, names, src, stale)
            %FILLREADOUT  One panel's value labels, in spec order.
            if stale
                col = gui2.palette('mutedText');
            else
                col = gui2.palette('defaultText');
            end
            for i = 1:numel(labels)
                labels(i).Text      = gui2.ResultsPage.readoutValue(src, names(i));
                labels(i).FontColor = col;
            end
        end

        function renderVerdict(obj)
            %RENDERVERDICT  Scope-qualified, always. Never "ALL CHECKS PASS".
            %   Counts the EIGHT margin rows. Separation-before-rupture is
            %   deliberately excluded: "not assured" is a BRANCH SELECTION,
            %   not a failure. It means the tension check took the more
            %   conservative Eq. 10 rupture path instead of Eq. 6, and that
            %   consequence is already fully reflected in the
            %   Tension-Ultimate margin - counting it again reports the same
            %   thing twice and paints a red failure on a joint that may be
            %   entirely sound.
            %
            %   The engine agrees: it gives the gate MS = NaN, which
            %   excludes it from WorstMargin. A row the engine refuses to
            %   let govern should not govern the verdict either.
            shown = obj.tableMargins();
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

            if nFail > 0
                txt = sprintf('%d of %d displayed checks FAIL', nFail, nTotal);
                col = gui2.palette('statusFail');
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

            % NO "N more computed, not shown" TAIL. It existed because six,
            % then four, computed checks had no row; every one of them has
            % a row now, so the sentence would read "0 more computed, not
            % shown" -- a qualification about nothing, which is exactly the
            % kind of boilerplate an analyst stops reading and then misses
            % when it says something real.
            obj.VerdictLabel.Text = txt;
            obj.VerdictLabel.FontColor = col;
        end

        function renderDecisions(obj)
            %RENDERDECISIONS  Which branches ran, and on what authority.
            %   DECISIONS ONLY. Equation citations were duplicated here for
            %   every check that had one, while the Selected check panel
            %   already shows Method and Detail for whichever row is
            %   clicked - so the longest text on the page repeated what was
            %   one click away, twice over, because tu.Decision also
            %   arrives as Result.Narrative AND as the gate row's Detail.
            %
            %   Everything below is read from STRUCTURED fields
            %   (Result.Gate, Result.Allowables), never parsed out of prose.
            %   The engine had this structure and used to flatten it into
            %   one sentence on the way out; it does not any more.
            r = obj.State.Result;
            lines = {};

            lines = [lines, obj.gateLines(r)];
            lines = [lines, obj.allowableLines(r)];

            lines = [lines, obj.bendingLines(r)];

            % The shear PLANE is a decision - it selects which equations
            % run at all - so it stays. Its citation is read from the
            % Method the engine returned rather than from
            % AppState.Joint.ShearPlane, because the joint on screen may
            % already have moved on from the joint that produced this
            % result. One line, not two: Interaction's citation says the
            % same thing and is on its own row in the table.
            su = obj.marginNamed("Shear-Ultimate");
            if ~isempty(su) && strlength(su.Method) > 0
                lines{end+1} = '';
                lines{end+1} = 'SHEAR PLANE - the equations that actually ran:';
                lines{end+1} = sprintf('  %s', su.Method);
            end

            obj.DecisionArea.Value = lines;
        end

        function lines = gateLines(~, r)
            %GATELINES  The Fig. 8 gate, one fact per line.
            lines = {};
            if ~isfield(r.Gate, 'Assessed')
                return
            end
            g = r.Gate;

            if ~g.Assessed
                verdict = 'NOT ASSESSED';
            elseif g.Assured
                verdict = 'ASSURED';
            else
                % NOT "FAIL". The engine has only Pass/Fail/NotEvaluated to
                % express a boolean gate with, but "not assured" SELECTS
                % the conservative rupture branch - it does not fail
                % anything, and that consequence is already priced into the
                % Tension-Ultimate margin.
                verdict = 'NOT ASSURED';
            end
            lines{end+1} = sprintf('SEPARATION BEFORE RUPTURE: %s', verdict);

            if strlength(g.Equation) > 0
                lines{end+1} = sprintf('  Governing equation: %s', g.Equation);
            end
            if isfinite(g.Phi)
                % Only the rupture branch has these, and they are the
                % numbers someone re-deriving that margin by hand needs.
                lines{end+1} = sprintf('  phi = %.4g (Eq. 9), n = %.2f', ...
                    g.Phi, g.N);
            end
            if strlength(g.Trace) > 0
                lines{end+1} = sprintf('  Gate: %s', g.Trace);
            end
        end

        function lines = bendingLines(~, r)
            %BENDINGLINES  The §4.4.4 determination, read from the Result.
            %   These four lines were HARDCODED to "not included (fbu = 0),
            %   exemption ASSUMED, not verified" -- printed unconditionally,
            %   without consulting anything. That was true while bending was
            %   unimplemented and false the moment a joint declared
            %   CloseToleranceOrInterference, which the engine has recorded
            %   since 2026-08-04. It now reads Result.Bending.
            lines = {''};
            if ~isfield(r.Bending, 'Condition')
                % A Result from before bending, or one staged directly.
                lines{end+1} = 'BOLT BENDING: not reported by this result.';
                return
            end
            bnd = r.Bending;

            if bnd.Included
                lines{end+1} = sprintf( ...
                    'BOLT BENDING: INCLUDED - fbu = %s psi on the %s diameter.', ...
                    gui2.ResultsPage.withThousands(bnd.Fbu), bnd.Basis);
                lines{end+1} = sprintf( ...
                    '  Rb = fbu/Ftu = %.4f, added to Rt inside the Eq. 20/22 bracket.', ...
                    bnd.Rb);
                lines{end+1} = sprintf('  Determination: %s.', bnd.Condition);
                return
            end

            lines{end+1} = 'BOLT BENDING: not included (fbu = 0).';
            switch bnd.Condition
                case "CloseToleranceOrInterference"
                    lines{end+1} = ['  NASA-STD-5020B 4.4.4 exemption ' ...
                        'VERIFIED - close-tolerance or interference fit.'];
                    % No "moment ignored" case any more: since the
                    % 2026-08-13 audit a supplied moment is used on every
                    % determination, because 4.4.4's exemption covers only
                    % bending caused by the SHEAR loading. Reaching this
                    % branch at all means no moment was supplied.
                case "ClearanceOrGapped"
                    % The one combination that is not a quiet default: the
                    % analyst has said bending applies and supplied nothing.
                    lines{end+1} = ['  4.4.4 says bending APPLIES here, and ' ...
                        'no bending moment was supplied - the interaction ' ...
                        'check is not evaluated. Enter a bolt bending ' ...
                        'limit moment on Joint Config.'];
                otherwise
                    lines{end+1} = ['  NASA-STD-5020B 4.4.4 exemption ' ...
                        'ASSUMED, not verified - record the determination ' ...
                        'with the shear-transfer condition on Joint Config.'];
            end
        end

        function lines = allowableLines(~, r)
            %ALLOWABLELINES  The 5020B 4.4.1 system allowable, as a list.
            %   It IS a table - one row per tensile failure mode, with the
            %   minimum governing - and it used to be rendered as a single
            %   prose sentence carrying all of it.
            lines = {};
            if ~isfield(r.Allowables, 'PtuAllow')
                return
            end
            a = r.Allowables;

            lines{end+1} = '';
            lines{end+1} = 'FASTENING-SYSTEM ALLOWABLE (5020B 4.4.1):';
            lines{end+1} = sprintf('  Governing: %s, %s lbf', ...
                gui2.ResultsPage.orPlaceholder(a.GoverningMode, 'unknown'), ...
                gui2.ResultsPage.withThousands(a.PtuAllow));

            if isfield(a, 'Modes') && ~isempty(a.Modes)
                for i = 1:numel(a.Modes)
                    m = a.Modes(i);
                    if m.Assessed
                        val = gui2.ResultsPage.withThousands(m.Allowable) + " lbf";
                    else
                        % A1: an unassessed mode is not a zero and not a
                        % blank - it is a hole in the minimum below.
                        val = "not assessed";
                    end
                    lines{end+1} = sprintf('    %-28s %s', ...
                        char(m.Name), char(val)); %#ok<AGROW>
                end
            end

            % THE FLAG THAT USED TO BE A CLAUSE. An incomplete set means
            % the minimum was taken over fewer modes than apply, so the
            % allowable - and every margin derived from it - is optimistic.
            if isfield(a, 'Complete') && ~a.Complete
                lines{end+1} = ['  INCOMPLETE - a mode that applies could ' ...
                    'not be assessed, so this minimum is over an ' ...
                    'incomplete set and is OPTIMISTIC.'];
            end
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
            %UPDATEDETAIL  The selected row, laid out rather than dumped.
            %   Three things it used to get wrong.
            %
            %   IT NEVER SHOWED THE NUMBER. It named the check and its
            %   status and then printed citations, so the one thing you had
            %   selected the row to look at was back in the table. The value
            %   comes from the SAME formatValue the table uses, so the cap
            %   rule and Interaction's ratio form cannot disagree between
            %   the two.
            %
            %   METHOD AND DETAIL ARRIVED AS BARE PARAGRAPHS, with nothing
            %   saying which was which. On a NotEvaluated row Method is not
            %   a governing equation at all - it carries the REASON the
            %   check did not run - so it is labelled accordingly.
            %
            %   AND THE GLUED SENTENCE MOVED HERE. analyze sets the
            %   Tension-Ultimate row's Detail to tu.Decision, the same
            %   string as Result.Narrative, so taking it out of the
            %   decisions panel just relocated it one panel over. Where a
            %   row's Detail IS the Narrative, it is not reprinted: the
            %   decisions panel renders those facts from Result.Gate and
            %   Result.Allowables as structure, and this points there.
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

            notEval = string(m.Status) == "NotEvaluated";
            if ~notEval
                lines{end+1} = sprintf('  %s', ...
                    gui2.ResultsPage.formatValue(m, logical(obj.CapCheck.Value)));
            end

            if strlength(m.Method) > 0
                lines{end+1} = '';
                if notEval
                    % Method carries the REASON on these rows, not a
                    % governing equation - calling it one would be a lie.
                    lines{end+1} = 'Why it did not run:';
                else
                    lines{end+1} = 'Governing equation:';
                end
                lines{end+1} = sprintf('  %s', char(m.Method));
            end

            lines = [lines, obj.inputLines(m)];

            detail = obj.rowDetail(m);
            if strlength(detail) > 0
                lines{end+1} = '';
                lines{end+1} = 'Detail:';
                lines{end+1} = sprintf('  %s', char(detail));
            end

            obj.DetailArea.Value = lines;
        end

        function lines = inputLines(~, m)
            %INPUTLINES  The numbers substituted into this row's equation.
            %   THE POINT OF THE PANEL. Method says what the equation is and
            %   the table says what came out; without this, the values that
            %   went in are spread across the preload and design-load panels
            %   or nowhere at all, so a disagreement with another tool can be
            %   seen but not localised to a single input.
            %
            %   NOTHING IS COMPUTED HERE and nothing is inferred. An absent
            %   Inputs array renders no section at all rather than a heading
            %   over an empty list: empty means "not recorded on this row"
            %   (a NotEvaluated check, or a margin function not yet wired),
            %   which is not a statement that the check consumed no numbers.
            %   Printing a bare "Inputs:" heading would imply the latter.
            %
            %   isfield guards a Result staged with the pre-Inputs Margins
            %   shape, which the GUI tests build directly.
            lines = {};
            if ~isfield(m, 'Inputs') || isempty(m.Inputs)
                return
            end
            in = m.Inputs;

            % Pad symbols to a common width so the values form a column and
            % the eye can run down them against a spreadsheet.
            w = max(arrayfun(@(x) strlength(x.Symbol), in));

            lines{end+1} = '';
            lines{end+1} = 'Inputs (substituted into the equation above):';
            for i = 1:numel(in)
                lines{end+1} = sprintf('  %s = %s%s', ...
                    char(pad(in(i).Symbol, w)), ...
                    char(gui2.ResultsPage.inputValueText(in(i))), ...
                    char(gui2.ResultsPage.inputSourceText(in(i))));  %#ok<AGROW>
            end
        end

        function d = rowDetail(obj, m)
            %ROWDETAIL  A row's Detail, minus the sentence that belongs elsewhere.
            %   Compared against Result.Narrative by EQUALITY rather than by
            %   row name: the two rows carrying this today are
            %   Tension-Ultimate and the Fig. 8 gate, but what actually
            %   makes the text redundant is that it is the same string the
            %   decisions panel already renders as structure - not which row
            %   it happens to sit on.
            d = m.Detail;
            r = obj.State.Result;
            if strlength(d) > 0 && strcmp(string(d), string(r.Narrative))
                d = "The Fig. 8 gate and the 5020B 4.4.1 system allowable " + ...
                    "that govern this check are laid out under Analysis " + ...
                    "decisions.";
            end
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
            %SCOPEFOOTERTEXT  What the table covers, and what it does not.
            %   It used to name the checks that had no row and explain
            %   where they went. There are none: all fifteen are displayed.
            %
            %   THE STATEMENT STAYS ANYWAY, because the thing it guards
            %   never went away -- a margin table that reads as a complete
            %   NASA-STD-5020B assessment when it is not is a compliance
            %   problem, and completeness of the CHECK LIST is not
            %   completeness of the assessment. TFSR 11 still requires
            %   yield and separation to account for combined loading and
            %   the tool implements neither (COMPLIANCE.md, TFSR 11
            %   PARTIAL), so a reader who takes fifteen green rows as a
            %   finished 5020B case is still wrong, just for a different
            %   reason than before.
            t = sprintf(['SCOPE: all 15 computed checks are shown - %d ' ...
                'margin rows plus the NASA-STD-5020B Fig. 8 gate, which ' ...
                'leads Analysis decisions because it selects a branch ' ...
                'rather than carrying a margin. NOT a complete 5020B ' ...
                'assessment even so: yield and separation under COMBINED ' ...
                'loading (TFSR 11) are required and not implemented.'], ...
                numel(gui2.ResultsPage.TableRows));
        end
    end

    % ---- Formatting -------------------------------------------------------
    methods (Static, Access = private)
        function s = formatValue(m, capOn)
            %FORMATVALUE  The Value cell for one row.
            %   Interaction is the exception and stays one: it reports a
            %   RATIO on the opposite scale, so its criterion is rendered
            %   with it and can never be read as a margin.
            %
            %   The rendering itself lives in gui2.MarginView, shared with
            %   the bulk grids so the same number cannot acquire two
            %   spellings in one application (GUI2_HARVEST.md A8). What
            %   stays here is picking WHICH of the two a row needs, which
            %   is a question about Result.Margins fields and belongs to
            %   this page.
            if m.Name == "Interaction"
                s = gui2.MarginView.rText(m.R);
                return
            end
            s = gui2.MarginView.msText(m.MS, capOn);
        end

        function s = readoutValue(src, name)
            %READOUTVALUE  One preload / design-load field, formatted.
            %   Absent field, non-numeric, empty and NaN all render the same
            %   em dash. Absent is the NORMAL case, not an error: Preload and
            %   DesignLoads both default to struct() with no fields, so any
            %   Result not built by engine.analyze arrives empty.
            %
            %   A1: an em dash, never a blank and never a zero. A zero here
            %   would read as "this joint has no preload", which is a
            %   statement the engine never made.
            s = char(8212);
            if ~isstruct(src) || ~isscalar(src) || ~isfield(src, char(name))
                return
            end
            v = src.(char(name));
            if ~isnumeric(v) || ~isscalar(v) || isnan(v)
                return
            end
            s = gui2.ResultsPage.withThousands(v);
        end

        function s = withThousands(v)
            %WITHTHOUSANDS  A force in lbf, 0 dp, comma-grouped.
            %   Zero decimals per GUI2_HARVEST.md Section D. Forces here run
            %   to five figures, and 15200 is materially harder to read
            %   against 1520 than 15,200 is.
            if isnan(v)
                % A1 again: an unknown allowable is an em dash, and in
                % particular is never a zero.
                s = char(8212);
                return
            end
            if isinf(v)
                if v > 0
                    s = '+inf';
                else
                    s = '-inf';
                end
                return
            end
            s = sprintf('%.0f', v);

            % Group the digits only - the sign must not collect a comma.
            neg = startsWith(s, '-');
            if neg
                s = s(2:end);
            end
            for k = (numel(s) - 3):-3:1
                s = [s(1:k) ',' s(k + 1:end)];
            end
            if neg
                s = ['-' s];
            end
        end

        function s = inputValueText(term)
            %INPUTVALUETEXT  One input's value and units.
            %   %.6g, NOT the two-decimal margin format: these numbers are
            %   here to be diffed against another tool's cell, and a
            %   thread-shear area (0.0234 in^2) or a shear strength
            %   (62000 psi) both have to survive the same formatter.
            %
            %   NaN renders as the same em dash the margin table uses for
            %   an unevaluated check — a term that was genuinely absent must
            %   never read as a zero that was used.
            if isnan(term.Value)
                s = string(gui2.MarginView.NotEvaluated);
                return
            end
            s = string(sprintf('%.6g', term.Value));
            if strlength(term.Units) > 0
                s = s + " " + term.Units;
            end
        end

        function s = inputSourceText(term)
            %INPUTSOURCETEXT  Where the number came from, parenthesised.
            %   Carried on every term because localising a disagreement
            %   means naming the upstream function or model property, not
            %   just the symbol.
            if strlength(term.Source) == 0
                s = "";
                return
            end
            s = "   (" + term.Source + ")";
        end

        function s = statusText(status)
            %STATUSTEXT  Engine status -> what the analyst reads.
            switch string(status)
                case "Pass"
                    s = 'Pass';
                case "Fail"
                    s = 'FAIL';
                case "Assured"
                    % The Separation-before-rupture gate. Reads as the
                    % branch it selected, matching what the decision panel
                    % below the table has always said, because it assesses
                    % nothing against an allowable.
                    s = 'Assured';
                case "NotAssured"
                    s = 'Not assured';
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

        function b = reportButton(obj)
            b = obj.ReportButton;
        end

        function b = exportButton(obj)
            b = obj.ExportButton;
        end

        function T = exportTable(obj)
            %EXPORTTABLE  Exactly what Export would write, without a file.
            T = obj.displayedTable();
        end

        function v = preloadValues(obj)
            v = obj.PreloadValues;
        end

        function v = designLoadValues(obj)
            v = obj.DesignLoadValues;
        end

        function s = readoutText(obj, name)
            %READOUTTEXT  The displayed string for one readout field, by name.
            %   Keyed by the engine field name so a test asks for "PpMin"
            %   rather than for an index into a panel - the panels are
            %   ordered by a private constant a test cannot reach anyway, and
            %   an index would silently follow a reordering to the wrong row.
            s = char(obj.readoutLabel(name).Text);
        end

        function s = readoutTooltip(obj, name)
            %READOUTTOOLTIP  The citation shown for one readout field, by name.
            s = char(obj.readoutLabel(name).Tooltip);
        end

        function h = readoutLabel(obj, name)
            %READOUTLABEL  The value label for one readout field, by name.
            %   Errors rather than returning empty on an unknown name: a test
            %   asking for a field that is not displayed has found a real
            %   disagreement, and a silent '' would read as a passing assert.
            k = find(gui2.ResultsPage.PreloadRows(:, 1) == name, 1);
            if ~isempty(k)
                h = obj.PreloadValues(k);
                return
            end
            k = find(gui2.ResultsPage.DesignLoadRows(:, 1) == name, 1);
            if isempty(k)
                error('gui2:ResultsPage:noSuchReadout', ...
                    'No readout row named "%s".', name);
            end
            h = obj.DesignLoadValues(k);
        end
    end
end
