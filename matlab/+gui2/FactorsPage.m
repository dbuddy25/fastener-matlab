classdef FactorsPage < gui2.Page
    %FACTORSPAGE  The fitting factor and the four factors of safety
    %   (GUI2_SPEC.md Section 3, "Factors").
    %
    %   Fitting factor first, then Factors of Safety: one FF multiplies
    %   every FS below it, so reading order matches the arithmetic. Each
    %   row is name | symbol | value.
    %
    %   Four factor-of-safety fields map 1:1 onto model.Factors (FSU / FSY /
    %   FSSep / FSSlip). NASA-STD-5020B 4.2.2 [TFSR 3] defines ONE fitting
    %   factor that multiplies every factor of safety, so the GUI exposes a
    %   single FF field while model.Factors keeps its four FF slots
    %   (FFU/FFY/FFSep/FFSlip) as the engine mechanism — single-FF mode
    %   writes that one field into all four on commit.
    %
    %   MIXED-FF PRESERVATION. A loaded case can carry UNEQUAL per-check fitting factors — the DABJ fixture is FFU=1.15,
    %   the rest 1.0. Collapsing that onto one field and writing it back
    %   would silently change the loaded margins. So an unequal set is kept
    %   verbatim in LoadedFittingFactors (page-local, not case state — it is
    %   a view of what AppState.Factors already holds) until the analyst
    %   edits the FF field, at which point that one value governs all four
    %   and the mixed set is dropped. This mirrors +gui's
    %   applyFactors/buildFactors exactly (GUI2_HARVEST.md source: that
    %   file's rationale comments).
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
        FFField
        MixedLabel
        LoadedFittingFactors = double.empty(1, 0)
    end

    properties (Constant, Access = private)
        % Shared by both factor grids so the name / symbol / value columns
        % line up between the panels. A trailing '1x' absorbs the slack:
        % a value box stretched across the page reads as a text field.
        RowColumns = {'fit', 60, 90, '1x'}
    end

    methods
        function obj = FactorsPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "Factors";
        end

        function t = title(~)
            t = "Factors";
        end

        function build(obj, parent)
            g = uigridlayout(parent, [3 1]);
            g.RowHeight   = {'fit', 'fit', '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;
            g.Scrollable  = 'on';

            obj.buildFittingGroup(g, 1);
            obj.buildSafetyGroup(g, 2);

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
            %BUILDFITTINGGROUP  The fitting factor, first on the page.
            %   First because one FF multiplies every factor of safety
            %   below it — reading order matches the arithmetic.
            panel = uipanel(parent, 'Title', 'Fitting Factor');
            panel.Layout.Row = row;
            g = uigridlayout(panel, [2 4]);
            g.ColumnWidth = gui2.FactorsPage.RowColumns;
            g.RowHeight   = {'fit', 'fit'};
            g.RowSpacing  = 4;
            g.Padding     = [6 6 6 6];

            % NASA-STD-5020B 4.2.2 [TFSR 3] — one fitting factor multiplies
            % every factor of safety (FF is a program-level policy knob, not
            % an equation with a number to evaluate; the citation still
            % names the governing section per CLAUDE.md's traceability rule).
            ffTip = ['Fitting factor (FF), NASA-STD-5020B 4.2.2 [TFSR 3]: ' ...
                'one factor multiplies every factor of safety — ultimate, ' ...
                'yield, separation, slip. A minimum of 1.15 is recommended ' ...
                'for ultimate. Commits into all four model.Factors FF slots ' ...
                'unless a loaded case carried unequal values — see the ' ...
                'banner below.'];
            obj.FFField = obj.addFactorRow(g, 1, 'Fitting Factor', 'FF', ffTip);
            obj.bindEdit(obj.FFField, @(~, ~) obj.onFittingFactorEdited());

            obj.MixedLabel = uilabel(g, 'Text', '', 'WordWrap', 'on');
            obj.MixedLabel.Layout.Row    = 2;
            obj.MixedLabel.Layout.Column = [1 4];
            obj.MixedLabel.VerticalAlignment = 'top';
            obj.MixedLabel.BackgroundColor   = gui2.palette('bannerWarnBg');
            obj.MixedLabel.FontColor         = gui2.palette('bannerWarnFg');
            obj.MixedLabel.Visible           = 'off';
        end

        function buildSafetyGroup(obj, parent, row)
            %BUILDSAFETYGROUP  The four factors of safety.
            panel = uipanel(parent, 'Title', 'Factors of Safety');
            panel.Layout.Row = row;
            g = uigridlayout(panel, [4 4]);
            g.ColumnWidth = gui2.FactorsPage.RowColumns;
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
            fsNames = ["FSU", "FSY", "FSSep", "FSSlip"];
            for i = 1:numel(fsNames)
                obj.SafetyFields.(fsNames(i)).Value = fac.(fsNames(i));
            end
            ff = [fac.FFU, fac.FFY, fac.FFSep, fac.FFSlip];
            if all(ff == ff(1))
                obj.FFField.Value = ff(1);
                obj.clearMixedFitting();
            else
                obj.FFField.Value = fac.FFU;
                obj.LoadedFittingFactors = ff;
                obj.MixedLabel.Text = sprintf( ...
                    ['Unequal per-check fitting factors: FFU=%g, FFY=%g, ' ...
                     'FFSep=%g, FFSlip=%g. These stay in effect until the ' ...
                     'FF field above is edited.'], ff(1), ff(2), ff(3), ff(4));
                obj.MixedLabel.Visible = 'on';
            end
        end

        function clearMixedFitting(obj)
            obj.LoadedFittingFactors = double.empty(1, 0);
            obj.MixedLabel.Text    = '';
            obj.MixedLabel.Visible = 'off';
        end

        function fac = factorsFromControls(obj)
            if isempty(obj.LoadedFittingFactors)
                ff = repmat(obj.FFField.Value, 1, 4);
            else
                ff = obj.LoadedFittingFactors;
            end
            fac = model.Factors( ...
                FSU    = obj.SafetyFields.FSU.Value, ...
                FSY    = obj.SafetyFields.FSY.Value, ...
                FSSep  = obj.SafetyFields.FSSep.Value, ...
                FSSlip = obj.SafetyFields.FSSlip.Value, ...
                FFU    = ff(1), FFY = ff(2), FFSep = ff(3), FFSlip = ff(4));
        end

        function commitFromControls(obj)
            %COMMITFROMCONTROLS  Write the current control values into
            %   AppState.Factors. Fires FactorsChanged, which calls
            %   refresh() — harmless (see ProjectPage.commit for why).
            obj.State.Factors = obj.factorsFromControls();
        end

        function onFittingFactorEdited(obj)
            %ONFITTINGFACTOREDITED  Editing FF exits mixed-FF mode: from
            %   here on this one value governs all four engine slots.
            obj.clearMixedFitting();
            obj.commitFromControls();
        end

    end

    % ---- Test seams ---------------------------------------------------
    %   Public handle getters, same pattern as PlaceholderPage's counters:
    %   tGui2SetupPages drives real matlab.uitest gestures (type/press/
    %   choose) against these controls rather than reaching into private
    %   state.
    methods
        function f = fsuField(obj)
            f = obj.SafetyFields.FSU;
        end

        function f = ffField(obj)
            f = obj.FFField;
        end

        function lbl = mixedLabel(obj)
            lbl = obj.MixedLabel;
        end




    end
end
