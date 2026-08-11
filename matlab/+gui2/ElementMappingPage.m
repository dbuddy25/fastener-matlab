classdef ElementMappingPage < gui2.Page
    %ELEMENTMAPPINGPAGE  Which defined joint each FE element is analyzed as.
    %   Bulk step 2 of 4 (GUI2_SPEC.md Section 3 numbers the bulk workflow
    %   in the rail, and that is the only place the 1-4 scheme lives).
    %
    %   WHY THIS PAGE EXISTS AT ALL. A force export knows element ids and
    %   forces; it does not know the analyst's joint naming. So
    %   data.loadElementWorkbook returns JointName "" on every row on
    %   purpose, and engine.analyzeBulk writes a per-row Error naming THIS
    %   page when a joint name is missing. Nothing in the bulk workflow can
    %   run until these rows exist.
    %
    %   A VIEW OVER AppState.Mapping, which already existed, was already
    %   serialized into the case file's "mapping.elements" key, and is
    %   already retargeted by DefinedJointsPage when a joint is renamed.
    %   This page adds no storage and computes no margin.
    %
    %   THE THREE THINGS A MAPPING ROW CARRIES
    %     Element ID  a STRING, not a number - data.loadElements and
    %                 data.loadElementWorkbook both stringify ids, so a
    %                 numeric mapping could not be joined to imported
    %                 forces without a str2double that drops non-numeric
    %                 ids.
    %     Joint Name  the library key. Case-insensitive, because letting
    %                 "JT-A" and "jt-a" coexist is a mapping trap
    %                 (GUI2_HARVEST.md A13).
    %     Pattern ID  the physical joint INSTANCE, optional. Blank is
    %                 meaningful rather than missing: engine.analyzeBulk
    %                 falls back to the joint name as the pattern key, so
    %                 two brackets sharing one joint definition need
    %                 distinct pattern ids or their elements aggregate into
    %                 one oversized pattern, Eq. 84's nf check fails, and
    %                 joint slip is left NotEvaluated.
    %
    %   DUPLICATE ELEMENT IDS ARE ALLOWED BUT FLAGGED. Blocking them would
    %   fight CSV import and paste, which is where a 200-element mapping
    %   actually comes from; silently keeping them produces wrong bulk
    %   results, since the first matching row wins. So they are loud and
    %   editable instead.
    %
    %   Backed by AppState.Mapping. Listens to ElementsChanged (its own
    %   writes, and the forces import once step 7 lands) and
    %   JointLibraryChanged (the joint picker and the unknown-name check
    %   both track the library).

    properties (Access = private)
        Grid
        Table
        Banner              % empty-state note, shares the table's cell
        SummaryLabel
        WarnBar             % unknown-joint bar, height-toggled
        WarnLabel
        WarnCreateButton
        WarnDismissButton
        AssignDropDown
        AssignPatternField
        AssignButton
        ImportForcesButton
        ImportCsvButton
        ExportCsvButton
        BulkAddToolbarButton
        ClearAllButton

        % Set of unknown joint names the warn bar was dismissed for. A NEW
        % unknown name re-shows it; the same one stays hidden.
        WarnDismissedKey (1,1) string = ""

        StyleDup
        StyleUnknown

        % The bulk-add dialog, if one is open. A uifigure cannot be a child
        % of the app window, so nothing closes it when the app is deleted —
        % it has to be tracked and torn down explicitly, or a test that
        % opens one leaks a window into every test that follows.
        BulkDialog
        BulkTextArea
        BulkDropDown
        BulkDetectLabel
        BulkAddButton
    end

    properties (Constant, Access = private)
        % Row 2 of the grid: the warn bar's two heights.
        WarnBarH = 34

        % Import error reports stop here and say how many were dropped
        % (GUI_PORT_SPEC.md Section 7.4 point 3).
        MaxReportedErrors = 20
    end

    methods
        function obj = ElementMappingPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "ElementMapping";
        end

        function t = title(~)
            t = "Element Mapping";
        end

        function delete(obj)
            %DELETE  Take any open bulk-add dialog down with the page.
            obj.closeBulkDialog();
        end

        function s = railStatus(obj)
            %RAILSTATUS  A check mark once the case carries a mapping.
            if isempty(obj.State.Mapping)
                s = "";
            else
                s = "loaded";
            end
        end

        function build(obj, parent)
            g = uigridlayout(parent, [6 1]);
            g.RowHeight   = {'fit', 30, 0, '1x', 'fit', 22};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 6;
            obj.Grid = g;

            obj.addBanner(g, 1, 1, ...
                ['Bulk step 2 of 4. This page is the authority on which ' ...
                 'defined joint each FE element is analyzed as — a force ' ...
                 'file carries element IDs and forces, not joint names. ' ...
                 'Case-scoped: the mapping is saved in the case file.']);

            % Cell styles built ONCE and batch-applied after a removeStyle
            % on every refresh, the discipline the margin table uses.
            obj.StyleDup = uistyle( ...
                'BackgroundColor', gui2.palette('bannerWarnBg'), ...
                'FontColor',       gui2.palette('bannerWarnFg'), ...
                'FontWeight',      'bold');
            obj.StyleUnknown = uistyle( ...
                'BackgroundColor', gui2.palette('requiredBlankBg'));

            obj.buildToolbar(g, 2);
            obj.buildWarnBar(g, 3);
            obj.buildTable(g, 4);
            obj.buildAssignRow(g, 5);

            obj.SummaryLabel = uilabel(g, 'Text', '');
            obj.SummaryLabel.Layout.Row    = 6;
            obj.SummaryLabel.Layout.Column = 1;

            obj.listenTo('ElementsChanged',     @() obj.refresh());
            obj.listenTo('JointLibraryChanged', @() obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            %REFRESH  Sync the whole page from AppState. The ONLY populate
            %   path: every mutation, every library change and every
            %   File > Open funnels through here, so a rejected edit
            %   reverts by construction rather than by an undo branch.
            %   Never marks dirty — repopulating is not editing.
            if isempty(obj.Table) || ~isvalid(obj.Table)
                return   % not built yet
            end
            rows = obj.rows();
            n    = numel(rows);

            obj.renderTable(rows);

            [dupMask, unknownMask, blankMask] = obj.problemMasks(rows);
            obj.applyStyles(dupMask, unknownMask | blankMask);
            obj.renderSummary(rows, dupMask, unknownMask, blankMask);
            obj.renderWarnBar(rows, unknownMask);
            obj.renderAssignControls(n);
            obj.renderImportForcesButton();
        end
    end

    % ---- Construction -----------------------------------------------------
    methods (Access = private)
        function buildToolbar(obj, parent, row)
            bar = uigridlayout(parent, [1 6]);
            bar.Layout.Row    = row;
            bar.Layout.Column = 1;
            bar.RowHeight     = {'1x'};
            bar.ColumnWidth   = {'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
            bar.Padding       = [0 0 0 0];
            bar.ColumnSpacing = 8;

            b = uibutton(bar, 'push', 'Text', 'Import CSV...', ...
                'ButtonPushedFcn', @(~, ~) obj.onImportCsv());
            b.Tooltip = ['Import an element_id, joint_name, pattern_id ' ...
                'CSV. Rows are processed independently — one bad line ' ...
                'never aborts the import; errors are reported with line ' ...
                'numbers.'];
            b.Layout.Row = 1;  b.Layout.Column = 1;
            obj.ImportCsvButton = b;

            b = uibutton(bar, 'push', 'Text', 'Export CSV...', ...
                'ButtonPushedFcn', @(~, ~) obj.onExportCsv());
            b.Tooltip = ['Write the current mapping as element_id, ' ...
                'joint_name, pattern_id. On an EMPTY mapping this writes ' ...
                'the commented template shape instead — the answer to ' ...
                '"what columns does it want?".'];
            b.Layout.Row = 1;  b.Layout.Column = 2;
            obj.ExportCsvButton = b;

            b = uibutton(bar, 'push', 'Text', 'Import IDs from Forces', ...
                'ButtonPushedFcn', @(~, ~) obj.onImportFromForces());
            b.Layout.Row = 1;  b.Layout.Column = 3;
            obj.ImportForcesButton = b;   % Enable/Tooltip set by refresh

            b = uibutton(bar, 'push', 'Text', '+ Bulk Add...', ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onBulkAdd());
            b.Tooltip = ['Paste ONE column of element IDs (commas, ' ...
                'spaces, tabs or newlines) to assign them all to one ' ...
                'joint, or TWO columns of ID + joint name straight from ' ...
                'Excel. The dialog says what it detected before anything ' ...
                'is added; invalid tokens are reported individually while ' ...
                'the valid ones still land.'];
            b.Layout.Row = 1;  b.Layout.Column = 4;
            obj.BulkAddToolbarButton = b;

            b = uibutton(bar, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(~, ~) obj.onClearAll());
            b.Tooltip = ['Remove every mapping row (asks first). The ' ...
                'defined joints themselves are untouched.'];
            b.Layout.Row = 1;  b.Layout.Column = 5;
            obj.ClearAllButton = b;
        end

        function buildWarnBar(obj, parent, row)
            wb = uigridlayout(parent, [1 3]);
            wb.Layout.Row      = row;
            wb.Layout.Column   = 1;
            wb.RowHeight       = {'1x'};
            wb.ColumnWidth     = {'1x', 'fit', 'fit'};
            wb.Padding         = [6 2 6 2];
            wb.ColumnSpacing   = 8;
            wb.BackgroundColor = gui2.palette('bannerWarnBg');
            wb.Visible         = 'off';
            obj.WarnBar = wb;

            lb = uilabel(wb, 'Text', '');
            lb.FontColor     = gui2.palette('bannerWarnFg');
            lb.FontWeight    = 'bold';
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            obj.WarnLabel = lb;

            b = uibutton(wb, 'push', 'Text', 'Create Missing Joints', ...
                'ButtonPushedFcn', @(~, ~) obj.onCreateMissing());
            b.Tooltip = ['Add a placeholder joint for every unknown name. ' ...
                'They appear on Defined Joints immediately and are saved ' ...
                'with the case — edit them there.'];
            b.Layout.Row = 1;  b.Layout.Column = 2;
            obj.WarnCreateButton = b;

            b = uibutton(wb, 'push', 'Text', 'Dismiss', ...
                'ButtonPushedFcn', @(~, ~) obj.onWarnDismiss());
            b.Tooltip = ['Hide this bar until the set of unknown joint ' ...
                'names changes. The summary line below the table stays red.'];
            b.Layout.Row = 1;  b.Layout.Column = 3;
            obj.WarnDismissButton = b;
        end

        function buildTable(obj, parent, row)
            %BUILDTABLE  gui2's first EDITABLE uitable.
            %   Page.bindEdit does not reach this: it wires
            %   ValueChangedFcn-style controls, and a uitable reports edits
            %   through CellEditCallback. So onCellEdited calls markDirty
            %   itself — the one place in gui2 outside the funnel, and the
            %   reason the call sits on the success path only.
            t = uitable(parent);
            t.Layout.Row     = row;
            t.Layout.Column  = 1;
            t.ColumnName     = {'Element ID', 'Joint Name', ...
                                'Pattern ID', 'Remove'};
            t.RowName        = {};
            t.ColumnWidth    = {120, '1x', 130, 70};
            t.ColumnFormat   = {'char', 'char', 'char', 'logical'};
            t.ColumnEditable = [true true true true];
            % Row selection, stated rather than left to the default: the
            % bulk-assign row acts on WHOLE rows, and "assign to selected
            % rows" reads wrong if clicking one cell selects one cell.
            % Editing is independent of selection type.
            t.SelectionType = 'row';
            t.CellEditCallback = @(~, evt) obj.onCellEdited(evt);
            t.Tooltip = ['One row per FE element. Joint Name is a ' ...
                'dropdown of the defined joints. Pattern ID is optional — ' ...
                'blank means this joint name is one physical bolt ' ...
                'pattern; set it when one joint definition is used by ' ...
                'several separate patterns. Tick Remove to delete a row. ' ...
                'Select rows (drag / Shift / Ctrl) to bulk-assign below. ' ...
                'Amber = duplicate element ID, pale red = joint name ' ...
                'blank or not in the library.'];
            obj.Table = t;

            % Empty state and table share the cell, toggled by Visible.
            banner = uilabel(parent, 'Text', ['No elements mapped yet. ' ...
                'Map each FE element ID to a defined joint so the bulk ' ...
                'run knows which joint to analyze with that element''s ' ...
                'forces.  ' ...
                '+ Bulk Add... pastes a column of element IDs onto one ' ...
                'joint (or two columns of ID + joint name). Import CSV... ' ...
                'loads an element_id, joint_name, pattern_id file — and ' ...
                'Export CSV... on an empty mapping writes that shape for ' ...
                'you. Import IDs from Forces bootstraps the table from ' ...
                'forces imported on Element Forces (bulk step 3).']);
            banner.Layout.Row        = row;
            banner.Layout.Column     = 1;
            banner.WordWrap          = 'on';
            banner.VerticalAlignment = 'top';
            banner.BackgroundColor   = gui2.palette('bannerInfoBg');
            banner.FontColor         = gui2.palette('bannerInfoFg');
            banner.Visible           = 'off';
            obj.Banner = banner;
        end

        function buildAssignRow(obj, parent, row)
            ab = uigridlayout(parent, [1 6]);
            ab.Layout.Row    = row;
            ab.Layout.Column = 1;
            ab.RowHeight     = {'fit'};
            ab.ColumnWidth   = {'fit', 200, 'fit', 130, 'fit', '1x'};
            ab.Padding       = [0 0 0 0];
            ab.ColumnSpacing = 8;

            lb = uilabel(ab, 'Text', 'Assign to selected rows:');
            lb.Layout.Row = 1;  lb.Layout.Column = 1;

            dd = uidropdown(ab, 'Items', {'(no joints defined)'});
            dd.Tooltip = 'The joint the Assign button writes into every selected row.';
            dd.Layout.Row = 1;  dd.Layout.Column = 2;
            obj.AssignDropDown = dd;

            lb = uilabel(ab, 'Text', 'Pattern ID:');
            lb.Layout.Row = 1;  lb.Layout.Column = 3;

            f = uieditfield(ab, 'text');
            f.Tooltip = ['Optional. Written to the selected rows only when ' ...
                'non-blank — leave it empty to assign the joint and leave ' ...
                'existing pattern IDs alone. This is how one joint ' ...
                'definition is split across several physical patterns.'];
            f.Layout.Row = 1;  f.Layout.Column = 4;
            obj.AssignPatternField = f;

            b = uibutton(ab, 'push', 'Text', 'Assign', ...
                'ButtonPushedFcn', @(~, ~) obj.onAssignSelected());
            b.Tooltip = ['Set the chosen joint on every selected table row ' ...
                '(select rows first — drag, Shift or Ctrl).'];
            b.Layout.Row = 1;  b.Layout.Column = 5;
            obj.AssignButton = b;
        end
    end

    % ---- Rendering --------------------------------------------------------
    methods (Access = private)
        function renderTable(obj, rows)
            choices = obj.jointChoices();
            n = numel(rows);

            % A cell-of-char ColumnFormat renders as an in-cell dropdown.
            % With no joints defined it stays a plain text column, and a
            % typed name then goes through the unknown-joint flow.
            if isempty(choices)
                fmt2 = 'char';
            else
                fmt2 = choices;
            end

            d = cell(n, 4);
            for i = 1:n
                d(i, :) = {char(rows(i).ElementID), ...
                           char(rows(i).JointName), ...
                           char(rows(i).PatternId), false};
            end
            obj.Table.ColumnFormat = {'char', fmt2, 'char', 'logical'};
            obj.Table.Data         = d;
            obj.Table.Selection    = [];   % old row indices no longer apply

            obj.Table.Visible  = matlab.lang.OnOffSwitchState(n > 0);
            obj.Banner.Visible = matlab.lang.OnOffSwitchState(n == 0);
        end

        function applyStyles(obj, dupMask, unknownOrBlank)
            % removeStyle first, then ONE addStyle per group with an Nx2
            % [row col] index matrix. Wrapped, because a styling failure
            % must not take the page down: the summary line and the warn
            % bar below say the same thing in words.
            try
                removeStyle(obj.Table);
                if any(dupMask)
                    addStyle(obj.Table, obj.StyleDup, 'cell', ...
                        gui2.ElementMappingPage.cellIndex(dupMask, 1));
                end
                if any(unknownOrBlank)
                    addStyle(obj.Table, obj.StyleUnknown, 'cell', ...
                        gui2.ElementMappingPage.cellIndex(unknownOrBlank, 2));
                end
            catch
                % Styling unavailable — see above.
            end
        end

        function renderSummary(obj, rows, dupMask, unknownMask, blankMask)
            %RENDERSUMMARY  Three visually distinct states.
            %   Empty, broken and clean must never look alike, and a
            %   problem must never render muted (GUI2_HARVEST.md).
            n = numel(rows);
            if n == 0
                obj.SummaryLabel.Text       = 'No elements mapped yet.';
                obj.SummaryLabel.FontColor  = gui2.palette('mutedText');
                obj.SummaryLabel.FontWeight = 'normal';
                return
            end

            names   = obj.jointNames(rows);
            nDup    = nnz(dupMask);
            nUnknwn = nnz(unknownMask);
            nBlank  = nnz(blankMask);

            txt = sprintf('%d element(s) -> %d joint(s)', n, ...
                numel(unique(lower(names(strlength(strtrim(names)) > 0)))));
            if nDup > 0
                txt = sprintf('%s   |   WARNING: %d duplicate element ID(s)', ...
                    txt, nDup);
            end
            if nBlank > 0
                txt = sprintf('%s   |   %d row(s) have no joint assigned', ...
                    txt, nBlank);
            end
            if nUnknwn > 0
                txt = sprintf(['%s   |   %d row(s) reference a joint not ' ...
                    'in the library'], txt, nUnknwn);
            end

            if nUnknwn > 0 || nBlank > 0
                obj.SummaryLabel.FontColor  = gui2.palette('statusFail');
                obj.SummaryLabel.FontWeight = 'bold';
            elseif nDup > 0
                obj.SummaryLabel.FontColor  = gui2.palette('statusWarn');
                obj.SummaryLabel.FontWeight = 'bold';
            else
                txt = [txt '   —   no issues'];
                obj.SummaryLabel.FontColor  = gui2.palette('mutedText');
                obj.SummaryLabel.FontWeight = 'normal';
            end
            obj.SummaryLabel.Text = txt;
        end

        function renderWarnBar(obj, rows, unknownMask)
            %RENDERWARNBAR  Dismissal holds only while the unknown SET is
            %   unchanged — a new bad name re-shows the bar. Dismissing
            %   never touches the summary line, which stays red.
            names   = obj.jointNames(rows);
            unknown = names(unknownMask);
            key     = strjoin(unique(lower(unknown)), '|');   % "" when none

            rh = obj.Grid.RowHeight;
            if isempty(unknown)
                obj.WarnBar.Visible    = 'off';
                rh{3}                  = 0;
                obj.WarnDismissedKey   = "";
            elseif strcmp(key, char(obj.WarnDismissedKey))
                obj.WarnBar.Visible = 'off';
                rh{3}               = 0;
            else
                [~, firstIdx] = unique(lower(unknown), 'stable');
                shown = unknown(firstIdx);
                obj.WarnLabel.Text = sprintf('%d joint(s) not in library: %s', ...
                    numel(shown), ...
                    char(gui2.ElementMappingPage.idListSuffix(shown, false)));
                obj.WarnBar.Visible = 'on';
                rh{3}               = obj.WarnBarH;
            end
            obj.Grid.RowHeight = rh;
        end

        function renderAssignControls(obj, n)
            choices = obj.jointChoices();
            if isempty(choices)
                obj.AssignDropDown.Items  = {'(no joints defined)'};
                obj.AssignDropDown.Enable = 'off';
                obj.AssignButton.Enable   = 'off';
                return
            end
            prev = obj.AssignDropDown.Value;
            obj.AssignDropDown.Items = choices;
            if any(strcmp(choices, prev))
                obj.AssignDropDown.Value = prev;
            end
            obj.AssignDropDown.Enable = 'on';
            obj.AssignButton.Enable   = matlab.lang.OnOffSwitchState(n > 0);
        end

        function renderImportForcesButton(obj)
            %RENDERIMPORTFORCESBUTTON  Live exactly while forces exist.
            %   A dead button with no explanation reads as a bug, so the
            %   tooltip says why it is off and where the fix is.
            if isempty(obj.forceElementIds())
                obj.ImportForcesButton.Enable  = 'off';
                obj.ImportForcesButton.Tooltip = ['Bootstraps the mapping ' ...
                    'from the element IDs in the imported forces. ' ...
                    'Disabled — no element forces are imported yet ' ...
                    '(Element Forces, bulk step 3).'];
            else
                obj.ImportForcesButton.Enable  = 'on';
                obj.ImportForcesButton.Tooltip = ['Collects the unique ' ...
                    'element IDs from the imported forces, asks which ' ...
                    'joint to assign, and adds or updates mapping rows.'];
            end
        end
    end

    % ---- Reading state ----------------------------------------------------
    methods (Access = private)
        function rows = rows(obj)
            %ROWS  The mapping in canonical shape, whoever wrote it.
            rows = gui2.AppState.normalizeMapping(obj.State.Mapping);
        end

        function names = jointNames(~, rows)
            if isempty(rows)
                names = strings(1, 0);
            else
                names = string({rows.JointName});
            end
        end

        function ids = elementIds(~, rows)
            if isempty(rows)
                ids = strings(1, 0);
            else
                ids = string({rows.ElementID});
            end
        end

        function [dupMask, unknownMask, blankMask] = problemMasks(obj, rows)
            n   = numel(rows);
            ids = obj.elementIds(rows);
            nm  = obj.jointNames(rows);

            dupMask = false(1, n);
            if n > 0
                [u, ~, ic] = unique(ids);
                counts  = accumarray(ic(:), 1);
                dupMask = ismember(ids, u(counts > 1));
            end

            blankMask   = strlength(strtrim(nm)) == 0;
            unknownMask = false(1, n);
            for i = 1:n
                if ~blankMask(i)
                    unknownMask(i) = isempty(obj.findJoint(nm(i)));
                end
            end
        end

        function idx = findJoint(obj, name)
            %FINDJOINT  Library index for a joint name ([] = none).
            %   Case-insensitive ON PURPOSE — the library key is the name,
            %   and letting "JT-A" and "jt-a" coexist is a mapping trap.
            idx = [];
            lib = obj.State.JointLibrary;
            if isempty(lib)
                return
            end
            hit = find(strcmpi(strtrim(string({lib.Name})), ...
                               strtrim(string(name))), 1);
            if ~isempty(hit)
                idx = hit;
            end
        end

        function names = jointChoices(obj)
            %JOINTCHOICES  Defined-joint names, alphabetical, as cellstr.
            %   Sorted independently of the Defined Joints list's own
            %   order, which the analyst reorders freely — a name picker
            %   sorts.
            lib = obj.State.JointLibrary;
            if isempty(lib)
                names = {};
                return
            end
            nm = string({lib.Name});
            [~, order] = sort(lower(nm));
            names = cellstr(nm(order));
        end

        function ids = forceElementIds(obj)
            %FORCEELEMENTIDS  Unique element ids from the imported forces.
            %   Empty until Element Forces (step 7) fills AppState.Elements.
            ids = strings(1, 0);
            el  = obj.State.Elements;
            if ~isstruct(el) || ~isfield(el, 'Rows') || isempty(el.Rows)
                return
            end
            ids = unique(string({el.Rows.ElementId}), 'stable');
        end

        function fig = figureHandle(obj)
            fig = ancestor(obj.Root, 'figure');
        end

        function closeBulkDialog(obj)
            if ~isempty(obj.BulkDialog) && isvalid(obj.BulkDialog)
                delete(obj.BulkDialog);
            end
            obj.BulkDialog      = [];
            obj.BulkTextArea    = [];
            obj.BulkDropDown    = [];
            obj.BulkDetectLabel = [];
            obj.BulkAddButton   = [];
        end
    end

    % ---- Writing state ----------------------------------------------------
    methods (Access = private)
        function commit(obj, rows, statusMsg)
            %COMMIT  THE write path: state, dirty, status. One place, so no
            %   mutation can forget the dirty flag (the uitable's
            %   CellEditCallback cannot use Page.bindEdit).
            obj.State.Mapping = rows;    % fires ElementsChanged -> refresh
            obj.State.markDirty();
            if nargin > 2 && strlength(statusMsg) > 0
                obj.setStatus(statusMsg);
            end
        end

        function created = createStubJoints(obj, names)
            %CREATESTUBJOINTS  Placeholder library entries from a name list.
            %   "Create the joints this mapping refers to." The entries
            %   show up on Defined Joints immediately and are saved with
            %   the case, with no page-to-page call: writing JointLibrary
            %   fires JointLibraryChanged and that page refreshes itself.
            arguments
                obj
                names (1, :) string
            end
            created = strings(1, 0);
            lib = obj.State.JointLibrary;
            % Checked against the LOCAL library, not against State: nothing
            % is written back until the loop ends, so asking State would
            % let "Bracket" and "bracket" in the same list both be created
            % — the case-insensitive collision this check exists to stop.
            existing = strings(1, 0);
            if ~isempty(lib)
                existing = strtrim(string({lib.Name}));
            end
            for nm = names
                t = strtrim(nm);
                if strlength(t) == 0 || any(strcmpi(existing, t))
                    continue
                end
                existing(end + 1) = t; %#ok<AGROW>
                % A stub is deliberately a NAME and nothing else. Seeding
                % geometry would put numbers in front of an analyst that
                % nobody chose, and the required-field gate on Joint
                % Config is what makes the placeholder obvious.
                lib(end + 1) = struct('Name', t, 'Joint', model.Joint(Name = t)); %#ok<AGROW>
                created(end + 1) = t; %#ok<AGROW>
            end
            if ~isempty(created)
                obj.State.JointLibrary = lib;
                obj.State.markDirty();
            end
        end
    end

    % ---- Cell editing -----------------------------------------------------
    methods (Access = private)
        function onCellEdited(obj, evt)
            %ONCELLEDITED  One committed cell -> AppState.Mapping.
            %   On success OR failure the page re-renders from state, which
            %   both canonicalises accepted values and reverts rejected
            %   ones. Nothing is mutated in the widget.
            rows = obj.rows();
            try
                r = evt.Indices(1);
                c = evt.Indices(2);
                if r < 1 || r > numel(rows)
                    error('gui2:ElementMappingPage:staleRow', ...
                        'Stale table row — the view will refresh.');
                end
                switch c
                    case 1
                        rows(r).ElementID = obj.validatedId(evt, 'Element ID');
                    case 2
                        obj.editJointName(rows, r, evt);
                        return   % continuation may still be outstanding
                    case 3
                        % Pattern ID: BLANK IS LEGAL and means "this joint
                        % name is one pattern", so only the shape is
                        % checked, not the presence.
                        rows(r).PatternId = obj.validatedPattern(evt);
                    case 4
                        if gui2.ElementMappingPage.isTicked(evt.NewData)
                            removed = rows(r).ElementID;
                            rows(r) = [];
                            obj.commit(rows, sprintf( ...
                                'Removed element %s from the mapping.', removed));
                            return
                        end
                        obj.refresh();   % untick: nothing to commit
                        return
                    otherwise
                        error('gui2:ElementMappingPage:badColumn', ...
                            'Unknown mapping column %d.', c);
                end
            catch err
                uialert(obj.figureHandle(), err.message, 'Edit rejected');
                obj.refresh();
                return
            end
            obj.commit(rows);
        end

        function v = validatedId(~, evt, label)
            raw = strtrim(string(evt.NewData));
            if strlength(raw) == 0
                error('gui2:ElementMappingPage:blankId', ...
                    '%s cannot be blank.', label);
            end
            if ~isempty(regexp(char(raw), '[\s,]', 'once'))
                error('gui2:ElementMappingPage:badId', ...
                    ['''%s'' cannot contain spaces or commas — those ' ...
                     'separate IDs when pasting and importing.'], raw);
            end
            v = raw;
        end

        function v = validatedPattern(~, evt)
            raw = strtrim(string(evt.NewData));
            if contains(raw, ",")
                error('gui2:ElementMappingPage:badPattern', ...
                    'A pattern ID cannot contain a comma.');
            end
            v = raw;
        end

        function editJointName(obj, rows, r, evt)
            nm = strtrim(string(evt.NewData));
            if strlength(nm) == 0
                uialert(obj.figureHandle(), ...
                    'Joint name cannot be blank.', 'Edit rejected');
                obj.refresh();
                return
            end
            idx = obj.findJoint(nm);
            if isempty(idx)
                obj.askUnknownJoint(nm, ...
                    @(choice) obj.finishJointEdit(rows, r, nm, choice));
                return
            end
            rows(r).JointName = obj.State.JointLibrary(idx).Name;  % canonical case
            obj.commit(rows);
        end

        function finishJointEdit(obj, rows, r, nm, choice)
            switch choice
                case "Cancel"
                    obj.refresh();       % re-render reverts the typed cell
                    return
                case "Create All"
                    obj.createStubJoints(nm);
                    idx = obj.findJoint(nm);
                    if ~isempty(idx)
                        nm = obj.State.JointLibrary(idx).Name;
                    end
                otherwise                % Skip: keep the name, flag the row
                    obj.WarnDismissedKey = "";   % re-arm the warn bar
            end
            if r >= 1 && r <= numel(rows)
                rows(r).JointName = nm;
                obj.commit(rows);
            else
                obj.refresh();
            end
        end

        function askUnknownJoint(obj, name, continuation)
            %ASKUNKNOWNJOINT  Create All / Skip / Cancel, NON-BLOCKING.
            %   uiconfirm's return-value form blocks, and a blocking
            %   confirm deadlocks the App Testing Framework — the press
            %   that opened it never returns. Every confirm in gui2 is
            %   continuation-passing for that reason.
            n = numel(name);
            if n == 1
                msg = sprintf(['"%s" is not in the defined-joints ' ...
                    'library.\n\nCreate All adds it as a placeholder ' ...
                    'joint (edit it on Defined Joints). Skip keeps the ' ...
                    'name and flags the row. Cancel reverts.'], name);
            else
                msg = sprintf(['%d joint name(s) are not in the ' ...
                    'defined-joints library: %s.\n\nCreate All adds a ' ...
                    'placeholder for each (edit them on Defined Joints). ' ...
                    'Skip keeps the names and flags those rows. Cancel ' ...
                    'abandons the whole operation.'], n, ...
                    gui2.ElementMappingPage.idListSuffix(name, false));
            end
            uiconfirm(obj.figureHandle(), msg, 'Unknown Joint', ...
                'Options',       {'Create All', 'Skip', 'Cancel'}, ...
                'DefaultOption', 'Create All', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) continuation(string(evt.SelectedOption)));
        end
    end

    % ---- Toolbar and bulk-assign actions ----------------------------------
    methods (Access = private)
        function onAssignSelected(obj)
            %ONASSIGNSELECTED  The dropdown joint (and optionally a pattern
            %   id) onto every selected row.
            sel = obj.selectedRows();
            if isempty(sel)
                uialert(obj.figureHandle(), ['Select one or more rows in ' ...
                    'the table first (drag, Shift or Ctrl), then press ' ...
                    'Assign.'], 'No rows selected', 'Icon', 'info');
                return
            end
            jn  = string(obj.AssignDropDown.Value);
            if isempty(obj.findJoint(jn))
                return   % the "(no joints defined)" placeholder
            end
            pat  = strtrim(string(obj.AssignPatternField.Value));
            rows = obj.rows();
            sel  = sel(sel >= 1 & sel <= numel(rows));
            if isempty(sel)
                return
            end
            for r = reshape(sel, 1, [])
                rows(r).JointName = jn;
                if strlength(pat) > 0
                    rows(r).PatternId = pat;
                end
            end
            if strlength(pat) > 0
                msg = sprintf('Assigned "%s" (pattern "%s") to %d row(s).', ...
                    jn, pat, numel(sel));
            else
                msg = sprintf('Assigned "%s" to %d row(s).', jn, numel(sel));
            end
            obj.commit(rows, msg);
        end

        function onCreateMissing(obj)
            rows    = obj.rows();
            [~, unknownMask] = obj.problemMasks(rows);
            names   = obj.jointNames(rows);
            created = obj.createStubJoints(unique(names(unknownMask)));
            if isempty(created)
                return
            end
            % Point the rows at the canonical spelling that was created,
            % so a case-only difference stops reading as unknown.
            for i = 1:numel(rows)
                idx = obj.findJoint(rows(i).JointName);
                if ~isempty(idx)
                    rows(i).JointName = obj.State.JointLibrary(idx).Name;
                end
            end
            obj.commit(rows, sprintf('Created %d placeholder joint(s).', ...
                numel(created)));
        end

        function onWarnDismiss(obj)
            %ONWARNDISMISS  Hide the bar, keep the summary line red.
            rows  = obj.rows();
            [~, unknownMask] = obj.problemMasks(rows);
            names = obj.jointNames(rows);
            obj.WarnDismissedKey = ...
                string(strjoin(unique(lower(names(unknownMask))), '|'));
            obj.refresh();
        end

        function onClearAll(obj)
            if isempty(obj.State.Mapping)
                return
            end
            uiconfirm(obj.figureHandle(), sprintf( ...
                ['Remove all %d mapping row(s)? The defined joints ' ...
                 'themselves are untouched.'], numel(obj.State.Mapping)), ...
                'Clear mapping', ...
                'Options',       {'Clear All', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.onClearAllAnswered(evt));
        end

        function onClearAllAnswered(obj, evt)
            if ~strcmp(evt.SelectedOption, 'Clear All')
                return
            end
            obj.WarnDismissedKey = "";
            obj.commit(gui2.AppState.emptyMapping(), 'Mapping cleared.');
        end

        function rowsIdx = selectedRows(obj)
            %SELECTEDROWS  Row indices behind the table's Selection.
            %   Cell selection gives Nx2 [row col] pairs; a row-selection
            %   table gives a plain vector. Handle both rather than pin a
            %   SelectionType the table might not keep.
            sel = obj.Table.Selection;
            if isempty(sel)
                rowsIdx = [];
            elseif size(sel, 2) >= 2
                rowsIdx = unique(sel(:, 1));
            else
                rowsIdx = unique(sel(:));
            end
        end
    end

    % ---- Bulk add / Import IDs from Forces --------------------------------
    methods (Access = private)
        function onBulkAdd(obj)
            obj.openBulkAddDialog(strings(1, 0), 'Bulk Add Elements');
        end

        function onImportFromForces(obj)
            %ONIMPORTFROMFORCES  Bootstrap the mapping from imported forces.
            %   The ids pre-fill the SAME dialog, because a mapping row
            %   cannot have a blank joint name — so the user must pick one,
            %   and that prompt is exactly what this dialog is.
            ids = obj.forceElementIds();
            if isempty(ids)
                uialert(obj.figureHandle(), ['No element forces are ' ...
                    'imported yet — import them on Element Forces (bulk ' ...
                    'step 3) first.'], 'No forces imported', 'Icon', 'info');
                return
            end
            obj.openBulkAddDialog(ids, 'Import IDs from Forces');
        end

        function openBulkAddDialog(obj, prefill, dialogName)
            %OPENBULKADDDIALOG  Joint picker + paste area.
            %   uiconfirm has no input controls, so this is the page's one
            %   custom dialog. It is a SEPARATE uifigure rather than a
            %   modal blocking call: the Add button runs a callback and the
            %   dialog closes itself, so nothing here can deadlock a test.
            choices = obj.jointChoices();
            if isempty(choices)
                uialert(obj.figureHandle(), ['No defined joints yet — ' ...
                    'this dialog assigns pasted element IDs to defined ' ...
                    'joints. Define joints first (Defined Joints, bulk ' ...
                    'step 1), or Import CSV..., which offers to create ' ...
                    'missing joints.'], 'No joints defined', 'Icon', 'info');
                return
            end

            obj.closeBulkDialog();   % never two at once
            d = uifigure('Name', char(dialogName), 'Visible', 'off');
            obj.BulkDialog = d;
            % MATLAB cannot index a function-call result, so the figure
            % handle goes to a local before its Position is read.
            fig = obj.figureHandle();
            fp  = fig.Position;
            d.Position = [fp(1) + max(0, (fp(3) - 460) / 2), ...
                          fp(2) + max(0, (fp(4) - 420) / 2), 460, 420];

            dg = uigridlayout(d, [6 1]);
            dg.RowHeight   = {22, 26, 'fit', '1x', 'fit', 32};
            dg.ColumnWidth = {'1x'};
            dg.Padding     = [8 8 8 8];
            dg.RowSpacing  = 4;

            lb = uilabel(dg, 'Text', 'Assign every pasted ID to joint:');
            lb.Layout.Row = 1;

            dd = uidropdown(dg, 'Items', choices);
            dd.Layout.Row = 2;
            prev = obj.AssignDropDown.Value;
            if any(strcmp(choices, prev))
                dd.Value = prev;
            end

            note = uilabel(dg, 'WordWrap', 'on', 'Text', ...
                ['Paste ONE column of element IDs, or TWO columns of ' ...
                 'ID + joint name (tab, comma, or two or more spaces — ' ...
                 'tab is what Excel pastes). Two columns disables the ' ...
                 'dropdown above, because the paste supplies the names. ' ...
                 'Pattern IDs are not part of a paste; set them in the ' ...
                 'table or import a CSV.']);
            note.Layout.Row  = 3;
            note.FontColor   = gui2.palette('mutedText');

            ta = uitextarea(dg);
            ta.Layout.Row = 4;
            if ~isempty(prefill)
                ta.Value = cellstr(prefill(:));
            end

            det = uilabel(dg, 'WordWrap', 'on', 'Text', '');
            det.Layout.Row = 5;

            btns = uigridlayout(dg, [1 3]);
            btns.Layout.Row   = 6;
            btns.RowHeight    = {'1x'};
            btns.ColumnWidth  = {'1x', 'fit', 'fit'};
            btns.Padding      = [0 0 0 0];
            btns.ColumnSpacing = 8;

            addBtn = uibutton(btns, 'push', 'Text', 'Add', ...
                'FontWeight', 'bold');
            addBtn.Layout.Column = 2;
            cancelBtn = uibutton(btns, 'push', 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~, ~) obj.closeBulkDialog());
            cancelBtn.Layout.Column = 3;

            % The detection line restates what Add will do BEFORE it runs —
            % the dialog must never silently guess which shape it got.
            ta.ValueChangedFcn = @(~, ~) ...
                gui2.ElementMappingPage.updateDetectLabel(ta, dd, det);
            addBtn.ButtonPushedFcn = @(~, ~) obj.onBulkAddCommit(d, ta, dd);
            gui2.ElementMappingPage.updateDetectLabel(ta, dd, det);

            obj.BulkTextArea    = ta;
            obj.BulkDropDown    = dd;
            obj.BulkDetectLabel = det;
            obj.BulkAddButton   = addBtn;

            d.Visible = 'on';
        end

        function onBulkAddCommit(obj, dlg, ta, dd)
            res = gui2.ElementMappingPage.parseBulkAddText( ...
                strjoin(string(ta.Value(:))', newline));
            if res.mode == "empty"
                uialert(dlg, 'Nothing to add — paste some element IDs.', ...
                    'Empty paste', 'Icon', 'info');
                return
            end
            if res.mode == "ids"
                pairIds   = res.ids;
                pairNames = repmat(string(dd.Value), 1, numel(res.ids));
            else
                pairIds   = res.pairIds;
                pairNames = res.pairNames;
            end
            obj.closeBulkDialog();
            obj.applyPairs(pairIds, pairNames, res.errs, 'Bulk add');
        end

        function applyPairs(obj, ids, names, errs, what)
            %APPLYPAIRS  Add/update rows, reconciling unknown joint names.
            %   Existing ids are REASSIGNED, new ones appended — the same
            %   loop for a paste and for a CSV merge.
            if isempty(ids)
                obj.reportImport(what, 0, 0, errs);
                return
            end
            unknown = unique(names(arrayfun( ...
                @(n) isempty(obj.findJoint(n)), names)));
            if isempty(unknown)
                obj.commitPairs(ids, names, errs, what, "Skip");
                return
            end
            obj.askUnknownJoint(unknown, @(choice) ...
                obj.commitPairs(ids, names, errs, what, choice));
        end

        function commitPairs(obj, ids, names, errs, what, choice)
            if choice == "Cancel"
                return
            end
            if choice == "Create All"
                obj.createStubJoints(unique(names));
            else
                obj.WarnDismissedKey = "";   % re-arm the bar for new names
            end

            rows    = obj.rows();
            known   = obj.elementIds(rows);
            nAdded  = 0;
            nUpdated = 0;
            for k = 1:numel(ids)
                nm  = names(k);
                idx = obj.findJoint(nm);
                if ~isempty(idx)
                    nm = obj.State.JointLibrary(idx).Name;   % canonical case
                end
                hit = find(known == ids(k), 1);   % duplicates: the first wins
                if isempty(hit)
                    rows(end + 1) = gui2.AppState.mappingRow(ids(k), nm); %#ok<AGROW>
                    known(end + 1) = ids(k); %#ok<AGROW>
                    nAdded = nAdded + 1;
                else
                    rows(hit).JointName = nm;
                    nUpdated = nUpdated + 1;
                end
            end
            obj.commit(rows);
            obj.reportImport(what, nAdded, nUpdated, errs);
        end

        function reportImport(obj, what, nAdded, nUpdated, errs)
            %REPORTIMPORT  The one import-report shape (GUI_PORT_SPEC S7.4).
            %   Counts first, then the individual failures with line
            %   numbers, truncated so a pathological file cannot produce a
            %   dialog nobody can read.
            head = sprintf('%s: %d row(s) added, %d updated.', ...
                what, nAdded, nUpdated);
            if isempty(errs)
                obj.setStatus(head);
                return
            end
            shown = errs;
            tail  = "";
            if numel(shown) > obj.MaxReportedErrors
                tail  = sprintf('%s... and %d more.', newline, ...
                    numel(shown) - obj.MaxReportedErrors);
                shown = shown(1:obj.MaxReportedErrors);
            end
            msg = sprintf('%s\n\n%d error(s):\n%s%s', head, numel(errs), ...
                strjoin(shown, newline), tail);
            % An import that produced NOTHING is the dangerous case: it
            % must not read as a clean run just because it did not throw.
            icon = 'warning';
            if nAdded + nUpdated == 0
                icon = 'error';
            end
            uialert(obj.figureHandle(), msg, [what ' — problems'], ...
                'Icon', icon);
        end
    end

    % ---- CSV import / export ----------------------------------------------
    methods (Access = private)
        function onImportCsv(obj)
            [f, p] = uigetfile({'*.csv;*.txt', 'CSV files'}, 'Import Mapping');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));
            try
                [ids, names, pats, errs] = ...
                    gui2.ElementMappingPage.parseMappingCsv(file);
            catch err
                uialert(obj.figureHandle(), err.message, 'Import failed');
                return
            end
            if isempty(ids) && isempty(errs)
                uialert(obj.figureHandle(), sprintf( ...
                    ['%s parsed cleanly but contains no mapping rows. ' ...
                     'Expected columns: element_id, joint_name, and ' ...
                     'optionally pattern_id.'], f), ...
                    'Nothing imported', 'Icon', 'error');
                return
            end
            if isempty(obj.State.Mapping)
                obj.applyCsv(ids, names, pats, errs, "Merge");
                return
            end
            uiconfirm(obj.figureHandle(), sprintf( ...
                ['This case already has %d mapping row(s).\n\nMerge adds ' ...
                 'and updates rows from the file. Replace discards the ' ...
                 'current mapping first.'], numel(obj.State.Mapping)), ...
                'Import Mapping', ...
                'Options',       {'Merge', 'Replace', 'Cancel'}, ...
                'DefaultOption', 'Merge', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.applyCsv(ids, names, pats, errs, ...
                    string(evt.SelectedOption)));
        end

        function applyCsv(obj, ids, names, pats, errs, mode)
            if mode == "Cancel"
                return
            end
            if mode == "Replace"
                obj.State.Mapping = gui2.AppState.emptyMapping();
            end
            unknown = unique(names(arrayfun( ...
                @(n) isempty(obj.findJoint(n)), names)));
            if isempty(unknown)
                obj.commitCsv(ids, names, pats, errs, "Skip");
                return
            end
            obj.askUnknownJoint(unknown, @(choice) ...
                obj.commitCsv(ids, names, pats, errs, choice));
        end

        function commitCsv(obj, ids, names, pats, errs, choice)
            if choice == "Cancel"
                return
            end
            if choice == "Create All"
                obj.createStubJoints(unique(names));
            else
                obj.WarnDismissedKey = "";
            end

            rows     = obj.rows();
            known    = obj.elementIds(rows);
            nAdded   = 0;
            nUpdated = 0;
            for k = 1:numel(ids)
                nm  = names(k);
                idx = obj.findJoint(nm);
                if ~isempty(idx)
                    nm = obj.State.JointLibrary(idx).Name;
                end
                hit = find(known == ids(k), 1);
                if isempty(hit)
                    rows(end + 1) = ...
                        gui2.AppState.mappingRow(ids(k), nm, pats(k)); %#ok<AGROW>
                    known(end + 1) = ids(k); %#ok<AGROW>
                    nAdded = nAdded + 1;
                else
                    rows(hit).JointName = nm;
                    rows(hit).PatternId = pats(k);
                    nUpdated = nUpdated + 1;
                end
            end
            obj.commit(rows);
            obj.reportImport('Import CSV', nAdded, nUpdated, errs);
        end

        function onExportCsv(obj)
            [f, p] = uiputfile({'*.csv', 'CSV file'}, 'Export Mapping', ...
                'element-mapping.csv');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));
            if ~endsWith(file, ".csv", "IgnoreCase", true)
                file = file + ".csv";
            end
            try
                obj.writeCsv(file);
            catch err
                uialert(obj.figureHandle(), err.message, 'Export failed');
                return
            end
            obj.setStatus(sprintf('Wrote %s', file));
        end

        function writeCsv(obj, file)
            rows = obj.rows();
            lines = "element_id,joint_name,pattern_id";
            if isempty(rows)
                % An EMPTY mapping exports the SHAPE, with the joints this
                % case actually has listed — the cheapest possible answer
                % to "what columns does it want?".
                lines(end + 1) = "# One row per FE element. pattern_id is optional:";
                lines(end + 1) = "# blank means this joint name is one bolt pattern.";
                names = obj.jointChoices();
                if isempty(names)
                    lines(end + 1) = "# No joints are defined in this case yet.";
                else
                    lines(end + 1) = "# Defined joints: " + ...
                        strjoin(string(names), ", ");
                end
            else
                for i = 1:numel(rows)
                    lines(end + 1) = strjoin([ ...
                        gui2.ElementMappingPage.csvField(rows(i).ElementID), ...
                        gui2.ElementMappingPage.csvField(rows(i).JointName), ...
                        gui2.ElementMappingPage.csvField(rows(i).PatternId)], ...
                        ","); %#ok<AGROW>
                end
            end
            fid = fopen(file, 'w');
            if fid < 0
                error('gui2:ElementMappingPage:cannotWrite', ...
                    'Cannot open "%s" for writing.', file);
            end
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, char(strjoin(lines, newline) + newline), 'char');
        end
    end

    % ---- Parsers ----------------------------------------------------------
    methods (Static, Access = private)
        function [ids, names, pats, errs] = parseMappingCsv(file)
            %PARSEMAPPINGCSV  element_id, joint_name[, pattern_id].
            %   Rows are processed INDEPENDENTLY: mapping 200 elements must
            %   survive one bad row, so a failure becomes an entry in errs
            %   (with its line number) and the rest still import.
            %
            %   Header detection is tolerant and optional: a first line
            %   whose first field looks like a header is consumed as one,
            %   and a headerless file is read from line 1.
            if ~isfile(file)
                error('gui2:ElementMappingPage:fileNotFound', ...
                    'File not found: %s', file);
            end
            txt = string(splitlines(fileread(file)));

            ids   = strings(1, 0);
            names = strings(1, 0);
            pats  = strings(1, 0);
            errs  = strings(1, 0);

            headerSeen = false;
            for n = 1:numel(txt)
                line = strtrim(txt(n));
                if strlength(line) == 0 || startsWith(line, "#")
                    continue
                end
                fields = gui2.ElementMappingPage.splitCsvLine(line);
                if ~headerSeen && gui2.ElementMappingPage.looksLikeHeader(fields)
                    headerSeen = true;
                    continue
                end
                headerSeen = true;   % only line 1 can be the header

                if numel(fields) < 2
                    errs(end + 1) = sprintf( ...
                        'line %d: needs element_id and joint_name', n); %#ok<AGROW>
                    continue
                end
                id = strtrim(fields(1));
                nm = strtrim(fields(2));
                pt = "";
                if numel(fields) >= 3
                    pt = strtrim(fields(3));
                end
                if strlength(id) == 0
                    errs(end + 1) = sprintf('line %d: blank element_id', n); %#ok<AGROW>
                    continue
                end
                if ~isempty(regexp(char(id), '[\s,]', 'once'))
                    errs(end + 1) = sprintf( ...
                        'line %d: element_id ''%s'' contains a space or comma', ...
                        n, id); %#ok<AGROW>
                    continue
                end
                if strlength(nm) == 0
                    errs(end + 1) = sprintf( ...
                        'line %d: blank joint_name (element %s)', n, id); %#ok<AGROW>
                    continue
                end
                ids(end + 1)   = id; %#ok<AGROW>
                names(end + 1) = nm; %#ok<AGROW>
                pats(end + 1)  = pt; %#ok<AGROW>
            end
        end

        function tf = looksLikeHeader(fields)
            %LOOKSLIKEHEADER  Is this first line column names, or data?
            % Lower FIRST, then strip: stripping [^a-z_] from mixed case
            % would eat every capital and turn "Element_ID" into "lement_".
            key = regexprep(lower(char(strtrim(fields(1)))), '[^a-z_]', '');
            tf  = ismember(string(key), ...
                ["elementid", "element_id", "element", "id", "eid"]);
        end

        function f = splitCsvLine(line)
            %SPLITCSVLINE  Comma split that respects "quoted, fields".
            %   Joint names can legitimately contain commas, so a plain
            %   strsplit would shift every later column on those rows.
            c = char(line);
            f = strings(1, 0);
            cur = '';
            inQ = false;
            k = 1;
            while k <= numel(c)
                ch = c(k);
                if inQ
                    if ch == '"'
                        if k < numel(c) && c(k + 1) == '"'
                            cur(end + 1) = '"'; %#ok<AGROW>
                            k = k + 1;
                        else
                            inQ = false;
                        end
                    else
                        cur(end + 1) = ch; %#ok<AGROW>
                    end
                elseif ch == '"'
                    inQ = true;
                elseif ch == ','
                    f(end + 1) = string(cur); %#ok<AGROW>
                    cur = '';
                else
                    cur(end + 1) = ch; %#ok<AGROW>
                end
                k = k + 1;
            end
            f(end + 1) = string(cur);
        end

        function s = csvField(value)
            %CSVFIELD  Quote a field that would otherwise break the split.
            s = string(value);
            if contains(s, ",") || contains(s, '"') || contains(s, newline)
                s = """" + replace(s, """", """""") + """";
            end
        end

        function [ids, errs] = parseIdTokens(txt)
            %PARSEIDTOKENS  Pasted text -> element ids + per-token errors.
            %   Splits on commas / spaces / tabs / newlines. Invalid tokens
            %   are reported INDIVIDUALLY while the valid ones still parse:
            %   one typo must not discard a 200-element paste. Duplicates
            %   collapse to the first occurrence, order preserved.
            ids  = strings(1, 0);
            errs = strings(1, 0);
            toks = regexp(char(txt), '[,\s]+', 'split');
            for k = 1:numel(toks)
                t = strtrim(string(toks{k}));
                if strlength(t) == 0
                    continue
                end
                if strlength(t) > 64
                    errs(end + 1) = sprintf( ...
                        '''%s...'' is too long for an element ID', ...
                        extractBefore(t, 20)); %#ok<AGROW>
                    continue
                end
                ids(end + 1) = t; %#ok<AGROW>
            end
            ids = unique(ids, 'stable');
        end

        function res = parseBulkAddText(txt)
            %PARSEBULKADDTEXT  Paste -> detected shape + rows.
            %   res.mode: "empty" | "ids" (one column of element IDs) |
            %   "pairs" (two columns, ID + joint name).
            %
            %   DETECTION RULE, deterministic, and the dialog's live line
            %   restates the outcome so it can never silently guess:
            %     - A line is a PAIR line when it splits at the FIRST
            %       column separator (tab, comma, or 2+ spaces — tab is
            %       what Excel pastes) into a first field plus a nonblank
            %       remainder that is not itself just more NUMBERS. So
            %       "101, 102, 103" stays an ID line and "101, JT-A" is a
            %       pair.
            %     - ANY pair line switches the whole paste to "pairs";
            %       ragged lines without a joint name then become
            %       individual line errors rather than silently half-working.
            %
            %   THE CORNER, stated because element IDs are strings here and
            %   the old numeric build did not have it: a comma-separated
            %   line of NON-NUMERIC ids ("E-1, E-2") is indistinguishable
            %   from an ID + joint-name pair and reads as a pair. Put
            %   non-numeric ids one per line, or import a CSV.
            res = struct('mode', "empty", 'ids', strings(1, 0), ...
                'pairIds', strings(1, 0), 'pairNames', strings(1, 0), ...
                'errs', strings(1, 0));
            lines = splitlines(string(txt));

            sep = '^(.*?)(?:\t|,| {2,})\s*(.*\S)\s*$';
            isPair   = false(1, numel(lines));
            firstTok = strings(1, numel(lines));
            restTok  = strings(1, numel(lines));
            anyContent = false;
            for i = 1:numel(lines)
                t = strtrim(lines(i));
                if strlength(t) == 0
                    continue
                end
                anyContent = true;
                tok = regexp(char(t), sep, 'tokens', 'once');
                if isempty(tok)
                    continue
                end
                rest = string(strtrim(tok{2}));
                if ~gui2.ElementMappingPage.allNumeric(rest)
                    isPair(i)   = true;
                    firstTok(i) = string(strtrim(tok{1}));
                    restTok(i)  = rest;
                end
            end
            if ~anyContent
                return
            end

            if ~any(isPair)
                res.mode = "ids";
                [res.ids, res.errs] = ...
                    gui2.ElementMappingPage.parseIdTokens(txt);
                return
            end

            res.mode = "pairs";
            for i = 1:numel(lines)
                t = strtrim(lines(i));
                if strlength(t) == 0
                    continue
                end
                if ~isPair(i)
                    res.errs(end + 1) = sprintf( ...
                        'line %d: "%s" has no joint name', i, t); %#ok<AGROW>
                    continue
                end
                id = strtrim(firstTok(i));
                if strlength(id) == 0
                    res.errs(end + 1) = sprintf( ...
                        'line %d: blank element ID', i); %#ok<AGROW>
                    continue
                end
                if ~isempty(regexp(char(id), '[\s,]', 'once'))
                    res.errs(end + 1) = sprintf( ...
                        'line %d: element ID "%s" contains a space or comma', ...
                        i, id); %#ok<AGROW>
                    continue
                end
                res.pairIds(end + 1)   = id; %#ok<AGROW>
                res.pairNames(end + 1) = restTok(i); %#ok<AGROW>
            end
            % Within one paste the LAST assignment of an id wins, matching
            % how a later line overrides an earlier one when reading down.
            [~, keep] = unique(flip(res.pairIds), 'stable');
            keep = sort(numel(res.pairIds) + 1 - keep);
            res.pairIds   = res.pairIds(keep);
            res.pairNames = res.pairNames(keep);
        end

        function tf = allNumeric(s)
            %ALLNUMERIC  Is every comma/space-separated token a number?
            parts = regexp(char(s), '[,\s]+', 'split');
            tf = true;
            for k = 1:numel(parts)
                if isempty(parts{k})
                    continue
                end
                if isnan(str2double(parts{k}))
                    tf = false;
                    return
                end
            end
        end

        function updateDetectLabel(ta, dd, det)
            %UPDATEDETECTLABEL  Say what Add will do, before it runs.
            res = gui2.ElementMappingPage.parseBulkAddText( ...
                strjoin(string(ta.Value(:))', newline));
            switch res.mode
                case "empty"
                    det.Text = 'Nothing pasted yet.';
                    det.FontColor = gui2.palette('mutedText');
                    dd.Enable = 'on';
                case "ids"
                    det.Text = sprintf(['Detected %d element ID(s) — all ' ...
                        'assigned to the joint above.'], numel(res.ids));
                    det.FontColor = gui2.palette('defaultText');
                    dd.Enable = 'on';
                otherwise
                    det.Text = sprintf(['Detected %d ID + joint-name ' ...
                        'pair(s) — the paste supplies the names, so the ' ...
                        'dropdown is ignored.'], numel(res.pairIds));
                    det.FontColor = gui2.palette('defaultText');
                    dd.Enable = 'off';
            end
            if ~isempty(res.errs)
                det.Text = sprintf('%s  %d line(s) will be reported as errors.', ...
                    det.Text, numel(res.errs));
                det.FontColor = gui2.palette('statusWarn');
            end
        end

        function k = cellIndex(mask, col)
            %CELLINDEX  Nx2 [row col] matrix for a batched addStyle.
            r = reshape(find(mask), [], 1);
            k = [r, col * ones(numel(r), 1)];
        end

        function tf = isTicked(v)
            tf = isequal(v, true) || ...
                (isnumeric(v) && isscalar(v) && v ~= 0);
        end

        function s = idListSuffix(ids, withColon)
            %IDLISTSUFFIX  "a, b, c" up to 5, then a count.
            %   Listing every id in a 200-element problem is not a message,
            %   it is a wall; five plus a count is.
            arguments
                ids       (1, :) string
                withColon (1, 1) logical = true
            end
            if isempty(ids)
                s = "";
                return
            end
            if numel(ids) <= 5
                s = strjoin(ids, ", ");
            else
                s = strjoin(ids(1:5), ", ") + ...
                    sprintf(", ... (%d total)", numel(ids));
            end
            if withColon
                s = ": " + s;
            end
        end
    end

    % ---- Test seams -------------------------------------------------------
    %   Widget handles and the two pure parsers. The parsers are static and
    %   reachable directly because their rules (paste shape detection, CSV
    %   quoting) are the part most likely to be wrong and the part least
    %   convenient to reach through gestures.
    methods
        function t = mapTable(obj)
            %MAPTABLE  Not named table(): a method called `table` shadows
            %   MATLAB's own table() everywhere inside this class.
            t = obj.Table;
        end

        function l = summaryLabel(obj)
            l = obj.SummaryLabel;
        end

        function b = emptyBanner(obj)
            b = obj.Banner;
        end

        function w = warnBar(obj)
            w = obj.WarnBar;
        end

        function l = warnLabel(obj)
            l = obj.WarnLabel;
        end

        function b = createMissingButton(obj)
            b = obj.WarnCreateButton;
        end

        function b = dismissButton(obj)
            b = obj.WarnDismissButton;
        end

        function b = importCsvButton(obj)
            b = obj.ImportCsvButton;
        end

        function b = exportCsvButton(obj)
            b = obj.ExportCsvButton;
        end

        function b = bulkAddButton(obj)
            %BULKADDBUTTON  The TOOLBAR button that opens the dialog.
            b = obj.BulkAddToolbarButton;
        end

        function b = clearAllButton(obj)
            b = obj.ClearAllButton;
        end

        function d = assignDropDown(obj)
            d = obj.AssignDropDown;
        end

        function f = assignPatternField(obj)
            f = obj.AssignPatternField;
        end

        function b = assignButton(obj)
            b = obj.AssignButton;
        end

        function b = importForcesButton(obj)
            b = obj.ImportForcesButton;
        end

        function editCell(obj, row, col, value)
            %EDITCELL  Drive one cell edit the way the widget would.
            %   matlab.uitest has no cell-edit gesture, so this builds the
            %   event the CellEditCallback receives and runs the REAL
            %   callback — a seam, not a stand-in for the logic.
            obj.onCellEdited(struct( ...
                'Indices',      [row col], ...
                'PreviousData', [], ...
                'NewData',      value, ...
                'EditData',     value, ...
                'Error',        []));
        end

        function selectRows(obj, rowsIdx)
            %SELECTROWS  Set the table selection programmatically.
            %   Assigning Selection fires no callback, which is exactly
            %   what a test driving Assign wants.
            obj.Table.Selection = reshape(rowsIdx, 1, []);
        end

        function d = bulkDialog(obj)
            d = obj.BulkDialog;
        end

        function t = bulkTextArea(obj)
            t = obj.BulkTextArea;
        end

        function d = bulkJointDropDown(obj)
            d = obj.BulkDropDown;
        end

        function l = bulkDetectLabel(obj)
            l = obj.BulkDetectLabel;
        end

        function b = bulkDialogAddButton(obj)
            %BULKDIALOGADDBUTTON  The Add button INSIDE the dialog.
            b = obj.BulkAddButton;
        end

        function res = detectPaste(~, txt)
            res = gui2.ElementMappingPage.parseBulkAddText(txt);
        end

        function f = splitCsv(~, line)
            f = gui2.ElementMappingPage.splitCsvLine(line);
        end

        function writeMappingCsv(obj, file)
            obj.writeCsv(file);
        end

        function [ids, names, pats, errs] = readMappingCsv(~, file)
            [ids, names, pats, errs] = ...
                gui2.ElementMappingPage.parseMappingCsv(file);
        end
    end
end
