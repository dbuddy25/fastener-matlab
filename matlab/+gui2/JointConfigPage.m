classdef JointConfigPage < gui2.Page
    %JOINTCONFIGPAGE  Define one joint and its loads (GUI2_SPEC.md Section 7).
    %   The largest page in the app. Two columns: the LEFT is the joint in
    %   PHYSICAL STACK ORDER — bolt, head washer, flange stack, nut washer,
    %   threaded member — so the form reads the way the hardware assembles.
    %   The RIGHT is preload, applied loads, analysis assumptions, and the
    %   two actions.
    %
    %   SYNC IS NOT AN EDIT. applyNutSpec / refreshWasherState /
    %   applyWasherSpec / syncWasherEnables / updateEngagementFieldMode /
    %   mirrorNutWasherFromHead NEVER mark dirty. They run during build and
    %   from refresh(), where a dirty flag would be a lie — a new session
    %   would open with a "* " title and prompt to discard on close. Genuine
    %   edits are marked by Page.bindEdit BEFORE the callback runs, so these
    %   are safe to call from anywhere. Each must also be idempotent and
    %   no-op cleanly before the panel exists.
    %
    %   ONE CASCADE, FOUR TRIGGERS. A bolt change re-resolves the bolt spec,
    %   the nut spec and BOTH washer specs, then refreshes the length
    %   readout: every one of those matches is keyed on the selected bolt's
    %   thread size. The same orchestrators run on a member-type change, a
    %   washer Present toggle, build, and refresh. There is one entry point
    %   per picker and every trigger calls it.
    %
    %   NOTHING HERE COMPUTES. The grip and bolt-length readouts format
    %   structs returned by model.Joint / engine.boltLengthCheck. Analyze
    %   marshals controls and calls engine.analyze. No margin, area or
    %   threshold is derived in this file (GUI2_SPEC.md Section 6).
    %
    %   KEEP IN SYNC WITH THE DEFINED JOINTS SUMMARY (GUI2_SPEC.md Section
    %   7.6). That page is step 5 and does not exist yet. When it does, its
    %   summary mirrors these panels field for field: add, remove or move a
    %   control here and update it in the same change, or the summary goes
    %   stale while still looking current.

    properties (Constant, Access = private)
        % Blank sentinel for REQUIRED dropdowns. A single space, not '': it
        % renders empty but survives round-trips through Items lists that
        % some MATLAB releases normalise. ALWAYS test with isBlank, never
        % strcmp against '' (GUI2_HARVEST.md A6).
        BlankChoice = ' '

        % Placeholder in a washer size dropdown with nothing to resolve.
        WasherSizeNA = '(n/a - Custom)'

        % Shared row geometry. Fixed, not 'fit': 'fit' resolves per grid, so
        % panels using the same spec still misalign (GUI2_HARVEST.md D).
        LabelW = 165
        ValueW = 115

        % Insert's display label, used in enough comparisons to be worth a
        % constant. Derived from the enum, never typed as a bare string in a
        % comparison — GUI2_HARVEST.md C1 is a bug that came from exactly
        % that (a string compare against 'TappedHole' that could never
        % match, so the member silently behaved as bolt-only).
        MaxFlangeLayers = 4
    end

    properties (Access = private)
        % ---- Identity / bolt
        JointNameField
        BoltDropDown
        BoltMaterialDropDown
        SpecLabel
        BoltCountField

        % ---- Washers (two groups, identical shape)
        HeadWasher   % struct of handles, see washerGroup()
        NutWasher
        NutWasherSameAsHeadCheck

        % ---- Flange stack
        FlangeActive
        FlangeName
        FlangeMaterial
        FlangeThickness
        FlangeHole
        FlangeEdge
        FlangeTearout

        % ---- Threaded member
        MemberTypeDropDown
        MemberMaterialLabel
        MemberMaterialDropDown
        NutSpecDropDown
        EngagementField
        EngagementFieldLabel

        % Tracks which UNIT the engagement field currently means, so a
        % crossing can be detected. Not derivable after the fact — the
        % dropdown has already moved by the time the callback runs.
        EngagementIsInsertMode (1,1) logical = false

        % ---- Bolt length & grip
        BoltLengthField
        GripLabel
        BoltLengthLabel

        % ---- Advanced / overrides
        BodyLengthField
        RatedUltField
        RatedYieldField
        RatedOverrideCheck
        FrustumAngleField

        % ---- Preload
        NominalTorqueField
        TorqueTolField
        NutFactorField
        UncertaintyField
        RelaxationField
        SeparationCriticalCheck

        % ---- Applied loads
        CaseNameField
        BoltTensileField
        BoltShearField
        JointTensileField
        JointShearField
        JointLoadRows          % handles hidden unless SlipMode = Joint

        % ---- Analysis assumptions
        ShearPlaneDropDown
        SlipModeDropDown
        FrictionField
        BoltAxisDropDown
        LoadingPlaneField

        % ---- Actions
        AnalyzeButton
        SaveJointButton
        AnalyzeDefaultTooltip (1,1) string = ""

        % Collapsible group bookkeeping: one row per group, so a toggle can
        % find its body row and set that row's height.
        Groups = struct('Button', {}, 'Body', {}, 'Grid', {}, 'Row', {}, 'Title', {})

        % Guards refresh() against re-entry. Assigning AppState.Joint fires
        % JointChanged, which calls refresh(), which would repopulate the
        % controls mid-marshal.
        Refreshing (1,1) logical = false
    end

    methods
        function obj = JointConfigPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "JointConfig";
        end

        function t = title(~)
            t = "Joint Config";
        end

        function build(obj, parent)
            g = uigridlayout(parent, [2 3]);
            g.RowHeight   = {'fit', 'fit'};
            g.ColumnWidth = {'fit', 'fit', '1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;
            g.ColumnSpacing = 10;
            g.Scrollable  = 'on';

            obj.addBanner(g, 1, [1 3], ...
                ['Define one joint and its limit loads, then Analyze (F5). ' ...
                 'The left column follows the physical stack, top to bottom. ' ...
                 'Factors and service temperatures are global — they live on ' ...
                 'their own pages and are shown in the bar at the bottom of ' ...
                 'the window.']);

            left = uigridlayout(g, [1 1]);
            left.Layout.Row    = 2;
            left.Layout.Column = 1;
            left.ColumnWidth   = {'fit'};
            left.Padding       = [0 0 0 0];
            left.RowSpacing    = 4;

            right = uigridlayout(g, [1 1]);
            right.Layout.Row    = 2;
            right.Layout.Column = 2;
            right.ColumnWidth   = {'fit'};
            right.Padding       = [0 0 0 0];
            right.RowSpacing    = 4;

            obj.buildLeftColumn(left);
            obj.buildRightColumn(right);

            % Initial sync. Order matters: the spec pickers depend on the
            % bolt selection, and the length readout depends on all of them.
            obj.populateSpecPickers();
            obj.installAnalyzeShortcut();
            obj.updateSpecFields(false);
            obj.updateEngagementFieldMode();
            obj.applyNutSpec();
            obj.refreshWasherState();
            obj.syncJointLoadVisibility();
            obj.updateGripLength();
            obj.updateBoltLengthLabel();
            obj.validateRequiredFields();

            obj.listenTo('JointChanged',   @() obj.refresh());
            obj.listenTo('LoadCaseChanged', @() obj.refresh());
            obj.listenTo('LibraryChanged', @() obj.refreshLibraryDropdowns());
        end

        function refresh(obj)
            %REFRESH  AppState.Joint + LoadCase -> controls. Never dirty.
            if ~obj.IsBuilt || obj.Refreshing
                return
            end
            obj.Refreshing = true;
            c = onCleanup(@() obj.clearRefreshing()); %#ok<NASGU>
            obj.applyJoint(obj.State.Joint);
            obj.applyLoadCase(obj.State.LoadCase);
        end
    end

    % ---- Left column: the joint in physical stack order -------------------
    methods (Access = private)
        function buildLeftColumn(obj, col)
            r = 0;

            % ---- 1. Identity ------------------------------------------
            r = r + 1;
            b = obj.addGroup(col, r, 'Identity', true);
            obj.JointNameField = obj.addTextRow(b, 1, 'Joint name', '', ...
                'Name this joint is stored and reported under.');
            obj.bindEdit(obj.JointNameField, @(~, ~) obj.commitJoint());

            % ---- 2. Bolt ----------------------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Bolt', true);
            obj.BoltDropDown = obj.addDropdownRow(b, 1, 'Bolt', ...
                obj.boltItems(), 'Bolt designation from the hardware library.');
            obj.bindEdit(obj.BoltDropDown, @(~, ~) obj.onBoltChanged());

            obj.BoltMaterialDropDown = obj.addDropdownRow(b, 2, 'Bolt material', ...
                obj.materialItems('bolt'), ...
                ['REQUIRED. Feeds every strength check. Starts blank — a ' ...
                 'silently defaulted material analyses the wrong metal and ' ...
                 'looks deliberate.']);
            obj.bindEdit(obj.BoltMaterialDropDown, @(~, ~) obj.onBoltMaterialChanged());

            obj.SpecLabel = uilabel(b, 'Text', 'Bolt spec: —', 'WordWrap', 'on');
            obj.SpecLabel.Layout.Row    = 3;
            obj.SpecLabel.Layout.Column = [1 2];

            obj.BoltCountField = obj.addNumericRow(b, 4, 'Bolt count nf', ...
                'Number of fasteners in the joint pattern.');
            obj.BoltCountField.Limits = [1 Inf];
            obj.BoltCountField.RoundFractionalValues = 'on';
            obj.bindEdit(obj.BoltCountField, @(~, ~) obj.commitJoint());

            % ---- 3. Washer under bolt head ----------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Washer under bolt head', false);
            obj.HeadWasher = obj.buildWasherGroup(b, 'Head');

            % ---- 4. Flange stack --------------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Flange stack (clamped layers)', true);
            obj.buildFlangeGrid(b);

            % ---- 5. Washer under nut ----------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Washer under nut', false);
            obj.NutWasherSameAsHeadCheck = uicheckbox(b, 'Text', 'Same as Head', ...
                'Value', false);
            obj.NutWasherSameAsHeadCheck.Layout.Row    = 1;
            obj.NutWasherSameAsHeadCheck.Layout.Column = [1 3];
            obj.NutWasherSameAsHeadCheck.Tooltip = ['Mirror the head washer ' ...
                '(spec, size, material, OD/ID/thickness) live and gray out ' ...
                'this group. Unticking keeps the mirrored values and ' ...
                're-enables editing — it never blanks them.'];
            obj.bindEdit(obj.NutWasherSameAsHeadCheck, @(~, ~) obj.onSameAsHeadToggled());
            obj.NutWasher = obj.buildWasherGroup(b, 'Nut', 1);

            % ---- 6. Threaded member -----------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Threaded member', true);
            obj.MemberTypeDropDown = obj.addDropdownRow(b, 1, 'Type', ...
                gui2.JointConfigPage.memberTypeItems(), ...
                'Nut, helical insert, tapped hole, or none (bolt only).');
            obj.bindEdit(obj.MemberTypeDropDown, @(~, ~) obj.onMemberTypeChanged());

            [obj.MemberMaterialDropDown, obj.MemberMaterialLabel] = ...
                obj.addDropdownRow(b, 2, 'Nut material', obj.materialItems(), ...
                ['REQUIRED. Its role changes with Type: the nut''s own ' ...
                 'material for a Nut, the PARENT (host) material for an ' ...
                 'insert or a tapped hole.']);
            obj.bindEdit(obj.MemberMaterialDropDown, @(~, ~) obj.onMemberMaterialChanged());

            obj.NutSpecDropDown = obj.addDropdownRow(b, 3, 'Nut spec', {'Custom'}, ...
                ['Pick a nut family to auto-fill and lock the material and ' ...
                 'engagement below, matched to the selected bolt''s thread ' ...
                 'size. "Custom" re-enables them and always remains ' ...
                 'available. Nut type only.']);
            obj.bindEdit(obj.NutSpecDropDown, @(~, ~) obj.applyNutSpec());

            [obj.EngagementField, obj.EngagementFieldLabel] = ...
                obj.addTextRow(b, 4, 'Engagement length Le (in)', '', '');
            obj.bindEdit(obj.EngagementField, @(~, ~) obj.onEngagementEdited());

            % ---- 7. Bolt length & grip --------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Bolt length & grip', true);
            obj.BoltLengthField = obj.addTextRow(b, 1, 'Overall bolt length (in)', '', ...
                ['OVERALL length, under-head to tip — not the thread length ' ...
                 'and not L1. Blank = the engine estimates it as grip + nut ' ...
                 'height + 2*pitch (NASA-STD-5020B 4.7.4) and the readout ' ...
                 'below reports "not evaluated".']);
            obj.bindEdit(obj.BoltLengthField, @(~, ~) obj.onLengthInputEdited());

            obj.GripLabel = uilabel(b, 'Text', 'Grip length: —');
            obj.GripLabel.Layout.Row    = 2;
            obj.GripLabel.Layout.Column = [1 2];

            obj.BoltLengthLabel = uilabel(b, 'Text', '', 'VerticalAlignment', 'top');
            obj.BoltLengthLabel.Layout.Row    = 3;
            obj.BoltLengthLabel.Layout.Column = [1 2];
            obj.BoltLengthLabel.FontColor     = gui2.palette('mutedText');
            obj.BoltLengthLabel.Tooltip = ['Live bolt-length adequacy ' ...
                '(engine.boltLengthCheck): grip, required engagement, ' ...
                'minimum bolt length, and the verdict on the entered ' ...
                'length. Recomputes on every relevant edit, before Analyze.'];
            b.RowHeight{3} = 64;   % four lines

            % ---- 8. Advanced / overrides ------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Advanced / overrides', false);
            obj.BodyLengthField = obj.addTextRow(b, 1, ...
                'Unthreaded body length L1 (in)', '', ...
                ['L1 — the UNTHREADED shank length inside the clamp, for ' ...
                 'bolt stiffness. NOT the bolt length. REQUIRED for bolt ' ...
                 'stiffness: catalogue bolts carry no thread length, so it ' ...
                 'cannot be derived. Blank leaves stiffness — and every ' ...
                 'check downstream of it — unevaluated.']);
            obj.bindEdit(obj.BodyLengthField, @(~, ~) obj.commitJoint());

            obj.RatedOverrideCheck = uicheckbox(b, 'Text', ...
                'Override the library''s rated loads', 'Value', false);
            obj.RatedOverrideCheck.Layout.Row    = 2;
            obj.RatedOverrideCheck.Layout.Column = [1 3];
            obj.RatedOverrideCheck.Tooltip = ['The two fields below ' ...
                'auto-fill from the library for the selected bolt and ' ...
                'material, and stay locked. Tick to enter them by hand — ' ...
                'needed when a bolt/material pair has no library spec, ' ...
                'where the engine otherwise falls back to At*Ftu, a ' ...
                'derived convention rather than a published allowable.'];
            obj.bindEdit(obj.RatedOverrideCheck, @(~, ~) obj.onRatedOverrideToggled());

            obj.RatedUltField = obj.addTextRow(b, 3, 'Bolt rated ultimate (lbf)', '', ...
                'Spec-rated bolt ultimate load. Auto-filled from the library.');
            obj.bindEdit(obj.RatedUltField, @(~, ~) obj.commitJoint());
            obj.RatedYieldField = obj.addTextRow(b, 4, 'Bolt rated yield (lbf)', '', ...
                'Spec-rated bolt yield load. Auto-filled from the library.');
            obj.bindEdit(obj.RatedYieldField, @(~, ~) obj.commitJoint());

            obj.FrustumAngleField = obj.addNumericRow(b, 5, 'Frustum half-angle (deg)', ...
                'Conical-frustum half-angle for the member-stiffness model. Integer degrees.');
            obj.FrustumAngleField.Limits = [1 90];
            obj.FrustumAngleField.UpperLimitInclusive = 'off';
            obj.FrustumAngleField.RoundFractionalValues = 'on';
            obj.bindEdit(obj.FrustumAngleField, @(~, ~) obj.commitJoint());
        end

        function buildFlangeGrid(obj, parent)
            %BUILDFLANGEGRID  Four layer rows plus a column header.
            %   A row is IN USE when Active is checked AND thickness > 0 —
            %   the same predicate that marshals the stack and that decides
            %   whether the row's material is required.
            fg = uigridlayout(parent, [gui2.JointConfigPage.MaxFlangeLayers + 1, 8]);
            fg.Layout.Row    = 1;
            fg.Layout.Column = [1 3];
            fg.ColumnWidth   = {46, 40, 100, 130, 62, 74, 74, 62};
            fg.RowHeight     = repmat({26}, 1, gui2.JointConfigPage.MaxFlangeLayers + 1);
            fg.RowSpacing    = 4;
            fg.ColumnSpacing = 4;
            fg.Padding       = [0 0 0 0];

            heads = {'Active', 'Layer', 'Name', 'Material', 't (in)', ...
                     'Hole (in)', 'Edge (in)', 'Tear-out'};
            tips = { ...
                ['Include this layer in the clamped stack. Unchecked = ' ...
                 'excluded entirely; its values are kept, so re-checking ' ...
                 'restores it.'], ...
                'Layer number, top = under the bolt head.', ...
                'Optional label. Never affects the analysis.', ...
                'Layer material. REQUIRED while the row is in use.', ...
                'Layer thickness t, in. 0 = row unused.', ...
                'Clearance/hole diameter, in. Blank = not supplied.', ...
                'Hole centre to free edge, in. Blank = tear-out not evaluated.', ...
                'Run the shear tear-out check on this layer.'};
            for c = 1:numel(heads)
                h = uilabel(fg, 'Text', heads{c}, 'Tooltip', tips{c}, ...
                    'FontWeight', 'bold');
                h.Layout.Row = 1; h.Layout.Column = c;
            end

            n = gui2.JointConfigPage.MaxFlangeLayers;
            obj.FlangeActive    = cell(1, n);
            obj.FlangeName      = cell(1, n);
            obj.FlangeMaterial  = cell(1, n);
            obj.FlangeThickness = cell(1, n);
            obj.FlangeHole      = cell(1, n);
            obj.FlangeEdge      = cell(1, n);
            obj.FlangeTearout   = cell(1, n);
            mats = obj.materialItems();

            for i = 1:n
                row = i + 1;
                ak = uicheckbox(fg, 'Text', '', 'Value', true, 'Tooltip', tips{1});
                ak.Layout.Row = row; ak.Layout.Column = 1;
                obj.bindEdit(ak, @(~, ~) obj.onFlangeEdited());

                lb = uilabel(fg, 'Text', sprintf('%d', i), 'Tooltip', tips{2});
                lb.Layout.Row = row; lb.Layout.Column = 2;

                nf = uieditfield(fg, 'text', 'Tooltip', tips{3});
                nf.Layout.Row = row; nf.Layout.Column = 3;
                obj.bindEdit(nf, @(~, ~) obj.commitJoint());

                dd = uidropdown(fg, 'Items', mats, ...
                    'Value', gui2.JointConfigPage.BlankChoice, 'Tooltip', tips{4});
                dd.Layout.Row = row; dd.Layout.Column = 4;
                obj.bindEdit(dd, @(~, ~) obj.onFlangeEdited());

                tf = uieditfield(fg, 'numeric', 'Limits', [0 Inf], 'Tooltip', tips{5});
                tf.Layout.Row = row; tf.Layout.Column = 5;
                obj.bindEdit(tf, @(~, ~) obj.onFlangeEdited());

                hf = uieditfield(fg, 'text', 'Tooltip', tips{6});
                hf.Layout.Row = row; hf.Layout.Column = 6;
                obj.bindEdit(hf, @(~, ~) obj.commitJoint());

                ef = uieditfield(fg, 'text', 'Tooltip', tips{7});
                ef.Layout.Row = row; ef.Layout.Column = 7;
                obj.bindEdit(ef, @(~, ~) obj.commitJoint());

                ck = uicheckbox(fg, 'Text', '', 'Value', true, 'Tooltip', tips{8});
                ck.Layout.Row = row; ck.Layout.Column = 8;
                obj.bindEdit(ck, @(~, ~) obj.commitJoint());

                obj.FlangeActive{i}    = ak;
                obj.FlangeName{i}      = nf;
                obj.FlangeMaterial{i}  = dd;
                obj.FlangeThickness{i} = tf;
                obj.FlangeHole{i}      = hf;
                obj.FlangeEdge{i}      = ef;
                obj.FlangeTearout{i}   = ck;
            end
        end

        function w = buildWasherGroup(obj, parent, group, rowOffset)
            %BUILDWASHERGROUP  The seven controls of one washer group.
            %   Returned as a struct so applyWasherSpec and the mirror can
            %   take either group without a seven-output dispatcher.
            if nargin < 4
                rowOffset = 0;
            end
            r = rowOffset;
            w = struct();

            w.Present = uicheckbox(parent, 'Text', 'Washer present', 'Value', false);
            w.Present.Layout.Row    = r + 1;
            w.Present.Layout.Column = [1 3];
            w.Present.Tooltip = ['Rigid in the frustum stiffness model; its ' ...
                'thickness counts toward the grip.'];
            obj.bindEdit(w.Present, @(~, ~) obj.onWasherPresentToggled());

            w.Spec = obj.addDropdownRow(parent, r + 2, 'Washer spec', {'Custom'}, ...
                ['Pick a washer family to list its matches at the selected ' ...
                 'bolt''s thread size in the size dropdown below. Choosing a ' ...
                 'size auto-fills and locks OD/ID/thickness. "Custom" ' ...
                 're-enables them.']);
            obj.bindEdit(w.Spec, @(~, ~) obj.onWasherSpecChanged(group));

            w.Size = obj.addDropdownRow(parent, r + 3, 'Washer size', ...
                {gui2.JointConfigPage.WasherSizeNA}, ...
                ['Size/thickness match from the family above. Multiple ' ...
                 'thicknesses at one thread size list thinnest first.']);
            w.Size.Enable = 'off';
            obj.bindEdit(w.Size, @(~, ~) obj.onWasherSizeChanged(group));

            w.Material = obj.addDropdownRow(parent, r + 4, 'Washer material', ...
                obj.materialItems('washer'), ...
                ['Independent of the spec family — washers are geometry ' ...
                 'only, so the picker never locks this.']);
            obj.bindEdit(w.Material, @(~, ~) obj.onWasherEdited(group));

            w.OD = obj.addTextRow(parent, r + 5, 'Outer diameter (in)', '', ...
                ['OUTER DIAMETER of the bearing face. Also the frustum ' ...
                 'contact diameter in engine.stiffness.']);
            obj.bindEdit(w.OD, @(~, ~) obj.onWasherEdited(group));

            w.ID = obj.addTextRow(parent, r + 6, 'Inner diameter (in)', '', ...
                'Washer ID, in. Carried for completeness; unused by the engine.');
            obj.bindEdit(w.ID, @(~, ~) obj.onWasherEdited(group));

            w.Thk = obj.addNumericRow(parent, r + 7, 'Thickness (in)', ...
                'Adds clamped length in engine.stiffness (washers are rigid).');
            w.Thk.Limits = [0 Inf];
            w.Thk.ValueDisplayFormat = '%.5f';
            obj.bindEdit(w.Thk, @(~, ~) obj.onWasherEdited(group));
        end
    end

    % ---- Right column: loads, assumptions, run ----------------------------
    methods (Access = private)
        function buildRightColumn(obj, col)
            r = 0;

            % ---- 9. Preload -------------------------------------------
            r = r + 1;
            b = obj.addGroup(col, r, 'Preload (torque-controlled)', true);
            obj.NominalTorqueField = obj.addTextRow(b, 1, 'Nominal torque (in-lbf)', '', ...
                'Nominal applied effective torque, above running torque. Blank = not set.');
            obj.bindEdit(obj.NominalTorqueField, @(~, ~) obj.commitJoint());

            obj.TorqueTolField = obj.addNumericRow(b, 2, 'Torque tolerance (frac)', ...
                'Fractional torque tolerance: 0.10 means +/-10%.');
            obj.TorqueTolField.Limits = [0 Inf];
            obj.TorqueTolField.ValueDisplayFormat = '%.2f';
            obj.bindEdit(obj.TorqueTolField, @(~, ~) obj.commitJoint());

            obj.NutFactorField = obj.addNumericRow(b, 3, 'Nut factor K', ...
                'Torque-to-preload nut factor K.');
            obj.NutFactorField.Limits = [0 Inf];
            obj.NutFactorField.ValueDisplayFormat = '%.2f';
            obj.bindEdit(obj.NutFactorField, @(~, ~) obj.commitJoint());

            obj.UncertaintyField = obj.addNumericRow(b, 4, 'Uncertainty (Gamma)', ...
                'Preload uncertainty, fractional (e.g. 0.25).');
            obj.UncertaintyField.Limits = [0 Inf];
            obj.UncertaintyField.ValueDisplayFormat = '%.2f';
            obj.bindEdit(obj.UncertaintyField, @(~, ~) obj.commitJoint());

            obj.RelaxationField = obj.addNumericRow(b, 5, 'Relaxation fraction', ...
                'Short-term preload relaxation, fractional (e.g. 0.05).');
            obj.RelaxationField.Limits = [0 Inf];
            obj.RelaxationField.ValueDisplayFormat = '%.2f';
            obj.bindEdit(obj.RelaxationField, @(~, ~) obj.commitJoint());

            obj.SeparationCriticalCheck = uicheckbox(b, 'Text', ...
                'Separation critical joint', 'Value', false);
            obj.SeparationCriticalCheck.Layout.Row    = 6;
            obj.SeparationCriticalCheck.Layout.Column = [1 3];
            obj.SeparationCriticalCheck.Tooltip = ...
                'Selects the engine''s minimum-preload equation.';
            obj.bindEdit(obj.SeparationCriticalCheck, @(~, ~) obj.commitJoint());

            % ---- 10. Applied loads ------------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Applied loads (single joint only)', true);
            obj.CaseNameField = obj.addTextRow(b, 1, 'Case name', '', ...
                'Label for this load case. Bulk analysis ignores these loads.');
            obj.bindEdit(obj.CaseNameField, @(~, ~) obj.commitLoadCase());

            obj.BoltTensileField = obj.addTextRow(b, 2, 'Bolt tensile limit PtL', '', ...
                'Most-loaded bolt tensile limit load, lbf. Blank = not set.');
            obj.bindEdit(obj.BoltTensileField, @(~, ~) obj.commitLoadCase());

            obj.BoltShearField = obj.addTextRow(b, 3, 'Bolt shear limit PsL', '', ...
                'Most-loaded bolt shear limit load, lbf. Blank = not set.');
            obj.bindEdit(obj.BoltShearField, @(~, ~) obj.commitLoadCase());

            % Joint totals are shown ONLY for Slip mode = Joint (Section
            % 7.3). Eq. 84 needs them; the single-fastener default does not,
            % and showing them unconditionally is what made them confusing.
            jointTip = ['Joint-level total, lbf. Required by NASA-STD-5020B ' ...
                'Eq. 84 when Slip mode is Joint. NOT BoltCount x the ' ...
                'per-bolt load — bolt-pattern distribution means the engine ' ...
                'cannot derive it, and blank leaves the Slip check ' ...
                'unevaluated. Enter it explicitly.'];
            [obj.JointTensileField, lblT] = obj.addTextRow(b, 4, ...
                'Joint tensile total', '', jointTip);
            obj.bindEdit(obj.JointTensileField, @(~, ~) obj.commitLoadCase());
            [obj.JointShearField, lblS] = obj.addTextRow(b, 5, ...
                'Joint shear total', '', jointTip);
            obj.bindEdit(obj.JointShearField, @(~, ~) obj.commitLoadCase());
            obj.JointLoadRows = {lblT, obj.JointTensileField, lblS, obj.JointShearField};

            % ---- 11. Analysis assumptions -----------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Analysis assumptions', true);
            obj.ShearPlaneDropDown = obj.addDropdownRow(b, 1, 'Shear plane', ...
                obj.enumItems('model.ShearPlaneCondition'), ...
                ['Does the shear plane cut the THREADS or the full-diameter ' ...
                 'BODY? Body if the unthreaded shank extends past the faying ' ...
                 'surface; threads otherwise. Sets the shear area ' ...
                 '(NASA-STD-5020B Eq. 12 shank area vs Eq. 13 minor-diameter ' ...
                 'area) AND the interaction exponents (Eq. 20/21 body ' ...
                 '2.5/1.5; Eq. 22/23 threads 1.2/2.0). Threads is the ' ...
                 'conservative choice.']);
            obj.bindEdit(obj.ShearPlaneDropDown, @(~, ~) obj.commitJoint());

            obj.SlipModeDropDown = obj.addDropdownRow(b, 2, 'Slip mode', ...
                obj.enumItems('model.SlipMode'), ...
                ['Single fastener (Eq. 86) uses the per-bolt loads above. ' ...
                 'Joint (Eq. 84) needs the joint totals, which appear when ' ...
                 'this is selected.']);
            obj.bindEdit(obj.SlipModeDropDown, @(~, ~) obj.onSlipModeChanged());

            obj.FrictionField = obj.addNumericRow(b, 3, 'Friction coefficient', ...
                '0 = slip not evaluated.');
            obj.FrictionField.Limits = [0 Inf];
            obj.bindEdit(obj.FrictionField, @(~, ~) obj.commitJoint());

            obj.BoltAxisDropDown = obj.addDropdownRow(b, 4, 'Bolt axis', ...
                obj.enumItems('model.BoltAxis'), ...
                ['Global FEM axis the fastener acts along; splits element ' ...
                 'forces into tension (this axis) and shear (RSS of the ' ...
                 'other two).']);
            obj.bindEdit(obj.BoltAxisDropDown, @(~, ~) obj.commitJoint());

            obj.LoadingPlaneField = obj.addNumericRow(b, 5, 'Loading-plane factor n', ...
                'n = Llp/L. 1.0 is conservative.');
            obj.bindEdit(obj.LoadingPlaneField, @(~, ~) obj.commitJoint());

            % Section 7.2(f): the shear-transfer control is deliberately
            % absent and NotDeclared is hard-set in marshalling. Stated on
            % the form because the assumption is the analyst's to know.
            note = uilabel(b, 'Text', ['Close-fit assumed — bolt bending ' ...
                '(fbu = 0) not yet implemented; NASA-STD-5020B 4.4.4 ' ...
                'exemption assumed, not verified.'], 'WordWrap', 'on');
            note.Layout.Row    = 6;
            note.Layout.Column = [1 3];
            note.FontColor     = gui2.palette('mutedText');

            % ---- 12. Actions ------------------------------------------
            r = r + 2;
            b = obj.addGroup(col, r, 'Actions', true);
            obj.AnalyzeButton = uibutton(b, 'push', 'Text', 'Analyze Single Joint', ...
                'FontWeight', 'bold');
            obj.AnalyzeButton.Layout.Row    = 1;
            obj.AnalyzeButton.Layout.Column = [1 3];
            obj.AnalyzeDefaultTooltip = ['Marshal these controls into a joint ' ...
                'and load case, take the global factors and temperatures, ' ...
                'and run engine.analyze. F5 does the same.'];
            obj.AnalyzeButton.Tooltip = obj.AnalyzeDefaultTooltip;
            obj.AnalyzeButton.ButtonPushedFcn = @(~, ~) obj.onAnalyze();

            obj.SaveJointButton = uibutton(b, 'push', 'Text', 'Save to Defined Joints');
            obj.SaveJointButton.Layout.Row    = 2;
            obj.SaveJointButton.Layout.Column = [1 3];
            obj.SaveJointButton.Tooltip = ['Store this joint in the defined ' ...
                'joints library under its name, for the bulk workflow. Asks ' ...
                'before overwriting.'];
            obj.SaveJointButton.ButtonPushedFcn = @(~, ~) obj.onSaveToDefinedJoints();
        end
    end

    % ---- Reactive logic: the cascade --------------------------------------
    methods (Access = private)
        function onBoltChanged(obj)
            %ONBOLTCHANGED  One bolt change invalidates every thread-keyed
            %   match: bolt spec, nut spec, both washer specs.
            obj.updateSpecFields(true);
            obj.applyNutSpec();
            obj.refreshWasherState();
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onBoltMaterialChanged(obj)
            obj.updateSpecFields(true);
            obj.validateRequiredFields();
            obj.commitJoint();
        end

        function onMemberMaterialChanged(obj)
            obj.validateRequiredFields()
            obj.commitJoint();
        end

        function updateSpecFields(obj, autofill)
            %UPDATESPECFIELDS  Bolt+material -> rated loads, from the library.
            %   Pure lookup, no math. autofill=false refreshes only the
            %   label, so a loaded case's stored (possibly overridden)
            %   rated loads are not clobbered by the library values.
            if nargin < 2
                autofill = true;
            end
            if isempty(obj.SpecLabel) || ~obj.State.LibraryOK
                return
            end
            s = [];
            try
                s = obj.State.Library.boltSpecFor( ...
                    string(obj.BoltDropDown.Value), ...
                    string(obj.BoltMaterialDropDown.Value));
            catch
                s = [];
            end
            if isempty(s)
                obj.SpecLabel.Text = ['Bolt spec: no library match — enter ' ...
                    'rated loads via the override, or leave blank for ' ...
                    'engine-derived values'];
                % Amber: "cannot look up" is not an OK state.
                obj.SpecLabel.FontColor = gui2.palette('statusWarn');
                if autofill && ~obj.RatedOverrideCheck.Value
                    % Blank the PREVIOUS pairing's values. Keeping them
                    % would analyse the new pairing with the old bolt's
                    % numbers.
                    obj.RatedUltField.Value   = '';
                    obj.RatedYieldField.Value = '';
                end
            else
                obj.SpecLabel.FontColor = gui2.palette('defaultText');
                if autofill && ~obj.RatedOverrideCheck.Value
                    obj.SpecLabel.Text = sprintf( ...
                        'Bolt spec: %s (rated loads auto-filled from library)', ...
                        char(s.Key));
                    obj.RatedUltField.Value   = sprintf('%g', s.RatedUltimateLoad);
                    obj.RatedYieldField.Value = sprintf('%g', s.RatedYieldLoad);
                else
                    obj.SpecLabel.Text = sprintf('Bolt spec: %s', char(s.Key));
                end
            end
            obj.SpecLabel.Tooltip = obj.SpecLabel.Text;
            obj.applyRatedLock();
        end

        function applyRatedLock(obj)
            %APPLYRATEDLOCK  Section 7.2(e): locked display by default,
            %   unlocked only by the explicit override. Enable only, never
            %   read-only (A5).
            if isempty(obj.RatedUltField)
                return
            end
            states = {'off', 'on'};
            e = states{obj.RatedOverrideCheck.Value + 1};
            obj.RatedUltField.Enable   = e;
            obj.RatedYieldField.Enable = e;
        end

        function onRatedOverrideToggled(obj)
            obj.applyRatedLock();
            if ~obj.RatedOverrideCheck.Value
                % Returning to library control: re-resolve, so the fields
                % cannot keep a hand-typed number while claiming to be
                % library-backed.
                obj.updateSpecFields(true);
            end
            obj.commitJoint();
        end

        function onMemberTypeChanged(obj)
            %ONMEMBERTYPECHANGED  Type drives the member-material LABEL, the
            %   nut-spec picker, the nut-washer group, and the engagement
            %   field's UNITS.
            %
            %   A9: engagement means inches for Nut/Tapped Hole and a
            %   multiple of the bolt nominal diameter for Insert. Crossing
            %   that boundary CLEARS the field rather than converting it —
            %   a conversion needs a diameter that is not always resolvable
            %   AND would silently swap the analyst's intent between an
            %   absolute target and a length-class multiple. Nut <-> Tapped
            %   Hole is not a crossing; the value survives.
            wasInsert = obj.EngagementIsInsertMode;
            isInsert  = obj.selectedMemberType() == model.ThreadedMemberType.Insert;
            if isInsert ~= wasInsert && ~isempty(strtrim(obj.EngagementField.Value))
                obj.EngagementField.Value = '';
                obj.setStatus(['Engagement Le cleared — its meaning changes ' ...
                    'between inches (Nut / Tapped Hole) and x bolt nominal ' ...
                    'diameter (Helical Insert).']);
            end
            obj.updateMemberMaterialLabel();
            obj.updateEngagementFieldMode();
            obj.applyNutSpec();
            obj.refreshWasherState();
            obj.updateBoltLengthLabel();
            obj.validateRequiredFields();
            obj.commitJoint();
        end

        function updateMemberMaterialLabel(obj)
            %UPDATEMEMBERMATERIALLABEL  Section 7.2(a): one dropdown, three
            %   roles — label it for the role it is playing.
            if isempty(obj.MemberMaterialLabel)
                return
            end
            switch obj.selectedMemberType()
                case model.ThreadedMemberType.Nut
                    obj.MemberMaterialLabel.Text = 'Nut material';
                case model.ThreadedMemberType.None
                    obj.MemberMaterialLabel.Text = 'Member material';
                otherwise
                    obj.MemberMaterialLabel.Text = 'Parent (host) material';
            end
        end

        function updateEngagementFieldMode(obj)
            %UPDATEENGAGEMENTFIELDMODE  Relabel and re-tooltip the engagement
            %   field for the CURRENT type, and record the mode so a later
            %   crossing can be detected.
            %
            %   NEVER TOUCHES THE VALUE. Only onMemberTypeChanged clears it,
            %   on a genuine user crossing; if this did, loading a case
            %   would wipe the number it just loaded.
            if isempty(obj.EngagementField)
                return
            end
            isInsert = obj.selectedMemberType() == model.ThreadedMemberType.Insert;
            if isInsert
                obj.EngagementFieldLabel.Text = 'Engagement Le (x bolt D)';
                tip = ['Thread engagement as a MULTIPLE OF THE BOLT NOMINAL ' ...
                    'DIAMETER (e.g. 1.5 for 1.5D). Helical inserts are ' ...
                    'specified by length CLASS, not an absolute inch value ' ...
                    '(NASM33537 Rev 4 Sec 6.1: 1, 1.5, 2, 2.5 or 3 x nominal ' ...
                    'major diameter). Feeds the length readout, the ' ...
                    'stiffness L1 estimate, and the insert pull-out margin. ' ...
                    'Blank = pull-out unassessed and the readout reports ' ...
                    '"not evaluated".'];
            else
                obj.EngagementFieldLabel.Text = 'Engagement length Le (in)';
                tip = ['Thread engagement in INCHES — nut thread height, or ' ...
                    'tapped-hole engagement depth. Gates the live ' ...
                    'bolt-length readout, the stiffness L1 estimate, and ' ...
                    'the thread-shear checks. Blank = all of those report ' ...
                    '"not evaluated".'];
            end
            obj.EngagementField.Tooltip      = tip;
            obj.EngagementFieldLabel.Tooltip = tip;
            obj.EngagementIsInsertMode       = isInsert;
        end

        function onEngagementEdited(obj)
            obj.updateBoltLengthLabel()
            obj.commitJoint();
        end

        function applyNutSpec(obj)
            %APPLYNUTSPEC  Resolve the nut family against the selected
            %   bolt's thread size and lock what it fills (A5).
            %
            %   NEVER MARKS DIRTY — state sync, not an edit. Idempotent, and
            %   safe before the panel exists.
            if isempty(obj.NutSpecDropDown) || ~obj.State.LibraryOK
                return
            end
            isNut = obj.selectedMemberType() == model.ThreadedMemberType.Nut;
            if ~isNut
                % Meaningful only for a Nut. Lock the picker to Custom and
                % leave the fields freely editable — their normal state for
                % the other types.
                obj.NutSpecDropDown.Value  = 'Custom';
                obj.NutSpecDropDown.Enable = 'off';
                obj.setNutFieldsEnable('on');
                return
            end
            obj.NutSpecDropDown.Enable = 'on';
            spec = string(obj.NutSpecDropDown.Value);
            if spec == "Custom"
                obj.setNutFieldsEnable('on');   % values left in place
                return
            end
            n = [];
            try
                bolt = obj.State.Library.bolt(string(obj.BoltDropDown.Value));
                n = obj.State.Library.nutFor(bolt.NominalDiameter, ...
                    bolt.ThreadsPerInch, spec);
            catch
                n = [];
            end
            if isempty(n)
                % No entry at this thread size. Revert to Custom rather
                % than leave a previous bolt's numbers locked and looking
                % authoritative, and NAME the miss.
                obj.NutSpecDropDown.Value = 'Custom';
                obj.setNutFieldsEnable('on');
                obj.setStatus(sprintf(['No %s nut matches bolt thread "%s" — ' ...
                    'nut spec reverted to Custom; enter the nut fields ' ...
                    'manually.'], char(spec), char(obj.BoltDropDown.Value)));
                return
            end
            obj.EngagementField.Value = gui2.JointConfigPage.fmtOptional(n.Height);
            % A material named by the nut but absent from the library must
            % not leave a stale selection locked — the exact failure the
            % picker exists to prevent.
            if ~obj.trySelect(obj.MemberMaterialDropDown, n.Material)
                obj.NutSpecDropDown.Value = 'Custom';
                obj.setNutFieldsEnable('on');
                obj.setStatus(sprintf(['Nut "%s" names a material not in ' ...
                    'the library (%s) — nut spec reverted to Custom; check ' ...
                    'the nut fields manually.'], char(n.Key), char(n.Material)));
                return
            end
            obj.setNutFieldsEnable('off');
            obj.updateBoltLengthLabel();
            obj.validateRequiredFields();
        end

        function setNutFieldsEnable(obj, state)
            %SETNUTFIELDSENABLE  Enable only — never read-only (A5).
            obj.MemberMaterialDropDown.Enable = state
            obj.EngagementField.Enable        = state;
        end

        % ---- Washers -------------------------------------------------
        function onWasherPresentToggled(obj)
            obj.refreshWasherState();
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onWasherSpecChanged(obj, group)
            obj.applyWasherSpec(group);
            if strcmp(group, 'Head') && obj.NutWasherSameAsHeadCheck.Value
                obj.mirrorNutWasherFromHead();
            end
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onWasherSizeChanged(obj, group)
            obj.fillWasherFromSize(group);
            if strcmp(group, 'Head') && obj.NutWasherSameAsHeadCheck.Value
                obj.mirrorNutWasherFromHead();
            end
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onWasherEdited(obj, group)
            if strcmp(group, 'Head') && obj.NutWasherSameAsHeadCheck.Value
                obj.mirrorNutWasherFromHead();
            end
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onSameAsHeadToggled(obj)
            %ONSAMEASHEADTOGGLED  Ticked: mirror live and gray the group.
            %   Unticked: restore independent editing with the mirrored
            %   values LEFT IN PLACE — never blanked.
            if obj.NutWasherSameAsHeadCheck.Value
                obj.mirrorNutWasherFromHead();
            else
                obj.refreshWasherState();
            end
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function refreshWasherState(obj)
            %REFRESHWASHERSTATE  The one orchestrator. Three gates on the
            %   nut group, outermost first: member type is not Nut -> whole
            %   group off (there is no nut, so a washer under it is
            %   meaningless); then Same as Head -> mirror and off; then
            %   Present -> gate the fields.
            %
            %   NEVER MARKS DIRTY (state sync).
            if isempty(obj.HeadWasher) || isempty(obj.HeadWasher.Spec)
                return
            end
            obj.syncWasherEnables();
            obj.applyWasherSpec('Head');

            if obj.selectedMemberType() ~= model.ThreadedMemberType.Nut
                obj.setNutWasherGroupEnable('off');
                return
            end
            obj.setNutWasherGroupEnable('on');
            if obj.NutWasherSameAsHeadCheck.Value
                obj.mirrorNutWasherFromHead();
            else
                obj.applyWasherSpec('Nut');
            end
        end

        function syncWasherEnables(obj)
            %SYNCWASHERENABLES  Present gates each group's material and
            %   geometry. Material's ONLY gate — the spec picker never
            %   touches it, since washer material is independent of family.
            states = {'off', 'on'};
            for w = [obj.HeadWasher, obj.NutWasher]
                e = states{w.Present.Value + 1};
                w.OD.Enable  = e;
                w.ID.Enable  = e;
                w.Thk.Enable = e;
                if obj.State.LibraryOK
                    w.Material.Enable = e;
                end
            end
        end

        function setNutWasherGroupEnable(obj, state)
            %SETNUTWASHERGROUPENABLE  The outermost gate. 'on' re-enables
            %   only the two top-level controls; the finer gates are applied
            %   immediately afterward by the caller and must not be
            %   second-guessed here.
            %
            %   GRAY, NOT HIDE: an analyst has to be able to see that the
            %   fields exist and why they are unavailable.
            obj.NutWasher.Present.Enable        = state;
            obj.NutWasherSameAsHeadCheck.Enable = state;
            if strcmp(state, 'off')
                w = obj.NutWasher;
                w.Spec.Enable = 'off';  w.Size.Enable = 'off';
                w.Material.Enable = 'off';
                w.OD.Enable = 'off';    w.ID.Enable = 'off';
                w.Thk.Enable = 'off';
            end
        end

        function mirrorNutWasherFromHead(obj)
            %MIRRORNUTWASHERFROMHEAD  Live copy, not a one-time snapshot.
            h = obj.HeadWasher;
            n = obj.NutWasher;
            n.Present.Value = h.Present.Value;
            n.Spec.Value    = h.Spec.Value;
            % The size list is family-specific and the two lists routinely
            % differ in LENGTH, so it must be copied wholesale through
            % setItemsAndData before the value can follow. A bare Items
            % assignment throws while the old ItemsData pairing is attached.
            gui2.JointConfigPage.setItemsAndData(n.Size, h.Size.Items, h.Size.ItemsData);
            n.Size.Value     = h.Size.Value;
            n.Material.Value = h.Material.Value;
            n.OD.Value       = h.OD.Value;
            n.ID.Value       = h.ID.Value;
            n.Thk.Value      = h.Thk.Value;
            n.Present.Enable = 'off';  n.Spec.Enable = 'off';
            n.Size.Enable    = 'off';  n.Material.Enable = 'off';
            n.OD.Enable      = 'off';  n.ID.Enable = 'off';
            n.Thk.Enable     = 'off';
        end

        function applyWasherSpec(obj, group)
            %APPLYWASHERSPEC  Resolve one group's family and drive its
            %   paired size dropdown. Unlike nuts, washersFor returns MANY
            %   matches, so this owns the size list too.
            %
            %   NEVER MARKS DIRTY.
            w = obj.washerGroup(group);
            if isempty(w.Spec) || ~obj.State.LibraryOK
                return
            end
            states = {'off', 'on'};
            w.Spec.Enable = states{w.Present.Value + 1};
            if ~w.Present.Value
                gui2.JointConfigPage.setItemsAndData(w.Size, ...
                    {gui2.JointConfigPage.WasherSizeNA}, {});
                w.Size.Value  = gui2.JointConfigPage.WasherSizeNA;
                w.Size.Enable = 'off';
                w.OD.Enable = 'off'; w.ID.Enable = 'off'; w.Thk.Enable = 'off';
                return
            end
            if strcmp(w.Spec.Value, 'Custom')
                gui2.JointConfigPage.setItemsAndData(w.Size, ...
                    {gui2.JointConfigPage.WasherSizeNA}, {});
                w.Size.Value  = gui2.JointConfigPage.WasherSizeNA;
                w.Size.Enable = 'off';
                w.OD.Enable = 'on'; w.ID.Enable = 'on'; w.Thk.Enable = 'on';
                return
            end
            matches = [];
            try
                bolt = obj.State.Library.bolt(string(obj.BoltDropDown.Value));
                matches = obj.State.Library.washersFor(bolt.NominalDiameter, ...
                    string(w.Spec.Value));
            catch
                matches = [];
            end
            if isempty(matches)
                spec = char(w.Spec.Value);
                w.Spec.Value = 'Custom';
                obj.setStatus(sprintf(['No %s washer matches bolt thread ' ...
                    '"%s" — washer spec reverted to Custom; enter the %s ' ...
                    'washer fields manually.'], spec, ...
                    char(obj.BoltDropDown.Value), lower(group)));
                obj.applyWasherSpec(group);   % Custom branch enables
                return
            end
            items     = cell(1, numel(matches));
            itemsData = cell(1, numel(matches));
            for k = 1:numel(matches)
                items{k}     = gui2.JointConfigPage.washerSizeLabel(matches(k));
                itemsData{k} = char(matches(k).Key);
            end
            prev = w.Size.Value;   % capture BEFORE Items changes under it
            gui2.JointConfigPage.setItemsAndData(w.Size, items, itemsData);
            if any(strcmp(itemsData, prev))
                w.Size.Value = prev;
            else
                w.Size.Value = itemsData{1};   % thinnest
            end
            w.Size.Enable = 'on';
            obj.fillWasherFromSize(group);
        end

        function fillWasherFromSize(obj, group)
            %FILLWASHERFROMSIZE  Fill + lock OD/ID/thickness from the
            %   selected size. Split out so a thickness switch within an
            %   already-resolved family need not re-resolve it.
            w = obj.washerGroup(group);
            key = w.Size.Value;
            if isempty(key) || strcmp(key, gui2.JointConfigPage.WasherSizeNA)
                return
            end
            try
                ws = obj.State.Library.washer(string(key));
            catch
                return
            end
            w.OD.Value  = gui2.JointConfigPage.fmtGeom(ws.OuterDiameter);
            w.ID.Value  = gui2.JointConfigPage.fmtGeom(ws.InnerDiameter);
            w.Thk.Value = ws.Thickness;
            w.OD.Enable = 'off'; w.ID.Enable = 'off'; w.Thk.Enable = 'off';
        end

        function w = washerGroup(obj, group)
            if strcmp(group, 'Head')
                w = obj.HeadWasher;
            else
                w = obj.NutWasher;
            end
        end

        % ---- Readouts -------------------------------------------------
        function onFlangeEdited(obj)
            %ONFLANGEEDITED  A thickness or Active toggle changes the grip,
            %   the length verdict, AND the required set — a row's material
            %   is required exactly while the row is in use.
            obj.updateGripLength();
            obj.updateBoltLengthLabel();
            obj.validateRequiredFields();
            obj.commitJoint();
        end

        function onLengthInputEdited(obj)
            obj.updateBoltLengthLabel()
            obj.commitJoint();
        end

        function updateGripLength(obj)
            %UPDATEGRIPLENGTH  Display model.Joint.GripLength. The model
            %   computes it; this prints it.
            if isempty(obj.GripLabel)
                return
            end
            try
                probe = model.Joint(FlangeStack = obj.collectFlangeLayers());
                obj.GripLabel.Text = sprintf('Grip length: %g in', probe.GripLength);
            catch
                obj.GripLabel.Text = 'Grip length: —';
            end
        end

        function updateBoltLengthLabel(obj)
            %UPDATEBOLTLENGTHLABEL  Four lines, three states, from
            %   engine.boltLengthCheck. ALL arithmetic is the engine's;
            %   this formats its struct.
            %
            %   The verdict keys off RequiredLength being NaN, never off an
            %   adequacy flag alone: while the engine cannot compute a
            %   required length it cannot evaluate ANY supplied length, and
            %   a short bolt must not render in the same muted style as an
            %   adequate one.
            if isempty(obj.BoltLengthLabel)
                return
            end
            try
                r = engine.boltLengthCheck(obj.probeJoint());
            catch
                % Bad typed input, library mismatch: never an error dialog
                % on an edit — but AMBER, not muted. The check is not
                % running, and that must not read as "adequate".
                obj.BoltLengthLabel.Text = {'Grip: —'; 'Engagement: —'; ...
                    'Min bolt: —'; 'Cannot check bolt length — fix the invalid input'};
                obj.BoltLengthLabel.FontColor  = gui2.palette('statusWarn');
                obj.BoltLengthLabel.FontWeight = 'normal';
                return
            end

            l1 = gui2.JointConfigPage.lineOrDash('Grip: %.4f in', r.GripLength, 'Grip: —');
            if ~isnan(r.Engagement) && ~isnan(r.ThreadAllowance)
                l2 = sprintf('Engagement %.4f + 2P %.4f in', r.Engagement, r.ThreadAllowance);
            elseif ~isnan(r.Engagement)
                l2 = sprintf('Engagement %.4f in', r.Engagement);
            else
                l2 = 'Engagement: —';
            end
            l3 = gui2.JointConfigPage.lineOrDash('Min bolt: %.4f in', ...
                r.RequiredLength, 'Min bolt: —');

            short       = r.Evaluated && r.Shortfall > 0;
            cannotCheck = isnan(r.RequiredLength);
            if cannotCheck
                l4 = ['Cannot check bolt length — ' obj.missingLengthInputs(r)];
            elseif isnan(r.SuppliedLength)
                l4 = 'Selected: — (blank = engine estimates)';
            elseif short
                l4 = sprintf('Selected: %.4f in TOO SHORT by %.4f in', ...
                    r.SuppliedLength, r.Shortfall);
            else
                l4 = sprintf('Selected: %.4f in OK', r.SuppliedLength);
            end
            obj.BoltLengthLabel.Text = {l1; l2; l3; l4};
            if short
                obj.BoltLengthLabel.FontColor  = gui2.palette('statusFail');
                obj.BoltLengthLabel.FontWeight = 'bold';
            elseif cannotCheck
                obj.BoltLengthLabel.FontColor  = gui2.palette('statusWarn');
                obj.BoltLengthLabel.FontWeight = 'normal';
            else
                obj.BoltLengthLabel.FontColor  = gui2.palette('mutedText');
                obj.BoltLengthLabel.FontWeight = 'normal';
            end
        end

        function s = missingLengthInputs(obj, r)
            %MISSINGLENGTHINPUTS  Name the missing inputs in the FORM's own
            %   words. The determination is the engine's; this maps its
            %   flags onto labels the analyst can see.
            parts = {};
            if isnan(r.GripLength)
                parts{end + 1} = 'a flange thickness (grip)';
            end
            t = obj.selectedMemberType();
            if string(r.EngagementBasis) == "unknown"
                switch t
                    case model.ThreadedMemberType.Nut
                        parts{end + 1} = 'engagement length (nut height)';
                    case model.ThreadedMemberType.Insert
                        parts{end + 1} = 'engagement Le (x bolt D)';
                    otherwise
                        parts{end + 1} = 'engagement length (tapped depth)';
                end
            end
            usesAllowance = t == model.ThreadedMemberType.Nut || ...
                            t == model.ThreadedMemberType.Insert;
            if usesAllowance && isnan(r.ThreadAllowance)
                parts{end + 1} = 'bolt thread pitch';
            end
            if isempty(parts)
                s = 'inputs incomplete';
            else
                s = ['enter ' strjoin(parts, ' and ')];
            end
        end

        % ---- Conditional fields ---------------------------------------
        function onSlipModeChanged(obj)
            obj.syncJointLoadVisibility()
            obj.commitJoint();
        end

        function syncJointLoadVisibility(obj)
            %SYNCJOINTLOADVISIBILITY  Section 7.3: the joint totals exist
            %   only for Eq. 84. Showing them for the single-fastener
            %   default is what made them confusing.
            if isempty(obj.JointLoadRows)
                return
            end
            show = false;
            try
                show = obj.selectedEnum('model.SlipMode', obj.SlipModeDropDown) == ...
                    model.SlipMode.Joint;
            catch
                show = false;
            end
            for k = 1:numel(obj.JointLoadRows)
                obj.JointLoadRows{k}.Visible = matlab.lang.OnOffSwitchState(show);
            end
        end

        % ---- Required-field validation --------------------------------
        function validateRequiredFields(obj)
            %VALIDATEREQUIREDFIELDS  Paint blank required dropdowns and gate
            %   Analyze with a tooltip naming what is missing, in the user's
            %   own labels. Runs on every relevant edit AND explicitly after
            %   every programmatic population — programmatic Value sets fire
            %   no callbacks.
            if isempty(obj.AnalyzeButton)
                return
            end
            if ~obj.State.LibraryOK
                obj.AnalyzeButton.Enable  = 'off';
                obj.AnalyzeButton.Tooltip = ['The hardware library is not ' ...
                    'loaded — analysis is unavailable.'];
                return
            end
            missing = obj.paintRequiredFields();
            if isempty(missing)
                obj.AnalyzeButton.Enable  = 'on';
                obj.AnalyzeButton.Tooltip = char(obj.AnalyzeDefaultTooltip);
            else
                obj.AnalyzeButton.Enable  = 'off';
                obj.AnalyzeButton.Tooltip = sprintf( ...
                    'Required fields missing: %s', strjoin(missing, ', '));
            end
        end

        function missing = paintRequiredFields(obj)
            %PAINTREQUIREDFIELDS  The required set:
            %     Bolt material    — always
            %     Member material  — always
            %     Flange layer i material — ONLY while the row is in use
            %       (Active AND thickness > 0, the same predicate that
            %       marshals the stack), so the set is conditional on the
            %       flange controls.
            missing  = {};
            normalBg = gui2.palette('fieldBg');
            blankBg  = gui2.palette('requiredBlankBg');

            dd = obj.BoltMaterialDropDown;
            if gui2.JointConfigPage.isBlank(dd)
                missing{end + 1} = 'Bolt material';
                dd.BackgroundColor = blankBg;
            else
                dd.BackgroundColor = normalBg;
            end

            for i = 1:numel(obj.FlangeMaterial)
                dd = obj.FlangeMaterial{i};
                if obj.flangeRowInUse(i) && gui2.JointConfigPage.isBlank(dd)
                    missing{end + 1} = sprintf('Flange layer %d material', i); %#ok<AGROW>
                    dd.BackgroundColor = blankBg;
                else
                    dd.BackgroundColor = normalBg;
                end
            end

            dd = obj.MemberMaterialDropDown;
            if gui2.JointConfigPage.isBlank(dd)
                missing{end + 1} = 'Member material';
                dd.BackgroundColor = blankBg;
            else
                dd.BackgroundColor = normalBg;
            end
        end

        function tf = flangeRowInUse(obj, i)
            t = obj.FlangeThickness{i}.Value
            tf = obj.FlangeActive{i}.Value && isfinite(t) && t > 0;
        end

        function assertRequiredSelections(obj)
            %ASSERTREQUIREDSELECTIONS  Belt and braces for marshalling.
            %   Analyze is already disabled while a required dropdown is
            %   blank; if one slips through, fail with the user-facing field
            %   label rather than letting the library throw about an
            %   internal key.
            problems = {};
            if gui2.JointConfigPage.isBlank(obj.BoltMaterialDropDown)
                problems{end + 1} = 'Bolt material is required — select one under "Bolt".';
            end
            for i = 1:numel(obj.FlangeMaterial)
                if obj.flangeRowInUse(i) && gui2.JointConfigPage.isBlank(obj.FlangeMaterial{i})
                    problems{end + 1} = sprintf(['Flange layer %d material is ' ...
                        'required — select one in the flange stack.'], i); %#ok<AGROW>
                end
            end
            if gui2.JointConfigPage.isBlank(obj.MemberMaterialDropDown)
                problems{end + 1} = ['Member material is required — select ' ...
                    'one under "Threaded member".'];
            end
            if ~isempty(problems)
                error('gui2:JointConfigPage:requiredFieldMissing', '%s', ...
                    strjoin(problems, newline));
            end
        end
    end

    % ---- Marshalling: controls <-> model ----------------------------------
    methods (Access = private)
        function joint = buildJoint(obj)
            %BUILDJOINT  model.Joint from the controls. Pure marshalling.
            obj.assertRequiredSelections();
            lib  = obj.State.Library;
            bolt = lib.bolt(string(obj.BoltDropDown.Value));
            % Overall length is joint-specific, so it comes from the form,
            % not the library entry (blank = NaN = engine estimates).
            bolt.Length = gui2.JointConfigPage.parseOptional( ...
                obj.BoltLengthField, 'Overall bolt length');

            memberType = obj.selectedMemberType();
            % Engagement: Insert -> ratio, everything else -> inches. ONE
            % control, never both properties from the same typed number.
            engVal = gui2.JointConfigPage.parseOptional( ...
                obj.EngagementField, 'Engagement length');
            if memberType == model.ThreadedMemberType.Insert
                engLength = NaN;  engRatio = engVal;
            else
                engLength = engVal;  engRatio = NaN;
            end
            % Insert only, catalogue-derived, never analyst-typed: the pitch
            % diameter at which the PARENT's internal thread shears. A miss
            % leaves NaN for the engine to report. Never substitute the
            % bolt's own pitch diameter.
            stiPitchDia = NaN;
            if memberType == model.ThreadedMemberType.Insert
                ins = lib.insertFor(bolt.NominalDiameter, bolt.ThreadsPerInch);
                if ~isempty(ins)
                    stiPitchDia = ins.StiPitchDiameterMin;
                end
            end
            member = model.ThreadedMember( ...
                Type             = memberType, ...
                Material         = lib.material(string(obj.MemberMaterialDropDown.Value)), ...
                EngagementLength = engLength, ...
                EngagementRatio  = engRatio, ...
                StiPitchDiameter = stiPitchDia);

            % Always torque control. NominalPreload, CreepLoss and
            % ThermalRate have no control — model defaults stand, so the
            % engine always computes thermal preload from CTE and stiffness
            % rather than an analyst override.
            spec = model.PreloadSpec( ...
                Method             = model.PreloadMethod.TorqueControl, ...
                NominalTorque      = gui2.JointConfigPage.parseOptional( ...
                                        obj.NominalTorqueField, 'Nominal torque'), ...
                TorqueTolerance    = obj.TorqueTolField.Value, ...
                NutFactor          = obj.NutFactorField.Value, ...
                Uncertainty        = obj.UncertaintyField.Value, ...
                RelaxationFraction = obj.RelaxationField.Value, ...
                SeparationCritical = logical(obj.SeparationCriticalCheck.Value));

            s = obj.State.Settings;
            joint = model.Joint( ...
                Name                  = string(obj.JointNameField.Value), ...
                Bolt                  = bolt, ...
                BoltMaterial          = lib.material(string(obj.BoltMaterialDropDown.Value)), ...
                FlangeStack           = obj.collectFlangeLayers(), ...
                ThreadedMember        = member, ...
                PreloadSpec           = spec, ...
                BoltCount             = obj.BoltCountField.Value, ...
                FrictionCoefficient   = obj.FrictionField.Value, ...
                LoadingPlaneFactor    = obj.LoadingPlaneField.Value, ...
                BoltRatedUltimateLoad = gui2.JointConfigPage.parseOptional( ...
                                            obj.RatedUltField, 'Bolt rated ultimate load'), ...
                BoltRatedYieldLoad    = gui2.JointConfigPage.parseOptional( ...
                                            obj.RatedYieldField, 'Bolt rated yield load'), ...
                ReferenceTemperature  = gui2.JointConfigPage.settingNum(s, 'NominalTempC'), ...
                MinTemperature        = gui2.JointConfigPage.settingNum(s, 'ColdTempC'), ...
                MaxTemperature        = gui2.JointConfigPage.settingNum(s, 'HotTempC'), ...
                ShearPlane            = obj.selectedEnum('model.ShearPlaneCondition', ...
                                            obj.ShearPlaneDropDown), ...
                ShearTransferCondition = model.ShearTransferCondition.NotDeclared, ...
                SlipMode              = obj.selectedEnum('model.SlipMode', ...
                                            obj.SlipModeDropDown), ...
                BoltAxis              = obj.selectedEnum('model.BoltAxis', ...
                                            obj.BoltAxisDropDown), ...
                FrustumAngle          = obj.FrustumAngleField.Value, ...
                HeadWasher            = obj.buildWasher('Head'), ...
                NutWasher             = obj.buildWasher('Nut'), ...
                BodyLengthInGrip      = gui2.JointConfigPage.parseOptional( ...
                                            obj.BodyLengthField, 'Body length in grip'));
        end

        function j = probeJoint(obj)
            %PROBEJOINT  A joint good enough for the live length readout,
            %   built WITHOUT the required-field assertion so the readout
            %   keeps working while the form is incomplete.
            %
            %   Resolves engagement the same way buildJoint will, or an inch
            %   value typed in Insert mode would be read as inches here and
            %   as a ratio later.
            bolt = model.Bolt();
            if obj.State.LibraryOK
                bolt = obj.State.Library.bolt(string(obj.BoltDropDown.Value));
            end
            bolt.Length = gui2.JointConfigPage.parseOptional( ...
                obj.BoltLengthField, 'Overall bolt length');
            t = obj.selectedMemberType();
            engVal = gui2.JointConfigPage.parseOptional( ...
                obj.EngagementField, 'Engagement length');
            if t == model.ThreadedMemberType.Insert
                member = model.ThreadedMember(Type = t, EngagementRatio = engVal);
            else
                member = model.ThreadedMember(Type = t, EngagementLength = engVal);
            end
            j = model.Joint( ...
                Bolt           = bolt, ...
                FlangeStack    = obj.collectFlangeLayers(), ...
                ThreadedMember = member, ...
                HeadWasher     = obj.buildWasher('Head'), ...
                NutWasher      = obj.buildWasher('Nut'));
        end

        function layers = collectFlangeLayers(obj)
            %COLLECTFLANGELAYERS  Rows in use, in order. An unchecked row is
            %   excluded entirely — non-destructively, its values are kept.
            layers = model.FlangeLayer.empty(1, 0);
            if ~obj.State.LibraryOK
                return
            end
            for i = 1:numel(obj.FlangeThickness)
                if ~obj.flangeRowInUse(i)
                    continue
                end
                if gui2.JointConfigPage.isBlank(obj.FlangeMaterial{i})
                    continue   % required-field validation reports it
                end
                layers(end + 1) = model.FlangeLayer( ...
                    Material          = obj.State.Library.material( ...
                                            string(obj.FlangeMaterial{i}.Value)), ...
                    Name              = string(obj.FlangeName{i}.Value), ...
                    Thickness         = obj.FlangeThickness{i}.Value, ...
                    HoleDiameter      = gui2.JointConfigPage.parseOptional( ...
                                            obj.FlangeHole{i}, ...
                                            sprintf('Flange layer %d hole diameter', i)), ...
                    EdgeDistance      = gui2.JointConfigPage.parseOptional( ...
                                            obj.FlangeEdge{i}, ...
                                            sprintf('Flange layer %d edge distance', i)), ...
                    CheckShearTearout = logical(obj.FlangeTearout{i}.Value)); %#ok<AGROW>
            end
        end

        function w = buildWasher(obj, group)
            %BUILDWASHER  model.Washer from one group. Present unchecked ->
            %   the model default ("no washer"), NOT zeros typed by a user.
            g = obj.washerGroup(group);
            w = model.Washer();
            if isempty(g) || ~g.Present.Value
                return
            end
            w.Thickness     = g.Thk.Value;
            w.OuterDiameter = gui2.JointConfigPage.parseOptional(g.OD, ...
                [group ' washer outer diameter']);
            w.InnerDiameter = gui2.JointConfigPage.parseOptional(g.ID, ...
                [group ' washer inner diameter']);
            if obj.State.LibraryOK && ~gui2.JointConfigPage.isBlank(g.Material)
                w.Material = obj.State.Library.material(string(g.Material.Value));
            end
        end

        function lc = buildLoadCase(obj)
            lc = model.LoadCase( ...
                Name                  = string(obj.CaseNameField.Value), ...
                BoltTensileLimitLoad  = gui2.JointConfigPage.parseOptional( ...
                                            obj.BoltTensileField, 'Bolt tensile limit load'), ...
                BoltShearLimitLoad    = gui2.JointConfigPage.parseOptional( ...
                                            obj.BoltShearField, 'Bolt shear limit load'), ...
                JointTensileLimitLoad = gui2.JointConfigPage.parseOptional( ...
                                            obj.JointTensileField, 'Joint tensile limit load'), ...
                JointShearLimitLoad   = gui2.JointConfigPage.parseOptional( ...
                                            obj.JointShearField, 'Joint shear limit load'))
            
        end

        function commitJoint(obj)
            %COMMITJOINT  Controls -> AppState.Joint. Best-effort: an
            %   incomplete form is the normal state while typing, so a
            %   marshalling failure is silent here. Analyze reports it
            %   properly.
            %
            %   SUPPRESSES ITS OWN REFRESH. Assigning State.Joint fires
            %   JointChanged, which this page listens to. Letting that come
            %   back would repopulate every control from the joint just
            %   marshalled — and marshalling is LOSSY by design: a flange
            %   row that is Active with zero thickness is not in the stack,
            %   so the round trip would un-tick it under an analyst who was
            %   about to type a thickness. The controls are already the
            %   truth here; only an EXTERNAL change (File > Open) needs to
            %   be read back.
            if obj.Refreshing
                return
            end
            obj.Refreshing = true;
            c = onCleanup(@() obj.clearRefreshing()); %#ok<NASGU>
            try
                obj.State.Joint = obj.buildJoint();
            catch
                % Nothing to report mid-edit.
            end
        end

        function commitLoadCase(obj)
            %COMMITLOADCASE  Controls -> AppState.LoadCase, suppressing the
            %   echo for the same reason as commitJoint.
            if obj.Refreshing
                return
            end
            obj.Refreshing = true;
            c = onCleanup(@() obj.clearRefreshing()); %#ok<NASGU>
            try
                obj.State.LoadCase = obj.buildLoadCase();
            catch
                % Nothing to report mid-edit.
            end
        end

        function clearRefreshing(obj)
            obj.Refreshing = false;
        end

        function applyJoint(obj, j)
            %APPLYJOINT  model.Joint -> controls. Programmatic sets fire no
            %   callbacks, so every derived state is re-synced explicitly
            %   afterward.
            obj.JointNameField.Value = char(j.Name);
            obj.trySelect(obj.BoltDropDown, j.Bolt.Designation);
            obj.trySelect(obj.BoltMaterialDropDown, j.BoltMaterial.Name);
            obj.BoltCountField.Value = j.BoltCount;
            obj.BoltLengthField.Value = gui2.JointConfigPage.fmtOptional(j.Bolt.Length);
            obj.BodyLengthField.Value = gui2.JointConfigPage.fmtOptional(j.BodyLengthInGrip);
            obj.RatedUltField.Value   = gui2.JointConfigPage.fmtOptional(j.BoltRatedUltimateLoad);
            obj.RatedYieldField.Value = gui2.JointConfigPage.fmtOptional(j.BoltRatedYieldLoad);
            obj.FrustumAngleField.Value = j.FrustumAngle;

            obj.applyFlangeStack(j.FlangeStack);
            obj.applyWasher('Head', j.HeadWasher);
            obj.applyWasher('Nut',  j.NutWasher);

            obj.MemberTypeDropDown.Value = ...
                gui2.JointConfigPage.memberTypeLabel(j.ThreadedMember.Type);
            obj.trySelect(obj.MemberMaterialDropDown, j.ThreadedMember.Material.Name);
            % Seed from whichever property this type actually uses — the
            % same split buildJoint marshals by.
            if j.ThreadedMember.Type == model.ThreadedMemberType.Insert
                engSeed = j.ThreadedMember.EngagementRatio;
            else
                engSeed = j.ThreadedMember.EngagementLength;
            end
            obj.EngagementField.Value = gui2.JointConfigPage.fmtOptional(engSeed);

            ps = j.PreloadSpec;
            obj.NominalTorqueField.Value = gui2.JointConfigPage.fmtOptional(ps.NominalTorque);
            obj.TorqueTolField.Value     = ps.TorqueTolerance;
            obj.NutFactorField.Value     = ps.NutFactor;
            obj.UncertaintyField.Value   = ps.Uncertainty;
            obj.RelaxationField.Value    = ps.RelaxationFraction;
            obj.SeparationCriticalCheck.Value = logical(ps.SeparationCritical);

            obj.ShearPlaneDropDown.Value = char(string(j.ShearPlane));
            obj.SlipModeDropDown.Value   = char(string(j.SlipMode));
            obj.BoltAxisDropDown.Value   = char(string(j.BoltAxis));
            obj.FrictionField.Value      = j.FrictionCoefficient;
            obj.LoadingPlaneField.Value  = j.LoadingPlaneFactor;

            % Re-sync everything derived. updateSpecFields(false) keeps the
            % loaded case's stored rated loads rather than overwriting them
            % with the library's.
            obj.updateSpecFields(false);
            obj.updateMemberMaterialLabel();
            obj.updateEngagementFieldMode();
            obj.applyNutSpec();
            obj.refreshWasherState();
            obj.syncJointLoadVisibility();
            obj.updateGripLength();
            obj.updateBoltLengthLabel();
            obj.validateRequiredFields();
        end

        function applyFlangeStack(obj, stack)
            for i = 1:numel(obj.FlangeThickness)
                if i <= numel(stack)
                    L = stack(i);
                    obj.FlangeActive{i}.Value    = true;
                    obj.FlangeName{i}.Value      = char(L.Name);
                    obj.trySelect(obj.FlangeMaterial{i}, L.Material.Name);
                    obj.FlangeThickness{i}.Value = L.Thickness;
                    obj.FlangeHole{i}.Value      = gui2.JointConfigPage.fmtGeom(L.HoleDiameter);
                    obj.FlangeEdge{i}.Value      = gui2.JointConfigPage.fmtGeom(L.EdgeDistance);
                    obj.FlangeTearout{i}.Value   = logical(L.CheckShearTearout);
                else
                    obj.FlangeActive{i}.Value    = false;
                    obj.FlangeThickness{i}.Value = 0;
                end
            end
        end

        function applyWasher(obj, group, w)
            g = obj.washerGroup(group);
            g.Present.Value = gui2.JointConfigPage.washerPresent(w);
            g.Thk.Value     = w.Thickness;
            g.OD.Value      = gui2.JointConfigPage.fmtGeom(w.OuterDiameter);
            g.ID.Value      = gui2.JointConfigPage.fmtGeom(w.InnerDiameter);
            obj.trySelect(g.Material, w.Material.Name);
        end

        function applyLoadCase(obj, lc)
            obj.CaseNameField.Value     = char(lc.Name);
            obj.BoltTensileField.Value  = gui2.JointConfigPage.fmtOptional(lc.BoltTensileLimitLoad);
            obj.BoltShearField.Value    = gui2.JointConfigPage.fmtOptional(lc.BoltShearLimitLoad);
            obj.JointTensileField.Value = gui2.JointConfigPage.fmtOptional(lc.JointTensileLimitLoad);
            obj.JointShearField.Value   = gui2.JointConfigPage.fmtOptional(lc.JointShearLimitLoad);
        end
    end

    % ---- Actions -----------------------------------------------------------
    methods (Access = private)
        function onAnalyze(obj)
            %ONANALYZE  Marshal -> engine.analyze -> AppState.Result.
            %   Does NOT render results; the Results page owns that and
            %   reads AppState.
            try
                joint    = obj.buildJoint();
                loadCase = obj.buildLoadCase();
                result   = engine.analyze(joint, loadCase, obj.State.Factors);
            catch err
                uialert(obj.figureHandle(), err.message, 'Analysis failed');
                % Any result on screen predates this failed run — stale it
                % rather than leave a confident verdict up (A3).
                obj.State.markResultStale();
                return
            end
            obj.State.setResult(result);
            obj.setStatus(sprintf('Analyzed "%s" — %d checks returned.', ...
                char(joint.Name), numel(result.Margins)));
        end

        function onSaveToDefinedJoints(obj)
            %ONSAVETODEFINEDJOINTS  Store the current joint under its name.
            %   Overwriting asks first and preserves the fields this page
            %   has no controls for.
            try
                j = obj.buildJoint();
            catch err
                uialert(obj.figureHandle(), err.message, 'Cannot save joint');
                return
            end
            nm = strtrim(j.Name);
            if strlength(nm) == 0
                uialert(obj.figureHandle(), ['Joint name is required — enter ' ...
                    'one at the top of Joint Config, then save again.'], ...
                    'Cannot save joint');
                return
            end
            j.Name = nm;
            lib = obj.State.JointLibrary;
            % Case-insensitive: letting "JT-A" and "jt-a" coexist is a
            % mapping trap (A13).
            idx = find(strcmpi({lib.Name}, nm), 1);
            if ~isempty(idx)
                choice = uiconfirm(obj.figureHandle(), sprintf(['A joint named ' ...
                    '"%s" is already in the library. Overwrite it with the ' ...
                    'current Joint Config values?'], lib(idx).Name), ...
                    'Overwrite joint', 'Options', {'Overwrite', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, 'Overwrite')
                    return
                end
                j = gui2.JointConfigPage.preserveUneditedFields(j, lib(idx).Joint);
                lib(idx).Name  = nm;
                lib(idx).Joint = j;
                verb = 'Updated';
            else
                lib(end + 1) = struct('Name', nm, 'Joint', j);
                verb = 'Added';
            end
            obj.State.JointLibrary = lib;   % fires JointLibraryChanged
            obj.State.markDirty();
            obj.setStatus(sprintf('%s joint "%s" in the defined joints library.', ...
                verb, nm));
        end

        function fig = figureHandle(obj)
            fig = ancestor(obj.Root, 'figure');
        end

        function installAnalyzeShortcut(obj)
            %INSTALLANALYZESHORTCUT  F5 runs Analyze (GUI2_SPEC.md Section 4).
            %   GUI_PORT_SPEC.md Section 11 claimed the first build had this;
            %   it never did, so there was nothing to port.
            %
            %   The handler is figure-level because that is the only place
            %   MATLAB delivers key presses, but it GUARDS ON THIS PAGE
            %   BEING VISIBLE: Analyze is meaningless from Element Forces,
            %   and a global shortcut that fires from anywhere would run a
            %   marshal the user never asked for.
            %
            %   A page reaching for the figure is a wart. It is here because
            %   the shell has no key-dispatch mechanism and inventing one
            %   for a single shortcut would be speculative. If a second page
            %   ever wants a key, that dispatch belongs in gui2.FastenerApp
            %   and this moves to it.
            fig = obj.figureHandle();
            if isempty(fig) || ~isvalid(fig)
                return
            end
            fig.KeyPressFcn = @(~, evt) obj.onFigureKey(evt);
        end

        function onFigureKey(obj, evt)
            if ~strcmp(evt.Key, 'f5')
                return
            end
            if isempty(obj.Root) || ~isvalid(obj.Root) || ~obj.Root.Visible
                return   % another page is showing
            end
            if ~strcmp(obj.AnalyzeButton.Enable, 'on')
                return   % required fields missing; the button already says so
            end
            obj.onAnalyze();
        end
    end

    % ---- Small helpers -----------------------------------------------------
    methods (Access = private)
        function b = addGroup(obj, parent, row, titleText, expanded)
            %ADDGROUP  A collapsible section. Returns the body grid.
            %   The header is a state button, the body a panel whose row
            %   height toggles between 'fit' and 0.
            %
            %   DEVIATION FROM GUI2_SPEC.md 7.5, deliberately: the body is
            %   BUILT EAGERLY and only its visibility toggles. 7.5 asks for
            %   collapsed groups to stay unbuilt, for render cost. But
            %   buildJoint reads EVERY control to marshal a model.Joint, so
            %   a control that does not exist is a marshalling failure, not
            %   a saving. Correctness beats the first paint here; the
            %   collapse still shrinks the page an analyst has to scan.
            % Both rows set explicitly. A grid's default row height is
            % '1x', which would stretch the first group's header to fill
            % the column.
            h = parent.RowHeight;
            while numel(h) < row + 1
                h{end + 1} = 'fit'; %#ok<AGROW>
            end
            h{row}     = 'fit';   % header button
            h{row + 1} = 'fit';   % body, until applyGroupState collapses it
            parent.RowHeight = h;

            btn = uibutton(parent, 'state', 'Value', expanded, ...
                'HorizontalAlignment', 'left', 'FontWeight', 'bold');
            btn.Layout.Row    = row;
            btn.Layout.Column = 1;
            btn.Text = gui2.JointConfigPage.groupCaption(titleText, expanded);

            panel = uipanel(parent, 'BorderType', 'line');
            panel.Layout.Row    = row + 1;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [8 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = repmat({'fit'}, 1, 8);
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            k = numel(obj.Groups) + 1;
            obj.Groups(k) = struct('Button', btn, 'Body', panel, ...
                'Grid', parent, 'Row', row + 1, 'Title', string(titleText));
            btn.ValueChangedFcn = @(~, ~) obj.toggleGroup(k);
            obj.applyGroupState(k);
        end

        function toggleGroup(obj, k)
            %TOGGLEGROUP  Collapse is a DISPLAY action — never marks dirty.
            obj.applyGroupState(k);
        end

        function applyGroupState(obj, k)
            g = obj.Groups(k);
            open = logical(g.Button.Value);
            g.Button.Text = gui2.JointConfigPage.groupCaption(g.Title, open);
            g.Body.Visible = matlab.lang.OnOffSwitchState(open);
            h = g.Grid.RowHeight;
            if open
                h{g.Row} = 'fit';
            else
                h{g.Row} = 0;
            end
            g.Grid.RowHeight = h;
        end

        function [c, lb] = addTextRow(obj, g, row, labelText, ~, tip)
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            c = uieditfield(g, 'text');
            c.Layout.Row = row; c.Layout.Column = 2;
            if strlength(string(tip)) > 0
                c.Tooltip = tip; lb.Tooltip = tip;
            end
        end

        function [c, lb] = addNumericRow(obj, g, row, labelText, tip)
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            c = uieditfield(g, 'numeric');
            c.Layout.Row = row; c.Layout.Column = 2;
            if strlength(string(tip)) > 0
                c.Tooltip = tip; lb.Tooltip = tip;
            end
        end

        function [c, lb] = addDropdownRow(obj, g, row, labelText, items, tip)
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            c = uidropdown(g, 'Items', items);
            c.Layout.Row = row; c.Layout.Column = [2 3];
            if strlength(string(tip)) > 0
                c.Tooltip = tip; lb.Tooltip = tip;
            end
        end

        function items = boltItems(obj)
            items = {' '};
            if obj.State.LibraryOK
                keys = obj.State.Library.boltKeys();
                if ~isempty(keys)
                    items = reshape(cellstr(keys), 1, []);
                end
            end
        end

        function items = materialItems(obj, role)
            %MATERIALITEMS  Blank sentinel FIRST, then the keys (A6). A
            %   deleted material falls back to BLANK, never to whatever is
            %   now first in the list.
            keys = strings(1, 0);
            if obj.State.LibraryOK
                try
                    if nargin > 1
                        keys = obj.State.Library.materialKeys(Role = role);
                    else
                        keys = obj.State.Library.materialKeys();
                    end
                catch
                    keys = strings(1, 0);
                end
            end
            items = [{gui2.JointConfigPage.BlankChoice}, reshape(cellstr(keys), 1, [])];
        end

        function items = enumItems(~, enumClass)
            members = enumeration(enumClass)
            items = cellstr(string(members(:)'));
        end

        function m = selectedEnum(~, enumClass, dd)
            members = enumeration(enumClass);
            idx = find(string(members) == string(dd.Value), 1);
            if isempty(idx)
                error('gui2:JointConfigPage:unknownEnum', ...
                    'Unknown %s member "%s".', enumClass, char(string(dd.Value)));
            end
            m = members(idx);
        end

        function t = selectedMemberType(obj)
            t = gui2.JointConfigPage.memberTypeFromLabel(obj.MemberTypeDropDown.Value);
        end

        function ok = trySelect(~, dd, key)
            %TRYSELECT  Select a key if the dropdown offers it. Returns
            %   false on a miss WITHOUT changing the selection — every
            %   caller must handle that, because silently keeping the
            %   previous value is how a stale entry ends up locked and
            %   looking authoritative.
            k = char(string(key));
            ok = ~isempty(k) && any(strcmp(dd.Items, k));
            if ok
                dd.Value = k;
            end
        end

        function refreshLibraryDropdowns(obj)
            %REFRESHLIBRARYDROPDOWNS  Repopulate every library-backed
            %   dropdown, preserving the current selection where it still
            %   exists. Programmatic sets fire no callbacks, so the
            %   required-field check is re-run explicitly.
            if ~obj.IsBuilt
                return
            end
            gui2.JointConfigPage.repopulate(obj.BoltDropDown, obj.boltItems());
            gui2.JointConfigPage.repopulate(obj.BoltMaterialDropDown, obj.materialItems('bolt'));
            gui2.JointConfigPage.repopulate(obj.MemberMaterialDropDown, obj.materialItems());
            for i = 1:numel(obj.FlangeMaterial)
                gui2.JointConfigPage.repopulate(obj.FlangeMaterial{i}, obj.materialItems());
            end
            for g = [obj.HeadWasher, obj.NutWasher]
                gui2.JointConfigPage.repopulate(g.Material, obj.materialItems('washer'));
            end
            obj.populateSpecPickers();
            obj.validateRequiredFields();
        end

        function populateSpecPickers(obj)
            %POPULATESPECPICKERS  Nut and washer family lists. Items carry
            %   "<token> - <name>" for the analyst; ItemsData carries the
            %   bare token, so Value is never a composite string that has to
            %   round-trip.
            if ~obj.State.LibraryOK
                return
            end
            try
                [tok, lab] = obj.State.Library.nutSpecs();
                gui2.JointConfigPage.setItemsAndData(obj.NutSpecDropDown, ...
                    [cellstr(lab), {'Custom'}], [cellstr(tok), {'Custom'}]);
                obj.NutSpecDropDown.Value = 'Custom';
            catch
            end
            try
                [wtok, wlab] = obj.State.Library.washerSpecs();
                for g = [obj.HeadWasher, obj.NutWasher]
                    gui2.JointConfigPage.setItemsAndData(g.Spec, ...
                        [cellstr(wlab), {'Custom'}], [cellstr(wtok), {'Custom'}]);
                    g.Spec.Value = 'Custom';
                end
            catch
            end
        end
    end

    % ---- Static helpers ----------------------------------------------------
    methods (Static, Access = private)
        function setItemsAndData(dd, items, itemsData)
            %SETITEMSANDDATA  Replace Items and ItemsData together.
            %   Lists change LENGTH between families, and a bare Items
            %   assignment throws while the old ItemsData pairing is still
            %   attached. Clearing ItemsData first is the only safe order.
            dd.ItemsData = {};
            dd.Items     = items;
            if ~isempty(itemsData)
                dd.ItemsData = itemsData;
            end
        end

        function repopulate(dd, items)
            prev = dd.Value;
            dd.Items = items;
            if any(strcmp(items, prev))
                dd.Value = prev;
            else
                dd.Value = items{1};   % the blank sentinel, by construction
            end
        end

        function s = groupCaption(titleText, open)
            if open
                s = ['v  ' char(titleText)];
            else
                s = ['>  ' char(titleText)];
            end
        end

        function v = parseOptional(field, label)
            %PARSEOPTIONAL  Blank (or "NaN") -> NaN, the model's documented
            %   "automatic / not set" sentinel. A non-blank non-numeric
            %   entry is a typo: error clearly rather than silently treating
            %   it as automatic.
            txt = strtrim(char(field.Value));
            if isempty(txt) || strcmpi(txt, 'nan')
                v = NaN;
                return
            end
            v = str2double(txt);
            if isnan(v)
                error('gui2:JointConfigPage:badNumber', ...
                    '%s: "%s" is not a number. Enter a value or leave blank for automatic.', ...
                    label, txt);
            end
        end

        function s = fmtOptional(v)
            if isnan(v)
                s = '';
            else
                s = sprintf('%g', v);
            end
        end


        function s = fmtGeom(v)
            if isnan(v)
                s = '';
            else
                s = sprintf('%.5f', v);
            end
        end


        function s = lineOrDash(fmt, v, dash)
            if isnan(v)
                s = dash;
            else
                s = sprintf(fmt, v);
            end
        end


        function tf = isBlank(dd)
            %ISBLANK  True on the blank sentinel. Trim before testing;
            %   never strcmp against '' (A6).
            tf = strlength(strtrim(string(dd.Value))) == 0;
        end

        function tf = washerPresent(w)
            %WASHERPRESENT  The model has no Present flag: a default washer
            %   (zero thickness, NaN diameters) means "no washer".
            tf = w.Thickness > 0 || ~isnan(w.OuterDiameter) || ~isnan(w.InnerDiameter);
        end

        function s = washerSizeLabel(w)
            thk = sprintf('%.3f', w.Thickness)
            s = sprintf('%s - %s thk', char(w.Key), thk(2:end));
        end

        function items = memberTypeItems()
            members = enumeration('model.ThreadedMemberType');
            items = cell(1, numel(members));
            for i = 1:numel(members)
                items{i} = gui2.JointConfigPage.memberTypeLabel(members(i));
            end
        end

        function s = memberTypeLabel(t)
            %MEMBERTYPELABEL  Enum -> display label. Display only; the enum
            %   member names are untouched.
            if t == model.ThreadedMemberType.Insert
                s = 'Helical Insert';
            elseif t == model.ThreadedMemberType.TappedHole
                s = 'Tapped Hole';
            else
                s = char(string(t));
            end
        end

        function t = memberTypeFromLabel(txt)
            %MEMBERTYPEFROMLABEL  Label -> enum, the inverse of the above.
            %   Resolved through the ENUMERATION, never by string equality
            %   against a member name: GUI2_HARVEST.md C1 is a bug that came
            %   from a comparison against 'TappedHole' that could never
            %   match, so the member silently behaved as bolt-only.
            normalized = strtrim(char(string(txt)));
            if strcmp(normalized, 'Helical Insert')
                t = model.ThreadedMemberType.Insert;
                return
            end
            if strcmp(normalized, 'Tapped Hole')
                t = model.ThreadedMemberType.TappedHole;
                return
            end
            members = enumeration('model.ThreadedMemberType');
            idx = find(string(members) == string(normalized), 1);
            if isempty(idx)
                error('gui2:JointConfigPage:unknownMemberType', ...
                    'Unknown threaded member type "%s".', normalized);
            end
            t = members(idx);
        end

        function v = settingNum(st, name)
            %SETTINGNUM  One numeric Settings field, or NaN. Tolerant: an
            %   older case file can be missing one, and marshalling must
            %   degrade rather than throw.
            if isstruct(st) && isfield(st, name)
                v = double(st.(name));
            else
                v = NaN;
            end
        end

        function j = preserveUneditedFields(j, old)
            %PRESERVEUNEDITEDFIELDS  Carry over what this page has no
            %   control for, so an overwrite does not silently reset it.
            %   Pure copying; nothing is computed.
            %
            %   Host name carries over ONLY when the member type is
            %   unchanged — a type change makes the old detail stale.
            %
            %   Two fields are deliberately NOT copied. The insert pitch
            %   diameter is re-resolved from the current bolt on every
            %   marshal. The shear engagement area is never analyst-supplied
            %   at all (NASA-STD-5020B 4.4.1 wants a rated load or specified
            %   catalogue geometry, not a typed area), so copying a stale
            %   value would reintroduce the override the field no longer
            %   accepts.
            if j.ThreadedMember.Type == old.ThreadedMember.Type
                j.ThreadedMember.HostName = old.ThreadedMember.HostName;
            end
            for i = 1:min(numel(j.FlangeStack), numel(old.FlangeStack))
                j.FlangeStack(i).Name = old.FlangeStack(i).Name;
            end
            j.PreloadSpec.CreepLoss   = old.PreloadSpec.CreepLoss;
            j.PreloadSpec.ThermalRate = old.PreloadSpec.ThermalRate;
        end
    end

    % ---- Test seams --------------------------------------------------------
    %   Public getters returning real handles, so tests drive gestures
    %   rather than poking private state.
    methods
        function f = jointNameField(obj)
            f = obj.JointNameField;
        end
        function d = boltDropDown(obj)
            d = obj.BoltDropDown;
        end
        function d = boltMaterialDropDown(obj)
            d = obj.BoltMaterialDropDown;
        end
        function f = ratedUltField(obj)
            f = obj.RatedUltField;
        end
        function f = ratedYieldField(obj)
            f = obj.RatedYieldField;
        end
        function c = ratedOverrideCheck(obj)
            c = obj.RatedOverrideCheck;
        end
        function d = memberTypeDropDown(obj)
            d = obj.MemberTypeDropDown;
        end
        function d = memberMaterialDropDown(obj)
            d = obj.MemberMaterialDropDown;
        end
        function l = memberMaterialLabel(obj)
            l = obj.MemberMaterialLabel;
        end
        function d = nutSpecDropDown(obj)
            d = obj.NutSpecDropDown;
        end
        function f = engagementField(obj)
            f = obj.EngagementField;
        end
        function l = engagementLabel(obj)
            l = obj.EngagementFieldLabel;
        end
        function c = sameAsHeadCheck(obj)
            c = obj.NutWasherSameAsHeadCheck;
        end
        function w = headWasher(obj)
            w = obj.HeadWasher;
        end
        function w = nutWasher(obj)
            w = obj.NutWasher;
        end
        function d = slipModeDropDown(obj)
            d = obj.SlipModeDropDown;
        end
        function f = jointTensileField(obj)
            f = obj.JointTensileField;
        end
        function f = jointShearField(obj)
            f = obj.JointShearField;
        end
        function b = analyzeButton(obj)
            b = obj.AnalyzeButton;
        end
        function b = saveJointButton(obj)
            b = obj.SaveJointButton;
        end
        function l = boltLengthLabel(obj)
            l = obj.BoltLengthLabel;
        end
        function l = gripLabel(obj)
            l = obj.GripLabel;
        end
        function c = flangeActive(obj, i)
            c = obj.FlangeActive{i};
        end
        function d = flangeMaterial(obj, i)
            d = obj.FlangeMaterial{i};
        end
        function f = flangeThickness(obj, i)
            f = obj.FlangeThickness{i};
        end
        function f = boltCountField(obj)
            f = obj.BoltCountField;
        end
        function f = boltLengthField(obj)
            f = obj.BoltLengthField;
        end
        function f = bodyLengthField(obj)
            f = obj.BodyLengthField;
        end
        function f = caseNameField(obj)
            f = obj.CaseNameField;
        end
        function f = boltTensileField(obj)
            f = obj.BoltTensileField;
        end
        function f = boltShearField(obj)
            f = obj.BoltShearField;
        end
        function g = groupButtons(obj)
            g = obj.Groups;
        end
    end
end
