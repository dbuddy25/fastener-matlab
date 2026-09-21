classdef BoltSizingPage < gui2.Page
    %BOLTSIZINGPAGE  First-cut bolt size from loads and a material alone.
    %   DELIBERATELY SIMPLE: a gut check on BOLT capability only. What the
    %   bolt threads into is not an input here (engine.boltSizingSweep can
    %   take one; this page never passes it) - that belongs on Joint Config.
    %   A thin page over engine.boltSizingSweep: every bolt in the library,
    %   in library (size) order, screened against one limit-load pair.
    %
    %   A SCREEN, NOT A MARGIN SET. The sweep checks Tension-Ultimate,
    %   Tension-Yield and Shear-Ultimate and uses the tension-shear
    %   interaction as a pass/fail gate. There is no preload, so there is no
    %   separation, slip, bearing or thread check, and the interaction gate
    %   has no bending term (TOOL_DIFFERENCES.md Section 2.4). The banner
    %   says so, and "Use this size" hands the choice to Joint Config, where
    %   the real NASA-STD-5020B analysis runs.
    %
    %   SCRATCH STATE. Inputs and the table live on the page: they are not
    %   part of the case and are not saved, so editing them does not mark
    %   the case dirty (plain callbacks, not bindEdit). Only "Use this size"
    %   edits the case.

    properties (Constant, Access = private)
        BlankChoice = '- select -'
    end

    properties (Access = private)
        MaterialDropDown
        TensionField
        ShearField
        ShearPlaneDropDown
        FactorsLabel
        SizeButton
        RequiredLabel
        SummaryLabel
        ResultTable
        UseButton
        Keys        (1,:) string = strings(1, 0)   % library bolt key per table row
        Sweep       = []                           % the engine's table, as returned
        SweepMaterial (1,1) string = ""            % bolt material the table was run with
        SelectedRow (1,1) double = 0
    end

    methods
        function obj = BoltSizingPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "BoltSizing";
        end

        function t = title(~)
            t = "Bolt Sizing";
        end

        function build(obj, parent)
            g = uigridlayout(parent, [2 2]);
            g.RowHeight   = {'fit', '1x'};
            g.ColumnWidth = {340, '1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;

            obj.addBanner(g, 1, [1 2], ...
                ['GUT CHECK ON BOLT CAPABILITY ONLY — not a NASA-STD-5020B ' ...
                 'margin set. It checks the bolt''s own tension (ultimate ' ...
                 'and yield) and shear, with tension-shear interaction as a ' ...
                 'pass/fail gate. The nut, insert or tapped hole is NOT ' ...
                 'considered, and there ' ...
                 'is no preload here, so NO separation, slip, bearing or ' ...
                 'thread checks, and the interaction gate has no bending ' ...
                 'term, which is optimistic for clearance-fit or gapped ' ...
                 'shear joints. Confirm the size you pick on Joint Config.']);

            obj.buildInputs(g);
            obj.buildResults(g);

            obj.listenTo('FactorsChanged', @() obj.onInputsInvalidated());
            obj.listenTo('LibraryChanged', @() obj.onLibraryChanged());
        end

        function refresh(obj)
            %REFRESH  Cheap and idempotent; never marks the case dirty.
            if ~obj.IsBuilt
                return
            end
            obj.updateFactorsLabel();
            obj.validateRequired();
        end
    end

    % ---- Building ---------------------------------------------------------
    methods (Access = private)
        function buildInputs(obj, g)
            panel = uipanel(g, 'FontWeight', 'bold', 'FontSize', 13, ...
                'Title', 'Loads and material');
            panel.Layout.Row = 2;  panel.Layout.Column = 1;
            b = uigridlayout(panel, [8 2]);
            b.ColumnWidth = {130, '1x'};
            b.RowHeight   = [repmat({'fit'}, 1, 7), {'1x'}];
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            obj.MaterialDropDown = obj.addDropdown(b, 1, 'Bolt material', ...
                obj.materialItems("bolt"), ...
                'One bolt material for the whole sweep. Required.');

            obj.TensionField = obj.addNumeric(b, 2, 'Limit tension (lbf)', ...
                'Axial limit load on the most-loaded bolt, PtL.');
            obj.ShearField = obj.addNumeric(b, 3, 'Limit shear (lbf)', ...
                'Shear limit load on the most-loaded bolt, per shear plane, PsL.');

            obj.ShearPlaneDropDown = obj.addDropdown(b, 4, 'Shear plane', ...
                {'Threads in shear', 'Body in shear'}, ...
                ['Which part of the bolt the shear plane cuts. Sets the ' ...
                 'shear area and the interaction exponents (Eq. 20-23).']);
            obj.ShearPlaneDropDown.ItemsData = [1 2];
            obj.ShearPlaneDropDown.Value     = 1;

            obj.FactorsLabel = uilabel(b, 'Text', '', 'WordWrap', 'on');
            obj.FactorsLabel.Layout.Row = 5;  obj.FactorsLabel.Layout.Column = [1 2];
            obj.FactorsLabel.FontColor = gui2.palette('mutedText');

            obj.SizeButton = uibutton(b, 'Text', 'Size bolts', ...
                'ButtonPushedFcn', @(~, ~) obj.onSize());
            obj.SizeButton.Layout.Row = 6;  obj.SizeButton.Layout.Column = [1 2];

            obj.RequiredLabel = uilabel(b, 'Text', '', 'WordWrap', 'on');
            obj.RequiredLabel.Layout.Row = 7;  obj.RequiredLabel.Layout.Column = [1 2];
            obj.RequiredLabel.FontColor = gui2.palette('statusWarn');
        end

        function buildResults(obj, g)
            panel = uipanel(g, 'FontWeight', 'bold', 'FontSize', 13, ...
                'Title', 'Candidate sizes (library order, smallest first)');
            panel.Layout.Row = 2;  panel.Layout.Column = 2;
            r = uigridlayout(panel, [3 2]);
            r.RowHeight   = {'fit', '1x', 'fit'};
            r.ColumnWidth = {'1x', 'fit'};
            r.Padding     = [6 6 6 6];

            obj.SummaryLabel = uilabel(r, 'WordWrap', 'on', 'FontWeight', 'bold', ...
                'Text', 'Enter loads and a material, then press Size bolts.');
            obj.SummaryLabel.Layout.Row = 1;  obj.SummaryLabel.Layout.Column = [1 2];

            obj.ResultTable = uitable(r, 'ColumnEditable', false, ...
                'ColumnName', {'Size', 'Spec', 'At (in^2)', 'MS tension ult', ...
                               'MS tension yield', 'MS shear', 'Status', 'Notes'}, ...
                'CellSelectionCallback', @(~, evt) obj.onRowSelected(evt));
            obj.ResultTable.Layout.Row = 2;  obj.ResultTable.Layout.Column = [1 2];

            obj.UseButton = uibutton(r, 'Text', 'Use this size ->', ...
                'Enable', 'off', ...
                'Tooltip', ['Put the selected bolt, the bolt material and ' ...
                            'these loads on Joint Config.'], ...
                'ButtonPushedFcn', @(~, ~) obj.onUse());
            obj.UseButton.Layout.Row = 3;  obj.UseButton.Layout.Column = 2;
        end

        function [d, lb] = addDropdown(obj, g, row, labelText, items, tip)
            lb = uilabel(g, 'Text', labelText, 'Tooltip', tip);
            lb.Layout.Row = row;  lb.Layout.Column = 1;
            d = uidropdown(g, 'Items', items, 'Tooltip', tip, ...
                'ValueChangedFcn', @(~, ~) obj.onInputEdited());
            d.Layout.Row = row;  d.Layout.Column = 2;
        end

        function [c, lb] = addNumeric(obj, g, row, labelText, tip)
            lb = uilabel(g, 'Text', labelText, 'Tooltip', tip);
            lb.Layout.Row = row;  lb.Layout.Column = 1;
            c = uieditfield(g, 'numeric', 'Limits', [0 Inf], 'Value', 0, ...
                'Tooltip', tip, 'ValueChangedFcn', @(~, ~) obj.onInputEdited());
            c.Layout.Row = row;  c.Layout.Column = 2;
        end

        function items = materialItems(obj, role)
            %MATERIALITEMS  Blank sentinel first, so a required picker never
            %   lands on whatever sorts first in the catalogue.
            items = {gui2.BoltSizingPage.BlankChoice};
            if obj.State.LibraryOK
                items = [items, reshape(cellstr( ...
                    obj.State.Library.materialKeys(Role = role)), 1, [])];
            end
        end
    end

    % ---- Behaviour --------------------------------------------------------
    methods (Access = private)
        function onInputEdited(obj)
            obj.onInputsInvalidated();
        end

        function onInputsInvalidated(obj)
            %ONINPUTSINVALIDATED  A table that no longer matches its inputs
            %   is cleared, never left on screen looking current.
            if ~obj.IsBuilt
                return
            end
            obj.clearResults('Inputs changed — press Size bolts to re-run.');
            obj.updateFactorsLabel();
            obj.validateRequired();
        end

        function onLibraryChanged(obj)
            if ~obj.IsBuilt
                return
            end
            obj.repopulate(obj.MaterialDropDown,       obj.materialItems("bolt"));
            obj.onInputsInvalidated();
        end

        function repopulate(~, dd, items)
            keep = dd.Value;
            dd.Items = items;
            if any(strcmp(items, keep))
                dd.Value = keep;
            else
                dd.Value = items{1};
            end
        end

        function updateFactorsLabel(obj)
            f = obj.State.Factors;
            obj.FactorsLabel.Text = sprintf( ...
                ['Factors in force: FSU %.3g, FSY %.3g, FFU %.3g, FFY %.3g ' ...
                 '(edit on the Factors page).'], f.FSU, f.FSY, f.FFU, f.FFY);
        end

        function k = chosen(~, dd)
            %CHOSEN  The dropdown's key, "" while it sits on the blank sentinel.
            k = string(dd.Value);
            if k == gui2.BoltSizingPage.BlankChoice
                k = "";
            end
        end

        function missing = missingRequired(obj)
            missing = string.empty(1, 0);
            if ~obj.State.LibraryOK
                missing = "The hardware library (it failed to load)";
                return
            end
            if strlength(obj.chosen(obj.MaterialDropDown)) == 0
                missing(end + 1) = "Bolt material";
            end
            if ~(obj.TensionField.Value > 0 || obj.ShearField.Value > 0)
                missing(end + 1) = "A limit load";
            end
        end

        function validateRequired(obj)
            missing = obj.missingRequired();
            if isempty(missing)
                obj.SizeButton.Enable  = 'on';
                obj.RequiredLabel.Text = '';
            else
                obj.SizeButton.Enable  = 'off';
                obj.RequiredLabel.Text = char("Still needed: " + strjoin(missing, "; "));
            end
        end

        function onSize(obj)
            lib = obj.State.Library;
            keys = lib.boltKeys();
            bolts = model.Bolt.empty(1, 0);
            for k = keys
                bolts(end + 1) = lib.bolt(k); %#ok<AGROW>
            end
            matKey = obj.chosen(obj.MaterialDropDown);
            planes = [model.ShearPlaneCondition.ThreadsInShear, ...
                      model.ShearPlaneCondition.BodyInShear];

            try
                T = engine.boltSizingSweep(bolts, lib.material(matKey), ...
                    obj.TensionField.Value, obj.ShearField.Value, ...
                    obj.State.Factors, planes(obj.ShearPlaneDropDown.Value));
            catch err
                obj.clearResults('The sizing run failed.');
                uialert(ancestor(obj.ResultTable, 'figure'), err.message, ...
                    'Sizing failed');
                return
            end
            obj.showResults(T, keys, matKey);
        end

        function showResults(obj, T, keys, matKey)
            obj.Sweep = T;
            obj.Keys  = keys;
            obj.SweepMaterial = matKey;
            obj.SelectedRow = 0;
            obj.UseButton.Enable = 'off';

            n = height(T);
            rows = cell(n, 8);
            for i = 1:n
                rows(i, :) = {char(T.ThreadSize(i)), char(T.Spec(i)), T.At(i), ...
                    gui2.BoltSizingPage.fmtMargin(T.MS_TensionUlt(i)), ...
                    gui2.BoltSizingPage.fmtMargin(T.MS_TensionYield(i)), ...
                    gui2.BoltSizingPage.fmtMargin(T.MS_Shear(i)), ...
                    char(T.Status(i)), char(T.Notes(i))};
            end
            obj.ResultTable.Data = rows;

            removeStyle(obj.ResultTable);
            pass = find(string(T.Status) == "Pass");
            fail = find(string(T.Status) ~= "Pass");
            if ~isempty(pass)
                addStyle(obj.ResultTable, uistyle('BackgroundColor', ...
                    gui2.palette('tablePassBg')), 'row', pass);
            end
            if ~isempty(fail)
                addStyle(obj.ResultTable, uistyle('BackgroundColor', ...
                    gui2.palette('tableFailBg')), 'row', fail);
            end

            if isempty(pass)
                obj.SummaryLabel.Text = sprintf( ...
                    'No size in the library passes (%d screened).', n);
            else
                obj.SummaryLabel.Text = sprintf( ...
                    'Smallest passing size: %s  (%d of %d pass). Select a row to use it.', ...
                    char(keys(pass(1))), numel(pass), n);
            end
        end

        function clearResults(obj, message)
            obj.Sweep = [];
            obj.Keys  = strings(1, 0);
            obj.SelectedRow = 0;
            obj.ResultTable.Data = {};
            removeStyle(obj.ResultTable);
            obj.UseButton.Enable  = 'off';
            obj.SummaryLabel.Text = message;
        end

        function onRowSelected(obj, evt)
            if isempty(evt.Indices)
                return
            end
            obj.setSelectedRow(evt.Indices(1, 1));
        end

        function setSelectedRow(obj, row)
            if row < 1 || row > numel(obj.Keys)
                return
            end
            obj.SelectedRow = row;
            obj.UseButton.Enable = 'on';
        end

        function onUse(obj)
            %ONUSE  Hand the choice to Joint Config. A FAILING row is allowed:
            %   this screen is optimistic in places and pessimistic in none
            %   it knows of, but the analyst may have reasons, and Joint
            %   Config is where the real answer comes from either way.
            if obj.SelectedRow < 1
                return
            end
            lib = obj.State.Library;
            j = obj.State.Joint;
            len = j.Bolt.Length;
            j.Bolt = lib.bolt(obj.Keys(obj.SelectedRow));
            j.Bolt.Length = len;                 % length is joint-specific, not catalogue data
            j.BoltMaterial = lib.material(obj.SweepMaterial);
            lc = obj.State.LoadCase;
            lc.BoltTensileLimitLoad = obj.TensionField.Value;
            lc.BoltShearLimitLoad   = obj.ShearField.Value;

            obj.State.markDirty();
            obj.State.Joint    = j;
            obj.State.LoadCase = lc;
            obj.goToPage("JointConfig");
        end

    end

    methods (Static, Access = private)
        function s = fmtMargin(v)
            if isnan(v)
                s = '-';
            elseif isinf(v)
                s = '+Inf';
            else
                s = sprintf('%+.2f', v);
            end
        end
    end

    % ---- Test seams -------------------------------------------------------
    methods
        function d = materialDropDown(obj),       d = obj.MaterialDropDown;       end
        function f = tensionField(obj),           f = obj.TensionField;           end
        function f = shearField(obj),             f = obj.ShearField;             end
        function b = sizeButton(obj),             b = obj.SizeButton;             end
        function b = useButton(obj),              b = obj.UseButton;              end
        function l = requiredLabel(obj),          l = obj.RequiredLabel;          end
        function l = summaryLabel(obj),           l = obj.SummaryLabel;           end
        function t = resultTable(obj),            t = obj.ResultTable;            end
        function T = sweepTable(obj),             T = obj.Sweep;                  end
        function selectRow(obj, row),             obj.setSelectedRow(row);        end
    end
end
