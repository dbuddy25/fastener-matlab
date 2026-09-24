classdef FactorsPage < gui.Page
    %FACTORSPAGE  The four fitting factors and the four factors of safety
    %   (GUI_SPEC.md Section 3, "Factors").
    %
    %   Fitting Factors first, then Factors of Safety: each FF multiplies
    %   the FS of the same check, so reading order matches the arithmetic.
    %   Each row is name | symbol | value, and all eight fields map 1:1
    %   onto model.Factors.
    %
    %   PER-CHECK FITTING FACTORS. A program may levy the fitting factor on
    %   some checks only — the DABJ answer key applies 1.15 to ultimate and
    %   1.0 elsewhere — so one FF field could not express a real case.
    %
    %   NO PRESET UI YET. data.factorPreset / factorPresets /
    %   factorPresetNames / saveFactorPreset are all in place and tested
    %   (tCaseIO), but the picker is deliberately deferred — this page is
    %   worth more small. When it returns it binds to that API and reads or
    %   writes no preset file itself.
    %
    %   Backed by AppState.Factors (model.Factors), fires FactorsChanged.

    properties (Access = private)
        SafetyFields   % struct: FSU/FSY/FSSep/FSSlip -> numeric edit field
        FittingFields  % struct: FFU/FFY/FFSep/FFSlip -> numeric edit field
    end

    properties (Constant, Access = private)
        % Shared by both factor grids. FIXED widths, not 'fit': 'fit'
        % resolves per grid, so "Fitting Factor" and "Separation" would
        % size their own columns differently and the two panels would not
        % line up. Fixed widths are what makes them one visual table.
        RowColumns = {110, 60, 90}
    end

    methods
        function obj = FactorsPage(state)
            obj@gui.Page(state);
        end

        function id = pageId(~)
            id = "Factors";
        end

        function t = title(~)
            t = "Factors";
        end

        function build(obj, parent)
            % Column 2 is a flexible gutter that absorbs the window width,
            % so the panels in column 1 size to their content instead of
            % stretching across the page around three narrow fields.
            g = uigridlayout(parent, [4 2]);
            g.RowHeight   = {'fit', 'fit', 'fit', '1x'};
            g.ColumnWidth = {'fit', '1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;
            g.Scrollable  = 'on';

            obj.addBanner(g, 1, [1 2], ...
                ['Applies to BOTH analyses — the single-joint Analyze and ' ...
                 'every joint in a bulk run use this one set of factors. ' ...
                 'They are case state, saved and loaded with the case file.']);
            obj.buildFittingGroup(g, 2);
            obj.buildSafetyGroup(g, 3);

            obj.listenTo('FactorsChanged', @() obj.refresh());
        end

        function refresh(obj)
            %REFRESH  AppState.Factors -> controls. Never marks dirty.
            if ~obj.IsBuilt
                return
            end
            obj.setFactorControls(obj.State.Factors);
        end
    end

    % ---- Layout -------------------------------------------------------
    methods (Access = private)
        function buildFittingGroup(obj, parent, row)
            %BUILDFITTINGGROUP  The four fitting factors, first on the page.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Fitting Factors');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;
            g = uigridlayout(panel, [4 3]);
            g.ColumnWidth = gui.FactorsPage.RowColumns;
            g.RowHeight   = repmat({'fit'}, 1, 4);
            g.RowSpacing  = 4;
            g.Padding     = [6 6 6 6];

            % NASA-STD-5020B 4.2.2 [TFSR 3] — FF multiplies the factor of
            % safety (a program-level policy value, not an equation).
            spec = { ...
                "FFY",    'Yield',      'FFy'; ...
                "FFU",    'Ultimate',   'FFu'; ...
                "FFSep",  'Separation', 'FFsep'; ...
                "FFSlip", 'Slip',       'FFslip'};
            tips = [ ...
                "Yield fitting factor, multiplies FSy (NASA-STD-5020B 4.2.2).", ...
                "Ultimate fitting factor, multiplies FSu. A minimum of 1.15 is recommended (NASA-STD-5020B 4.2.2).", ...
                "Separation fitting factor, multiplies FSsep. At least 1.15 on a separation-critical joint (NASA-STD-5020B 4.2.2).", ...
                "Slip fitting factor, multiplies FSslip (NASA-STD-5020B 4.2.2)."];

            obj.FittingFields = struct();
            for i = 1:size(spec, 1)
                f = obj.addFactorRow(g, i, spec{i, 2}, spec{i, 3}, tips(i));
                obj.FittingFields.(spec{i, 1}) = f;
                obj.bindEdit(f, @(~, ~) obj.commitFromControls());
            end
        end

        function buildSafetyGroup(obj, parent, row)
            %BUILDSAFETYGROUP  The four factors of safety.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Factors of Safety');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;
            g = uigridlayout(panel, [4 3]);
            g.ColumnWidth = gui.FactorsPage.RowColumns;
            g.RowHeight   = repmat({'fit'}, 1, 4);
            g.RowSpacing  = 4;
            g.Padding     = [6 6 6 6];

            % Property name, displayed name, displayed symbol.
            spec = { ...
                "FSY",    'Yield',      'FSy'; ...
                "FSU",    'Ultimate',   'FSu'; ...
                "FSSep",  'Separation', 'FSsep'; ...
                "FSSlip", 'Slip',       'FSslip'};
            tips = [ ...
                "Yield factor of safety (model.Factors.FSY).", ...
                "Ultimate factor of safety (model.Factors.FSU).", ...
                "Separation factor of safety (model.Factors.FSSep).", ...
                "Slip factor of safety (model.Factors.FSSlip)."];

            obj.SafetyFields = struct();
            for i = 1:size(spec, 1)
                f = obj.addFactorRow(g, i, spec{i, 2}, spec{i, 3}, tips(i));
                obj.SafetyFields.(spec{i, 1}) = f;
                obj.bindEdit(f, @(~, ~) obj.commitFromControls());
            end
        end

        function c = addFactorRow(obj, g, row, nameText, symbolText, tip)
            %ADDFACTORROW  Name | symbol | value, one row of a factor grid.
            lb = uilabel(g, 'Text', nameText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;

            sym = uilabel(g, 'Text', symbolText, 'FontAngle', 'italic');
            sym.Layout.Row    = row;
            sym.Layout.Column = 2;

            c = obj.addNumeric(g, row, 3, tip);
            if strlength(string(tip)) > 0
                lb.Tooltip  = tip;
                sym.Tooltip = tip;
            end
        end

        function c = addNumeric(~, g, row, col, tip)
            %ADDNUMERIC  One positive-only numeric field.
            c = uieditfield(g, 'numeric');
            c.Layout.Row    = row;
            c.Layout.Column = col;
            c.Limits = [0 Inf];
            c.LowerLimitInclusive = 'off';   % model.Factors: mustBePositive
            if strlength(string(tip)) > 0
                c.Tooltip = tip;
            end
        end
    end

    % ---- Widget <-> AppState -----------------------------------------------
    methods (Access = private)
        function setFactorControls(obj, fac)
            %SETFACTORCONTROLS  model.Factors -> controls (no dirty).
            for n = ["FSU", "FSY", "FSSep", "FSSlip"]
                obj.SafetyFields.(n).Value = fac.(n);
            end
            for n = ["FFU", "FFY", "FFSep", "FFSlip"]
                obj.FittingFields.(n).Value = fac.(n);
            end
        end

        function fac = factorsFromControls(obj)
            fac = model.Factors( ...
                FSU    = obj.SafetyFields.FSU.Value, ...
                FSY    = obj.SafetyFields.FSY.Value, ...
                FSSep  = obj.SafetyFields.FSSep.Value, ...
                FSSlip = obj.SafetyFields.FSSlip.Value, ...
                FFU    = obj.FittingFields.FFU.Value, ...
                FFY    = obj.FittingFields.FFY.Value, ...
                FFSep  = obj.FittingFields.FFSep.Value, ...
                FFSlip = obj.FittingFields.FFSlip.Value);
        end

        function commitFromControls(obj)
            %COMMITFROMCONTROLS  Write the current control values into
            %   AppState.Factors. Fires FactorsChanged, which calls
            %   refresh() — harmless (see ProjectPage.commit for why).
            obj.State.Factors = obj.factorsFromControls();
        end

    end

    % ---- Test seams ---------------------------------------------------
    %   Public handle getters, same pattern as PlaceholderPage's counters:
    %   tGuiSetupPages drives real matlab.uitest gestures (type/press/
    %   choose) against these controls rather than reaching into private
    %   state.
    methods
        function f = fsuField(obj)
            f = obj.SafetyFields.FSU;
        end

        function f = ffField(obj, name)
            %FFFIELD  One fitting-factor field: "FFU" (default), "FFY",
            %   "FFSep" or "FFSlip".
            arguments
                obj
                name (1,1) string = "FFU"
            end
            f = obj.FittingFields.(name);
        end
    end
end
