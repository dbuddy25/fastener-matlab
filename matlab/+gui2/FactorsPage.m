classdef FactorsPage < gui2.Page
    %FACTORSPAGE  Safety + fitting factors, and the factor-preset mechanism
    %   (GUI2_SPEC.md Section 3, "Factors").
    %
    %   Four safety-of-factor fields map 1:1 onto model.Factors (FSU / FSY /
    %   FSSep / FSSlip). NASA-STD-5020B 4.2.2 [TFSR 3] defines ONE fitting
    %   factor that multiplies every factor of safety, so the GUI exposes a
    %   single FF field while model.Factors keeps its four FF slots
    %   (FFU/FFY/FFSep/FFSlip) as the engine mechanism — single-FF mode
    %   writes that one field into all four on commit.
    %
    %   MIXED-FF PRESERVATION. A loaded case (or applied preset) can carry
    %   UNEQUAL per-check fitting factors — the DABJ fixture is FFU=1.15,
    %   the rest 1.0. Collapsing that onto one field and writing it back
    %   would silently change the loaded margins. So an unequal set is kept
    %   verbatim in LoadedFittingFactors (page-local, not case state — it is
    %   a view of what AppState.Factors already holds) until the analyst
    %   edits the FF field, at which point that one value governs all four
    %   and the mixed set is dropped. This mirrors +gui's
    %   applyFactors/buildFactors exactly (GUI2_HARVEST.md source: that
    %   file's rationale comments).
    %
    %   PRESETS. data.factorPreset / data.factorPresets / data.saveFactorPreset
    %   are the ONLY preset storage — this page never reads or writes the
    %   preset files itself. See the note above buildPresetGroup for the one
    %   place that API falls short of what a picker dropdown wants.
    %
    %   Backed by AppState.Factors (model.Factors), fires FactorsChanged.

    properties (Access = private)
        SafetyFields   % struct: FSU/FSY/FSSep/FSSlip -> numeric edit field
        FFField
        MixedLabel
        LoadedFittingFactors = double.empty(1, 0)

        PresetDropdown
        PresetNameField
        SaveButton
        LoadButton
    end

    properties (Constant, Access = private)
        PresetPlaceholder = "Apply a built-in preset…"
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

            obj.buildFactorsGroup(g, 1);
            obj.buildPresetGroup(g, 2);

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
        function buildFactorsGroup(obj, parent, row)
            panel = uipanel(parent, 'Title', 'Analysis Factors');
            panel.Layout.Row = row;
            g = uigridlayout(panel, [8 2]);
            g.ColumnWidth = {'fit', '1x'};
            g.RowHeight   = repmat({'fit'}, 1, 8);
            g.RowSpacing  = 4;
            g.Padding     = [6 6 6 6];

            h = uilabel(g, 'Text', 'Safety factors', 'FontWeight', 'bold');
            h.Layout.Row = 1;
            h.Layout.Column = [1 2];

            safetyNames  = ["FSU", "FSY", "FSSep", "FSSlip"];
            safetyLabels = ["FSU — ultimate FS", "FSY — yield FS", ...
                            "FSSep — separation FS", "FSSlip — slip FS"];
            safetyTips   = ["Ultimate factor of safety (model.Factors.FSU).", ...
                            "Yield factor of safety (model.Factors.FSY).", ...
                            "Separation factor of safety (model.Factors.FSSep).", ...
                            "Slip factor of safety (model.Factors.FSSlip)."];
            obj.SafetyFields = struct();
            for i = 1:numel(safetyNames)
                f = obj.addNumeric(g, 1 + i, char(safetyLabels(i)), safetyTips(i));
                obj.SafetyFields.(safetyNames(i)) = f;
                obj.bindEdit(f, @(~, ~) obj.commitFromControls());
            end

            h = uilabel(g, 'Text', 'Fitting factor', 'FontWeight', 'bold');
            h.Layout.Row = 6;
            h.Layout.Column = [1 2];

            % NASA-STD-5020B 4.2.2 [TFSR 3] — one fitting factor multiplies
            % every factor of safety (FF is a program-level policy knob, not
            % an equation with a number to evaluate; the citation still
            % names the governing section per CLAUDE.md's traceability rule).
            ffTip = ['Fitting factor (FF), NASA-STD-5020B 4.2.2 [TFSR 3]: ' ...
                'one factor multiplies every factor of safety — ultimate, ' ...
                'yield, separation, slip. A minimum of 1.15 is recommended ' ...
                'for ultimate. Commits into all four model.Factors FF slots ' ...
                'unless a loaded case or preset carried unequal values — see ' ...
                'the banner below.'];
            obj.FFField = obj.addNumeric(g, 7, 'FF — fitting factor', ffTip);
            obj.bindEdit(obj.FFField, @(~, ~) obj.onFittingFactorEdited());

            obj.MixedLabel = uilabel(g, 'Text', '', 'WordWrap', 'on');
            obj.MixedLabel.Layout.Row    = 8;
            obj.MixedLabel.Layout.Column = [1 2];
            obj.MixedLabel.VerticalAlignment = 'top';
            obj.MixedLabel.BackgroundColor   = gui2.palette('bannerWarnBg');
            obj.MixedLabel.FontColor         = gui2.palette('bannerWarnFg');
            obj.MixedLabel.Visible = 'off';
        end

        % Preset mechanism.
        %
        % data.factorPresets() is a public, reliable enumerator for the
        % BUILT-IN presets (a containers.Map), so those populate the
        % dropdown directly. There is deliberately NO equivalent public
        % enumerator for USER-saved presets — +data exposes only
        % factorPreset (lookup by exact name), factorPresets (built-in
        % map), and saveFactorPreset (write); the on-disk reader
        % (loadUserFactorPresets) and the path resolver are BOTH under
        % +data/private, unreachable from +gui2. Rather than parse
        % data.factorPreset's error-message text to fish out its
        % "Available: ..." list — a real option, but fragile: a wording
        % change in that error string would silently break the dropdown at
        % runtime with no test to catch it — this page exposes a
        % "load by name" text field for ANY saved preset (built-in or
        % user), and the dropdown as a quick-pick for the built-ins only.
        % See GUI2_SPEC.md open items / the step-2 report for the
        % public-API gap this works around.
        function buildPresetGroup(obj, parent, row)
            panel = uipanel(parent, 'Title', 'Factor Presets');
            panel.Layout.Row = row;
            g = uigridlayout(panel, [3 3]);
            g.ColumnWidth = {'fit', '1x', 'fit'};
            g.RowHeight   = {'fit', 'fit', 'fit'};
            g.RowSpacing  = 4;
            g.Padding     = [6 6 6 6];

            lb = uilabel(g, 'Text', 'Built-in:');
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            names = obj.builtInPresetNames();
            obj.PresetDropdown = uidropdown(g, ...
                'Items', cellstr([gui2.FactorsPage.PresetPlaceholder, names]));
            obj.PresetDropdown.Layout.Row    = 1;
            obj.PresetDropdown.Layout.Column = [2 3];
            obj.bindEdit(obj.PresetDropdown, @(~, ~) obj.onPresetDropdownChanged());

            lb = uilabel(g, 'Text', 'Preset name:');
            lb.Layout.Row    = 2;
            lb.Layout.Column = 1;
            obj.PresetNameField = uieditfield(g, 'text');
            obj.PresetNameField.Layout.Row    = 2;
            obj.PresetNameField.Layout.Column = [2 3];
            obj.PresetNameField.Tooltip = ['Type a preset name, then Save ' ...
                'the current factors under it, or Load a previously saved ' ...
                'one (built-in or your own) by its exact name.'];
            % Not bound through bindEdit — typing a name is not a case
            % edit; only Save/Load below act on AppState.

            obj.SaveButton = uibutton(g, 'push', 'Text', 'Save as preset');
            obj.SaveButton.Layout.Row    = 3;
            obj.SaveButton.Layout.Column = 2;
            obj.SaveButton.ButtonPushedFcn = @(~, ~) obj.onSavePreset();

            obj.LoadButton = uibutton(g, 'push', 'Text', 'Load by name');
            obj.LoadButton.Layout.Row    = 3;
            obj.LoadButton.Layout.Column = 3;
            obj.LoadButton.ButtonPushedFcn = @(~, ~) obj.onLoadByName();
        end

        function c = addNumeric(obj, g, row, labelText, tip)
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            c = uieditfield(g, 'numeric');
            c.Layout.Row    = row;
            c.Layout.Column = 2;
            c.Limits = [0 Inf];
            c.LowerLimitInclusive = 'off';   % model.Factors: mustBePositive
            if strlength(string(tip)) > 0
                c.Tooltip  = tip;
                lb.Tooltip = tip;
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

        function onPresetDropdownChanged(obj)
            name = string(obj.PresetDropdown.Value);
            % Reset to the neutral placeholder immediately (no event fires
            % from a programmatic Value set) — the dropdown is a trigger,
            % not a persistent "this preset is active" indicator, since
            % further hand-edits would make that claim false.
            obj.PresetDropdown.Value = char(gui2.FactorsPage.PresetPlaceholder);
            if name == gui2.FactorsPage.PresetPlaceholder
                return
            end
            obj.applyPresetByName(name);
        end

        function onLoadByName(obj)
            name = strtrim(string(obj.PresetNameField.Value));
            if strlength(name) == 0
                uialert(obj.figureHandle(), ...
                    'Enter a preset name to load.', 'No preset name');
                return
            end
            % A push-button action is not routed through bindEdit, so mark
            % dirty explicitly — applying a preset IS a case edit
            % (GUI2_HARVEST.md A4).
            obj.State.markDirty();
            obj.applyPresetByName(name);
        end

        function applyPresetByName(obj, name)
            try
                fac = data.factorPreset(name);
            catch err
                uialert(obj.figureHandle(), err.message, 'Preset not found');
                return
            end
            obj.setFactorControls(fac);
            obj.commitFromControls();
        end

        function onSavePreset(obj)
            name = strtrim(string(obj.PresetNameField.Value));
            if strlength(name) == 0
                uialert(obj.figureHandle(), ...
                    'Enter a name for the preset before saving.', 'No preset name');
                return
            end
            try
                data.saveFactorPreset(name, obj.factorsFromControls());
            catch err
                uialert(obj.figureHandle(), err.message, 'Save preset failed');
                return
            end
            obj.refreshBuiltInDropdown();
            uialert(obj.figureHandle(), sprintf('Saved preset "%s".', name), ...
                'Preset saved', 'Icon', 'success');
        end

        function refreshBuiltInDropdown(obj)
            % Built-in names never change at runtime, but re-derive anyway
            % rather than assume — cheap, and matches "never a stale cached
            % list" everywhere else dropdowns repopulate.
            obj.PresetDropdown.Items = ...
                cellstr([gui2.FactorsPage.PresetPlaceholder, obj.builtInPresetNames()]);
        end

        function names = builtInPresetNames(~)
            m = data.factorPresets();
            names = sort(string(keys(m)));
        end

        function fig = figureHandle(obj)
            fig = ancestor(obj.Root, 'figure');
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

        function dd = presetDropdown(obj)
            dd = obj.PresetDropdown;
        end

        function f = presetNameField(obj)
            f = obj.PresetNameField;
        end

        function b = saveButton(obj)
            b = obj.SaveButton;
        end

        function b = loadButton(obj)
            b = obj.LoadButton;
        end
    end
end
