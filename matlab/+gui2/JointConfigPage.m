classdef JointConfigPage < gui2.Page
    %JOINTCONFIGPAGE  Define one joint and its limit loads (GUI2_SPEC.md 3).
    %   Rebuilt in verified increments after the first attempt was reverted:
    %   one 2,276-line pass produced a page that could only be checked by
    %   watching a failure count move. Each increment here ends with the
    %   suite green before the next begins.
    %
    %   BUILT SO FAR: the page shell, Identity + Bolt, both washers, the
    %   flange stack with its grip readout, and the threaded member - laid
    %   out in PHYSICAL STACK ORDER, which is what the page's own banner
    %   promises. Later: the right column, the actions, and last and alone,
    %   the library auto-fill cascades.
    %
    %   BUILDJOINT IS TOTAL — it always returns a model.Joint and never
    %   throws. This is the design decision the first attempt got wrong. It
    %   asserted every required selection up front, so on an incomplete form
    %   NO commit succeeded: AppState.Joint stayed at its blank default,
    %   File > Save wrote that blank, and any repopulation from state wiped
    %   what the analyst had typed. An incomplete form is the NORMAL state
    %   while working, so marshalling has to tolerate it. Required-field
    %   enforcement belongs on the Analyze path alone, where the answer
    %   actually has to be trustworthy.
    %
    %   Backed by AppState.Joint; every edit fires JointChanged.

    properties (Constant, Access = private)
        % Blank sentinel for a required dropdown (A6). A space, not '', so
        % it is a selectable item rather than an absent value.
        BlankChoice = ' '

        % The manual escape from every spec picker. PERMANENT and always
        % reachable (A5): a user must never be left with fields locked and
        % no way back. A bare token, not a label, because it is also the
        % ItemsData value.
        CustomChoice = 'Custom'

        % Shown by a size picker with nothing to offer - no family chosen,
        % or no bolt to resolve against. Named rather than blank, so the
        % absence reads as a state instead of a rendering fault (A12).
        SizeNA = '(none - pick a family)'

        LabelW = 150
        ValueW = 150

        % The right column's value controls. Narrower than the left's
        % because it holds single numbers - a torque, a fraction, an axis -
        % where the left holds geometry and library keys. A box sized for a
        % catalogue designation reads as though it wants more than 0.25.
        ValueWRight = 120

        MaxFlangeLayers = 4
    end

    properties (Access = private)
        JointNameField
        BoltDropDown
        BoltMaterialDropDown
        BoltCountField

        % Flange stack, one cell per layer row.
        FlangeName
        FlangeMaterial
        FlangeThickness
        FlangeHole
        FlangeEdge
        FlangeTearout
        GripLabel

        % Washer groups. Each is a struct of handles from buildWasherGroup,
        % so both carry identical fields in identical order.
        HeadWasher
        NutWasher
        SameAsHeadCheck

        BoltLengthField
        BoltLengthLabel

        BodyLengthField
        RatedUltField
        RatedYieldField
        FrustumAngleField

        % Right column
        NominalTorqueField
        TorqueTolField
        NutFactorField
        UncertaintyField
        RelaxationField
        SeparationCriticalCheck

        CaseNameField
        BoltTensileField
        BoltShearField
        JointTensileField
        JointShearField
        JointTensileLabel
        JointShearLabel

        ShearPlaneDropDown
        SlipModeDropDown
        FrictionField
        BoltAxisDropDown
        LoadingPlaneField

        AnalyzeButton
        SaveJointButton
        RequiredLabel

        MemberTypeDropDown
        MemberMaterialDropDown
        MemberMaterialLabel
        EngagementRatioField
        EngagementRatioLabel
        EngagementLengthField
        EngagementLengthLabel

        NutSpecDropDown

        % True while a RESOLVED nut family owns the member material and the
        % inches engagement. Read by syncMemberType, which is the ONE method
        % that sets either engagement control's Enable - the nut cascade
        % feeds it this flag rather than writing Enable behind its back.
        % Two writers over one property is how a field ends up editable
        % when it should be locked (A5).
        NutSpecLocked (1,1) logical = false

        % Guards a commit against the refresh its own event triggers.
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
            % 2/3 : 1/3. The left column carries the physical stack - seven
            % groups including the seven-column flange grid - against four
            % narrower ones on the right.
            g = uigridlayout(parent, [2 2]);
            g.RowHeight     = {'fit', 'fit'};
            g.ColumnWidth   = {'2x', '1x'};
            g.Padding       = [8 8 8 8];
            g.RowSpacing    = 8;
            g.ColumnSpacing = 10;
            g.Scrollable    = 'on';

            obj.addBanner(g, 1, [1 2], ...
                ['Define one joint and its limit loads, then Analyze. The ' ...
                 'left column follows the physical stack, top to bottom. ' ...
                 'Factors and service temperatures are global — they live ' ...
                 'on their own pages and are shown in the bar at the bottom ' ...
                 'of the window.']);

            left = uigridlayout(g, [1 1]);
            left.Layout.Row    = 2;
            left.Layout.Column = 1;
            left.ColumnWidth   = {'1x'};
            left.RowHeight     = repmat({'fit'}, 1, 7);
            left.Padding       = [0 0 0 0];
            left.RowSpacing    = 8;

            % PHYSICAL STACK ORDER, head to tail: the bolt, the washer under
            % its head, the clamped layers, the washer under the nut, and
            % what the bolt threads into. The banner above promises exactly
            % this, so the washers sit between the groups they physically
            % sit between rather than being appended.
            obj.buildBoltGroup(left, 1);
            obj.HeadWasher = obj.buildWasherGroup(left, 2, ...
                'Washer under bolt head', false);
            obj.buildFlangeGroup(left, 3);
            obj.NutWasher = obj.buildWasherGroup(left, 4, ...
                'Washer under nut', true);
            obj.buildMemberGroup(left, 5);
            obj.buildBoltLengthGroup(left, 6);
            obj.buildAdvancedGroup(left, 7);

            right = uigridlayout(g, [4 1]);
            right.Layout.Row    = 2;
            right.Layout.Column = 2;
            right.ColumnWidth   = {'1x'};
            right.RowHeight     = repmat({'fit'}, 1, 4);
            right.Padding       = [0 0 0 0];
            right.RowSpacing    = 8;

            obj.buildPreloadGroup(right, 1);
            obj.buildLoadsGroup(right, 2);
            obj.buildAssumptionsGroup(right, 3);
            obj.buildActionsGroup(right, 4);
            % Families first, then the enable pass that reads their state.
            obj.populateSpecPickers();
            obj.syncWasherEnables();

            obj.listenTo('JointChanged', @() obj.refresh());
            obj.listenTo('LoadCaseChanged', @() obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            %REFRESH  AppState.Joint -> controls. Never marks dirty (A4).
            if ~obj.IsBuilt || obj.Refreshing
                return
            end
            obj.Refreshing = true;
            c = onCleanup(@() obj.clearRefreshing()); %#ok<NASGU>

            j = obj.State.Joint;
            obj.JointNameField.Value  = char(j.Name);
            obj.BoltCountField.Value  = j.BoltCount;
            obj.trySelect(obj.BoltDropDown,         j.Bolt.Designation);
            obj.trySelect(obj.BoltMaterialDropDown, j.BoltMaterial.Name);
            obj.applyFlangeStack(j.FlangeStack);
            obj.updateGripLabel();

            % Choices first: the ladder is per-bolt, and the value has to
            % land in a list that already reflects the bolt just selected.
            obj.updateBoltLengthChoices();
            obj.BoltLengthField.Value  = ...
                gui2.JointConfigPage.lengthChoice(j.Bolt.Length);
            obj.BodyLengthField.Value  = obj.fmtOptional(j.BodyLengthInGrip);
            obj.RatedUltField.Value    = obj.fmtOptional(j.BoltRatedUltimateLoad);
            obj.RatedYieldField.Value  = obj.fmtOptional(j.BoltRatedYieldLoad);
            obj.FrustumAngleField.Value = j.FrustumAngle;

            m = j.ThreadedMember;
            obj.MemberTypeDropDown.Value = ...
                gui2.JointConfigPage.memberTypeLabel(m.Type);
            obj.trySelect(obj.MemberMaterialDropDown, m.Material.Name);
            % BOTH engagement controls are seeded regardless of type: each
            % holds its own property, so a case carrying both keeps both.
            obj.EngagementRatioField.Value  = obj.fmtOptional(m.EngagementRatio);
            obj.EngagementLengthField.Value = obj.fmtOptional(m.EngagementLength);
            obj.syncMemberType();
            obj.syncJointLoadVisibility();
            obj.updateBoltLengthLabel();

            obj.FrictionField.Value      = j.FrictionCoefficient;
            obj.LoadingPlaneField.Value  = j.LoadingPlaneFactor;
            obj.ShearPlaneDropDown.Value = char(string(j.ShearPlane));
            obj.SlipModeDropDown.Value   = char(string(j.SlipMode));
            obj.BoltAxisDropDown.Value   = char(string(j.BoltAxis));

            ps = j.PreloadSpec;
            obj.NominalTorqueField.Value      = obj.fmtOptional(ps.NominalTorque);
            obj.TorqueTolField.Value          = ps.TorqueTolerance;
            obj.NutFactorField.Value          = ps.NutFactor;
            obj.UncertaintyField.Value        = ps.Uncertainty;
            obj.RelaxationField.Value         = ps.RelaxationFraction;
            obj.SeparationCriticalCheck.Value = ps.SeparationCritical;

            lc = obj.State.LoadCase;
            obj.CaseNameField.Value     = char(lc.Name);
            obj.BoltTensileField.Value  = obj.fmtOptional(lc.BoltTensileLimitLoad);
            obj.BoltShearField.Value    = obj.fmtOptional(lc.BoltShearLimitLoad);
            obj.JointTensileField.Value = obj.fmtOptional(lc.JointTensileLimitLoad);
            obj.JointShearField.Value   = obj.fmtOptional(lc.JointShearLimitLoad);

            obj.validateRequired();

            % Same as Head is PAGE state and stays cleared: model.Joint
            % holds the two washers independently, so a loaded case
            % defines both explicitly and a mirrored view would be
            % asserting a link the file never carried.
            obj.SameAsHeadCheck.Value = false;

            % The spec pickers start from Custom and are then RE-DERIVED
            % from the geometry that was just loaded. model.Joint records
            % resolved numbers rather than which family produced them, so
            % the picker cannot be restored from the file — but the
            % catalogue can be asked which part has exactly these
            % dimensions, and an exact hit is evidence enough. This used
            % to stop at the reset, which meant saving a case and
            % reloading it silently downgraded every washer to Custom.
            obj.resetSpecPickers();
            obj.applyWasher(obj.HeadWasher, j.HeadWasher);
            obj.applyWasher(obj.NutWasher,  j.NutWasher);
            obj.reselectWasherSpec('Head', j.HeadWasher);
            obj.reselectWasherSpec('Nut',  j.NutWasher);
            obj.reselectNutSpec(j.ThreadedMember);
            obj.syncWasherEnables();
        end
    end

    % ---- Layout -----------------------------------------------------------
    methods (Access = private)
        function buildBoltGroup(obj, parent, row)
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Bolt');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [4 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = repmat({'fit'}, 1, 4);
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            % Spans the gutter: a joint name is prose, and the value column
            % is sized for numbers.
            obj.JointNameField = uieditfield(b, 'text', ...
                'HorizontalAlignment', 'left');   % prose, not a number
            obj.JointNameField.Layout.Row    = 1;
            obj.JointNameField.Layout.Column = [2 3];
            lb = uilabel(b, 'Text', 'Joint name');
            lb.Layout.Row = 1; lb.Layout.Column = 1;
            obj.bindEdit(obj.JointNameField, @(~, ~) obj.commitJoint());

            % Not commitJoint: the bolt keys every cascade on the page, so a
            % change to it re-resolves the bolt spec, the nut family and
            % both washer families before committing.
            obj.BoltDropDown = obj.addDropdown(b, 2, 'Bolt', ...
                obj.libraryItems('bolt'), ...
                'Fastener from the hardware library. Required.');
            obj.bindEdit(obj.BoltDropDown, @(~, ~) obj.onBoltChanged());

            obj.BoltMaterialDropDown = obj.addDropdown(b, 3, 'Bolt material', ...
                obj.libraryItems('boltMaterial'), ...
                'Bolt material from the hardware library. Required.');
            obj.bindEdit(obj.BoltMaterialDropDown, @(~, ~) obj.onBoltMaterialChanged());

            obj.BoltCountField = obj.addNumeric(b, 4, 'Bolt count nf', ...
                'Number of fasteners in the pattern.');
            obj.BoltCountField.Limits = [1 Inf];
            obj.BoltCountField.RoundFractionalValues = 'on';
            obj.BoltCountField.Value = 1;
            obj.bindEdit(obj.BoltCountField, @(~, ~) obj.commitJoint());
        end

        function buildFlangeGroup(obj, parent, row)
            % Named to head off the obvious misreading: the threaded member
            % is NOT a layer here. Nut, insert or tapped parent is its own
            % group - the stack is what the bolt clamps, nothing else.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', ...
                'Flange stack (clamped layers only - not the threaded member)');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            outer = uigridlayout(panel, [2 1]);
            outer.RowHeight   = {'fit', 'fit'};
            outer.ColumnWidth = {'1x'};
            outer.RowSpacing  = 6;
            outer.Padding     = [6 6 6 6];

            % NO "Active" COLUMN. A layer is in the stack when it has a
            % thickness - that is the whole rule. The reverted build carried
            % an Active checkbox as a second, independent way to say the
            % same thing, and the two states had to be kept in step: the
            % deserializer unticked every row for an empty stack, which
            % silently undid the pre-ticked first row and made typing a
            % thickness do nothing. One source of truth removes the bug and
            % a column. To park a layer, clear its thickness.
            heads = {'Layer', 'Name', 'Material', 't (in)', ...
                     'Hole (in)', 'Edge (in)', 'Tear-out'};
            tips  = { ...
                'Layer number, top being under the bolt head.', ...
                'Optional label. Never affects the analysis.', ...
                'Layer material. Fsu drives tear-out; Fbru/Fbry drive bearing.', ...
                'Layer thickness t, in.', ...
                'Clearance hole diameter, in. Blank = bearing not evaluated.', ...
                'Hole centre to free edge e, in. Blank = tear-out not evaluated.', ...
                'Run the shear tear-out check on this layer.'};

            n = gui2.JointConfigPage.MaxFlangeLayers;
            fg = uigridlayout(outer, [n + 1, numel(heads)]);
            fg.Layout.Row    = 1;
            fg.Layout.Column = 1;
            % Name takes '1x': it is the one free-text column, and the
            % others are sized for the numbers they hold.
            fg.ColumnWidth   = {44, '1x', 150, 66, 76, 76, 66};
            fg.RowHeight     = repmat({'fit'}, 1, n + 1);
            fg.RowSpacing    = 4;
            fg.ColumnSpacing = 4;
            fg.Padding       = [0 0 0 0];

            for c = 1:numel(heads)
                h = uilabel(fg, 'Text', heads{c}, 'Tooltip', tips{c}, ...
                    'FontWeight', 'bold');
                h.Layout.Row = 1; h.Layout.Column = c;
            end

            obj.FlangeName      = cell(1, n);
            obj.FlangeMaterial  = cell(1, n);
            obj.FlangeThickness = cell(1, n);
            obj.FlangeHole      = cell(1, n);
            obj.FlangeEdge      = cell(1, n);
            obj.FlangeTearout   = cell(1, n);

            mats = obj.libraryItems('material');
            for i = 1:n
                r = i + 1;

                num = uilabel(fg, 'Text', sprintf('%d', i), 'Tooltip', tips{1});
                num.Layout.Row = r; num.Layout.Column = 1;

                obj.FlangeName{i} = uieditfield(fg, 'text', 'Tooltip', tips{2}, ...
                    'HorizontalAlignment', 'left');   % prose
                obj.FlangeName{i}.Layout.Row = r;
                obj.FlangeName{i}.Layout.Column = 2;
                obj.bindEdit(obj.FlangeName{i}, @(~, ~) obj.commitJoint());

                obj.FlangeMaterial{i} = uidropdown(fg, 'Items', mats, ...
                    'Value', gui2.JointConfigPage.BlankChoice, 'Tooltip', tips{3});
                obj.FlangeMaterial{i}.Layout.Row = r;
                obj.FlangeMaterial{i}.Layout.Column = 3;
                obj.bindEdit(obj.FlangeMaterial{i}, @(~, ~) obj.onFlangeEdited());

                % TEXT, not numeric. A numeric field cannot be empty - it
                % renders 0.00000, which has to be cleared before a real
                % thickness can be typed, and reads as a layer of zero
                % thickness rather than as no layer at all. Blank is the
                % honest empty state, and model.FlangeLayer.Thickness is
                % mustBePositive so zero was never valid anyway.
                obj.FlangeThickness{i} = uieditfield(fg, 'text', ...
                    'Tooltip', tips{4}, 'HorizontalAlignment', 'right');
                obj.FlangeThickness{i}.Layout.Row = r;
                obj.FlangeThickness{i}.Layout.Column = 4;
                obj.bindEdit(obj.FlangeThickness{i}, @(~, ~) obj.onFlangeEdited());

                obj.FlangeHole{i} = uieditfield(fg, 'text', 'Tooltip', tips{5}, ...
                    'HorizontalAlignment', 'right');
                obj.FlangeHole{i}.Layout.Row = r;
                obj.FlangeHole{i}.Layout.Column = 5;
                obj.bindEdit(obj.FlangeHole{i}, @(~, ~) obj.commitJoint());

                obj.FlangeEdge{i} = uieditfield(fg, 'text', 'Tooltip', tips{6}, ...
                    'HorizontalAlignment', 'right');
                obj.FlangeEdge{i}.Layout.Row = r;
                obj.FlangeEdge{i}.Layout.Column = 6;
                obj.bindEdit(obj.FlangeEdge{i}, @(~, ~) obj.commitJoint());

                obj.FlangeTearout{i} = uicheckbox(fg, 'Text', '', ...
                    'Value', true, 'Tooltip', tips{7});
                obj.FlangeTearout{i}.Layout.Row = r;
                obj.FlangeTearout{i}.Layout.Column = 7;
                obj.bindEdit(obj.FlangeTearout{i}, @(~, ~) obj.commitJoint());
            end

            obj.GripLabel = uilabel(outer, 'Text', '');
            obj.GripLabel.Layout.Row    = 2;
            obj.GripLabel.Layout.Column = 1;
        end

        function w = buildWasherGroup(obj, parent, row, titleText, withSameAsHead)
            %BUILDWASHERGROUP  One washer group; returns its handles.
            %   Both groups come from here, so the two structs carry
            %   identical fields in identical order - the thing that makes
            %   them safe to treat alike.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', titleText);
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            nRows = 7;
            b = uigridlayout(panel, [nRows 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = repmat({'fit'}, 1, nRows);
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            r = 1;
            w.Present = uicheckbox(b, 'Text', 'Washer present', ...
                'Value', false, 'Tooltip', ...
                ['Unchecked marshals the model default - no washer - NOT a ' ...
                 'washer of zero thickness. Rigid in the frustum stiffness ' ...
                 'model; its OD is the bearing face diameter.']);
            % Present and the mirror share a row: they are the two switches
            % that decide whether the rest of the group is editable at all,
            % so they read as one decision rather than two stacked ones.
            w.Present.Layout.Row = r; w.Present.Layout.Column = 1;
            obj.bindEdit(w.Present, @(~, ~) obj.onWasherPresentToggled());

            if withSameAsHead
                obj.SameAsHeadCheck = uicheckbox(b, 'Text', 'Same as under head', ...
                    'Value', false, 'Tooltip', ...
                    ['Mirror the washer under the bolt head live - material, ' ...
                     'OD, ID and thickness - and grey this group. Unticking ' ...
                     'KEEPS the mirrored values and re-enables editing; it ' ...
                     'never blanks them.']);
                obj.SameAsHeadCheck.Layout.Row    = r;
                obj.SameAsHeadCheck.Layout.Column = [2 3];
                obj.bindEdit(obj.SameAsHeadCheck, @(~, ~) obj.onSameAsHeadToggled());
            end

            % Spec + size, above the geometry they fill. A family resolves
            % MANY washers at one bolt size - 2-3 for NAS1149 - so unlike
            % the nut cascade this needs a second picker to choose between
            % them, and the family alone can never fill anything.
            r = r + 1;
            w.Spec = obj.addDropdown(b, r, 'Washer spec', ...
                {gui2.JointConfigPage.CustomChoice}, ...
                ['Pick a washer family to list the sizes catalogued at the ' ...
                 'selected bolt''s nominal diameter. Choosing a size fills ' ...
                 'and LOCKS OD, ID and thickness. Custom re-enables them ' ...
                 'and always remains available.']);

            r = r + 1;
            w.Size = obj.addDropdown(b, r, 'Washer size', ...
                {gui2.JointConfigPage.SizeNA}, ...
                ['Sizes catalogued at the selected bolt''s nominal ' ...
                 'diameter, thinnest first. A washer family resolves to ' ...
                 'several thicknesses, so the family alone cannot fill the ' ...
                 'geometry.']);
            w.Size.Enable = 'off';

            % Locked by a resolved size, so syncWasherEnables can tell
            % "greyed because the catalogue owns it" from "greyed because
            % there is no washer here". Both groups carry the field, so the
            % two structs stay identical in shape.
            w.Locked = false;

            r = r + 1;
            w.Material = obj.addDropdown(b, r, 'Washer material', ...
                obj.libraryItems('washerMaterial'), ...
                'Washer material. Carried for completeness; washers are rigid in the engine.');

            r = r + 1;
            w.OD = obj.addLabelledText(b, r, 'Outer diameter (in)', ...
                ['Washer OD - the bearing face diameter, and the frustum ' ...
                 'contact diameter in engine.stiffness. Blank = unspecified.']);

            r = r + 1;
            w.ID = obj.addLabelledText(b, r, 'Inner diameter (in)', ...
                'Washer ID, in. Carried for completeness; unused by the engine.');

            r = r + 1;
            w.Thk = obj.addNumeric(b, r, 'Thickness (in)', ...
                'Washer thickness, in. Adds clamped length in engine.stiffness.');
            w.Thk.Limits = [0 Inf];
            w.Thk.ValueDisplayFormat = '%.5f';

            % One handler per group, so the head group can drive the mirror
            % and the nut group cannot. `which` names the group for the
            % cascade, which needs to know whose OD/ID/thickness to fill.
            if withSameAsHead
                cb    = @(~, ~) obj.onNutWasherEdited();
                which = 'Nut';
            else
                cb    = @(~, ~) obj.onHeadWasherEdited();
                which = 'Head';
            end
            obj.bindEdit(w.Material, cb);
            obj.bindEdit(w.OD,       cb);
            obj.bindEdit(w.ID,       cb);
            obj.bindEdit(w.Thk,      cb);
            obj.bindEdit(w.Spec, @(~, ~) obj.onWasherSpecChanged(which));
            obj.bindEdit(w.Size, @(~, ~) obj.onWasherSizeChanged(which));
        end

        function buildMemberGroup(obj, parent, row)
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Threaded member');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [5 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = repmat({'fit'}, 1, 5);
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            obj.MemberTypeDropDown = obj.addDropdown(b, 1, 'Type', ...
                gui2.JointConfigPage.memberTypeItems(), ...
                'What the bolt threads into on the far side of the joint.');
            % Type is not a required-blank field: a joint always threads
            % into something, so the model default (Nut) is a real answer
            % rather than a silent guess.
            obj.MemberTypeDropDown.Value = gui2.JointConfigPage.memberTypeLabel( ...
                model.ThreadedMemberType.Nut);
            obj.bindEdit(obj.MemberTypeDropDown, @(~, ~) obj.onMemberTypeChanged());

            % Nut families only. An insert resolves through NASM33537
            % geometry rather than a picker, and a tapped hole has no
            % catalogue at all - so this control is meaningful for exactly
            % one member type and disables itself for the other two.
            obj.NutSpecDropDown = obj.addDropdown(b, 2, 'Nut spec', ...
                {gui2.JointConfigPage.CustomChoice}, ...
                ['Pick a nut family to resolve it against the selected ' ...
                 'bolt''s thread size, filling and LOCKING the material and ' ...
                 'the engagement length. Custom re-enables them and always ' ...
                 'remains available. Nut member type only.']);
            obj.bindEdit(obj.NutSpecDropDown, @(~, ~) obj.onNutSpecChanged());

            [obj.MemberMaterialDropDown, obj.MemberMaterialLabel] = ...
                obj.addDropdown(b, 3, 'Nut material', ...
                    obj.libraryItems('material'), ...
                    ['The material whose shear allowable carries the ' ...
                     'internal thread: the nut itself, or the parent body ' ...
                     'for an insert or a tapped hole.']);
            obj.bindEdit(obj.MemberMaterialDropDown, @(~, ~) obj.commitJoint());

            % TWO controls, not one that changes meaning. Each maps to its
            % own model.ThreadedMember property, so a ratio left behind by
            % a former Insert can never be read as inches (A9). The
            % irrelevant one greys out; both keep their values, so flipping
            % type to compare and flipping back loses nothing.
            [obj.EngagementRatioField, obj.EngagementRatioLabel] = ...
                obj.addLabelledText(b, 4, 'Engagement (x bolt D)', ...
                    ['Thread engagement as a MULTIPLE OF THE BOLT NOMINAL ' ...
                     'DIAMETER, e.g. 1.5 for 1.5D. Helical inserts are ' ...
                     'specified by length CLASS, not an absolute inch ' ...
                     'value (NASM33537 Rev 4 Sec 6.1). Helical Insert only.']);
            % onEngagementEdited, not commitJoint: engagement feeds the
            % required bolt length, so the readout has to follow it. Binding
            % straight to commitJoint left the four-line readout stale while
            % an insert's engagement changed under it.
            obj.bindEdit(obj.EngagementRatioField, @(~, ~) obj.onEngagementEdited());

            [obj.EngagementLengthField, obj.EngagementLengthLabel] = ...
                obj.addLabelledText(b, 5, 'Engagement length Le (in)', ...
                    ['Thread engagement in INCHES - nut thread height, or ' ...
                     'tapped-hole engagement depth. Nut and Tapped Hole ' ...
                     'only. Blank leaves the thread checks not evaluated.']);
            obj.bindEdit(obj.EngagementLengthField, @(~, ~) obj.onEngagementEdited());
        end

        function [c, lb] = addLabelledText(obj, g, row, labelText, tip)
            lb = uilabel(g, 'Text', labelText, 'Tooltip', tip);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            c = uieditfield(g, 'text', 'Tooltip', tip);
            c.Layout.Row = row; c.Layout.Column = 2;
            % addLabelledText carries NUMBERS held in text fields - lengths,
            % torques, loads - which are text only so that blank can mean
            % "not supplied". They right-align with the numeric fields;
            % prose fields set 'left' explicitly at their own site.
            c.HorizontalAlignment = 'right';
        end

        function buildBoltLengthGroup(obj, parent, row)
            %BUILDBOLTLENGTHGROUP  Overall bolt length, and whether it fits.
            %   LAST in the left column, and deliberately so: the adequacy
            %   readout depends on the flange stack, BOTH washers and the
            %   threaded member's engagement, so it has to sit below every
            %   input it consumes. The first build put a readout above two
            %   of its own inputs.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Bolt length');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [2 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = {'fit', 'fit'};
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            tip = ['OVERALL length, under-head to tip - not the thread ' ...
                   'length and not L1. The list holds the lengths this ' ...
                   'bolt''s standard tabulates (NAS1351/NAS1352 Table ' ...
                   'III), but the box is EDITABLE: Table III''s own note ' ...
                   'reads "see code for additional lengths", so a length ' ...
                   'outside the list is procurable and is accepted. Blank ' ...
                   'leaves the engine to estimate grip + nut height + ' ...
                   '2*pitch (NASA-STD-5020B 4.7.4).'];
            lb = uilabel(b, 'Text', 'Overall bolt length (in)', 'Tooltip', tip);
            lb.Layout.Row = 1; lb.Layout.Column = 1;

            % EDITABLE dropdown, not a picker plus a separate "other" field.
            % The catalogue is a starting point rather than a constraint --
            % see the tooltip - so pick-or-type has to be one control, and
            % an editable uidropdown is exactly that. Items are bare
            % numbers so parsePositive reads Value unchanged; the part
            % number belongs in the readout, where it can name the whole
            % dash number rather than crowd the list.
            %
            % NO ItemsData: MATLAB requires it to be empty when Editable
            % is on, which is also why the items cannot be labels.
            obj.BoltLengthField = uidropdown(b, 'Editable', 'on', ...
                'Items', {''}, 'Tooltip', tip);
            obj.BoltLengthField.Layout.Row    = 1;
            obj.BoltLengthField.Layout.Column = 2;
            obj.bindEdit(obj.BoltLengthField, @(~, ~) obj.onBoltLengthEdited());

            obj.BoltLengthLabel = uilabel(b, 'Text', '', 'WordWrap', 'on', ...
                'VerticalAlignment', 'top');
            obj.BoltLengthLabel.Layout.Row    = 2;
            obj.BoltLengthLabel.Layout.Column = [1 3];
        end

        function buildAdvancedGroup(obj, parent, row)
            %BUILDADVANCEDGROUP  The blank-means-automatic overrides.
            %   Everything here is optional and derived by the engine when
            %   left blank. They are grouped at the bottom rather than mixed
            %   into the stack because an override that sits among required
            %   inputs reads as one.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Advanced / overrides');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [4 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = repmat({'fit'}, 1, 4);
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            % L1 IS NOW A TRUE OVERRIDE, and this comment used to say the
            % opposite. It claimed L1 could not be automatic because no
            % seeded bolt carried a thread length -- true when written,
            % false since NAS1351/NAS1352 Table II's minimum basic thread
            % length was seeded onto all 25 catalogue bolts. Lt is keyed on
            % SIZE, not on the ordered length, which is what made it
            % catalogue data after all (GUI2_SPEC.md 7.2d, corrected).
            % engine.stiffness has always had the derivation; it was only
            % ever missing the input.
            obj.BodyLengthField = obj.addLabelledText(b, 1, ...
                'Unthreaded body length L1 (in)', ...
                ['L1 - the UNTHREADED shank length inside the clamp, used ' ...
                 'for bolt stiffness. NOT the bolt length and NOT the ' ...
                 'thread length. OPTIONAL: blank lets engine.stiffness ' ...
                 'derive it from the bolt length minus the catalogue ' ...
                 'thread length, or from the NASA-STD-5020B 4.7.4 length ' ...
                 'estimate. A value typed here OVERRIDES that. The Bolt ' ...
                 'length readout shows which one is in force. Note that ' ...
                 'Lt is a MINIMUM thread length, so a derived L1 is the ' ...
                 'longest shank the part can have.']);
            % Refreshes the readout, not just the model: the bolt length
            % group now reports WHICH L1 is in force, so typing one here
            % changes what that line has to say. Committing alone would
            % leave it claiming a derived value the override had just
            % replaced.
            obj.bindEdit(obj.BodyLengthField, @(~, ~) obj.onBodyLengthEdited());

            obj.RatedUltField = obj.addLabelledText(b, 2, ...
                'Bolt rated ultimate (lbf)', ...
                ['Spec-rated Ptu-allow. Blank = the engine derives ' ...
                 'At x Ftu, which is a derived convention rather than a ' ...
                 '5020B equation.']);
            obj.bindEdit(obj.RatedUltField, @(~, ~) obj.commitJoint());

            obj.RatedYieldField = obj.addLabelledText(b, 3, ...
                'Bolt rated yield (lbf)', ...
                ['Spec-rated Pty-allow. Blank = the engine derives it via ' ...
                 'NASA-STD-5020B Eq. 18.']);
            obj.bindEdit(obj.RatedYieldField, @(~, ~) obj.commitJoint());

            % NOT a text field like the others: FrustumAngle is the one
            % property here with no NaN state - model.Joint requires
            % 0 < angle < 90 always. A numeric field with exclusive limits
            % refuses an invalid value at the widget, so marshalling can
            % never be handed one.
            lb = uilabel(b, 'Text', 'Frustum half-angle (deg)');
            lb.Layout.Row = 4; lb.Layout.Column = 1;
            obj.FrustumAngleField = uieditfield(b, 'numeric', ...
                'HorizontalAlignment', 'right', ...
                'Limits', [0 90], 'LowerLimitInclusive', 'off', ...
                'UpperLimitInclusive', 'off', 'RoundFractionalValues', 'on', ...
                'Value', 30);
            obj.FrustumAngleField.Layout.Row = 4;
            obj.FrustumAngleField.Layout.Column = 2;
            obj.FrustumAngleField.Tooltip = ['Conical-frustum half-angle ' ...
                'for the member-stiffness model. Integer degrees; the ' ...
                'model default is 30.'];
            lb.Tooltip = obj.FrustumAngleField.Tooltip;
            obj.bindEdit(obj.FrustumAngleField, @(~, ~) obj.commitJoint());
        end

        function buildPreloadGroup(obj, parent, row)
            %BUILDPRELOADGROUP  model.PreloadSpec, torque-controlled.
            %   Method is hard-set to TorqueControl and has no selector:
            %   this team's workflow is always torque-controlled, and the
            %   first build removed the selector for the same reason.
            %   CreepLoss and ThermalRate have no controls either - the
            %   model keeps them for headless and fixture use.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Preload (torque-controlled)');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = obj.groupGrid(panel, 6);

            obj.NominalTorqueField = obj.addLabelledText(b, 1, ...
                'Nominal torque (in-lbf)', ...
                'Applied effective torque, above running torque.');
            obj.bindEdit(obj.NominalTorqueField, @(~, ~) obj.commitJoint());

            % These four are mustBeNonnegative / mustBePositive with NO NaN
            % state, so they are numeric fields with limits rather than text
            % that could parse to NaN and be rejected by the model.
            obj.TorqueTolField = obj.addNumeric(b, 2, 'Torque tolerance +/- (frac)', ...
                ['Tolerance band on the SPECIFIED TORQUE - how accurately ' ...
                 'the wrench is set. "40 +/- 2 in-lbf" is 0.05. ' ...
                 'NASA-STD-5020B 4.3.1: enters as c_max = 1 + tol and ' ...
                 'c_min = 1 - tol. This is about the torque; the ' ...
                 'uncertainty below is about what that torque achieves.']);
            obj.TorqueTolField.Limits = [0 Inf];
            obj.TorqueTolField.ValueDisplayFormat = '%.2f';
            obj.TorqueTolField.Value = 0;
            obj.bindEdit(obj.TorqueTolField, @(~, ~) obj.commitJoint());

            obj.NutFactorField = obj.addNumeric(b, 3, 'Nut factor K', ...
                'Torque-to-preload nut factor K.');
            obj.NutFactorField.Limits = [0 Inf];
            obj.NutFactorField.LowerLimitInclusive = 'off';
            obj.NutFactorField.ValueDisplayFormat = '%.2f';
            obj.NutFactorField.Value = 0.2;
            obj.bindEdit(obj.NutFactorField, @(~, ~) obj.commitJoint());

            obj.UncertaintyField = obj.addNumeric(b, 4, 'Preload uncertainty +/- (Gamma)', ...
                ['Scatter in the TORQUE-TO-PRELOAD relationship - nut ' ...
                 'factor K and friction - not in the torque itself. ' ...
                 'NASA-STD-5020B Eq. 3/4/5: (1 +/- Gamma). 0.25 is the ' ...
                 'usual figure for an unlubricated fastener. Unlike torque ' ...
                 'tolerance it earns a statistical benefit across the ' ...
                 'pattern: a joint that is NOT separation-critical uses ' ...
                 'Gamma/sqrt(nf) on the minimum (Eq. 5).']);
            obj.UncertaintyField.Limits = [0 Inf];
            obj.UncertaintyField.ValueDisplayFormat = '%.2f';
            obj.UncertaintyField.Value = 0.25;
            obj.bindEdit(obj.UncertaintyField, @(~, ~) obj.commitJoint());

            obj.RelaxationField = obj.addNumeric(b, 5, 'Relaxation fraction', ...
                'Short-term preload relaxation, fractional.');
            obj.RelaxationField.Limits = [0 Inf];
            obj.RelaxationField.ValueDisplayFormat = '%.2f';
            obj.RelaxationField.Value = 0.05;
            obj.bindEdit(obj.RelaxationField, @(~, ~) obj.commitJoint());

            obj.SeparationCriticalCheck = uicheckbox(b, ...
                'Text', 'Separation critical joint', 'Value', false);
            obj.SeparationCriticalCheck.Layout.Row = 6;
            obj.SeparationCriticalCheck.Layout.Column = [1 3];
            obj.SeparationCriticalCheck.Tooltip = ['Selects the minimum ' ...
                'preload equation: NASA-STD-5020B Eq. 4 vs Eq. 5.'];
            obj.bindEdit(obj.SeparationCriticalCheck, @(~, ~) obj.commitJoint());
        end

        function buildLoadsGroup(obj, parent, row)
            %BUILDLOADSGROUP  model.LoadCase - the single-joint limit loads.
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Applied loads (single joint)');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = obj.groupGrid(panel, 5);

            obj.CaseNameField = obj.addLabelledText(b, 1, 'Case name', ...
                'Label for this load case. Never analysed.');
            obj.bindEdit(obj.CaseNameField, @(~, ~) obj.commitLoadCase());

            obj.BoltTensileField = obj.addLabelledText(b, 2, ...
                'Bolt tensile limit PtL', ...
                'Most-loaded bolt tensile limit load, lbf.');
            obj.bindEdit(obj.BoltTensileField, @(~, ~) obj.commitLoadCase());

            obj.BoltShearField = obj.addLabelledText(b, 3, ...
                'Bolt shear limit PsL', ...
                'Most-loaded bolt shear limit load, lbf.');
            obj.bindEdit(obj.BoltShearField, @(~, ~) obj.commitLoadCase());

            % Joint totals are shown ONLY for joint-mode slip. NASA-STD-5020B
            % Eq. 84 needs them; Eq. 86 (the single-fastener default) does
            % not, and showing them unconditionally is what made them
            % confusing. They are NOT BoltCount x per-bolt - engine
            % marginSlip says so explicitly, because of bolt-pattern load
            % distribution - so blank leaves the Slip row not evaluated.
            [obj.JointTensileField, obj.JointTensileLabel] = ...
                obj.addLabelledText(b, 4, 'Joint tensile total', ...
                    ['Joint-level tensile total, lbf. Required for ' ...
                     'joint-mode slip (5020B Eq. 84). NOT bolt count x ' ...
                     'the per-bolt load.']);
            obj.bindEdit(obj.JointTensileField, @(~, ~) obj.commitLoadCase());

            [obj.JointShearField, obj.JointShearLabel] = ...
                obj.addLabelledText(b, 5, 'Joint shear total', ...
                    ['Joint-level shear total, lbf. Required for ' ...
                     'joint-mode slip (5020B Eq. 84).']);
            obj.bindEdit(obj.JointShearField, @(~, ~) obj.commitLoadCase());
        end

        function buildAssumptionsGroup(obj, parent, row)
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Analysis assumptions');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = obj.groupGrid(panel, 6);

            obj.ShearPlaneDropDown = obj.addDropdown(b, 1, 'Shear plane', ...
                gui2.JointConfigPage.enumItems('model.ShearPlaneCondition'), ...
                ['Does the shear plane cut the THREADS or the ' ...
                 'full-diameter BODY? Body if the unthreaded shank ' ...
                 'extends past the faying surface; threads otherwise. ' ...
                 'Sets the shear area (5020B Eq. 12 shank vs Eq. 13 ' ...
                 'minor-diameter) AND the interaction exponents ' ...
                 '(Eq. 20/21 body 2.5/1.5, Eq. 22/23 threads 1.2/2.0). ' ...
                 'Threads is the conservative choice.']);
            obj.bindEdit(obj.ShearPlaneDropDown, @(~, ~) obj.commitJoint());

            obj.SlipModeDropDown = obj.addDropdown(b, 2, 'Slip mode', ...
                gui2.JointConfigPage.enumItems('model.SlipMode'), ...
                ['Single-fastener slip (5020B Eq. 86) or joint slip ' ...
                 '(Eq. 84). Joint mode needs the joint-level totals in ' ...
                 'Applied loads.']);
            obj.bindEdit(obj.SlipModeDropDown, @(~, ~) obj.onSlipModeChanged());

            obj.FrictionField = obj.addNumeric(b, 3, 'Friction coefficient', ...
                'Faying-surface friction. Zero means slip is not evaluated.');
            obj.FrictionField.Limits = [0 Inf];
            obj.FrictionField.Value = 0;
            obj.bindEdit(obj.FrictionField, @(~, ~) obj.commitJoint());

            obj.BoltAxisDropDown = obj.addDropdown(b, 4, 'Bolt axis', ...
                gui2.JointConfigPage.enumItems('model.BoltAxis'), ...
                ['Global FEM axis the fastener acts along. Used by the ' ...
                 'bulk path to split element forces into tension and ' ...
                 'shear.']);
            obj.bindEdit(obj.BoltAxisDropDown, @(~, ~) obj.commitJoint());

            obj.LoadingPlaneField = obj.addNumeric(b, 5, 'Loading-plane factor n', ...
                'n = Llp/L. 1.0 is conservative.');
            obj.LoadingPlaneField.Limits = [0 Inf];
            obj.LoadingPlaneField.ValueDisplayFormat = '%.2f';
            obj.LoadingPlaneField.Value = 1.0;
            obj.bindEdit(obj.LoadingPlaneField, @(~, ~) obj.commitJoint());

            % GUI2_SPEC.md 7.2f: the shear-transfer condition control is
            % deliberately absent and model.Joint keeps its NotDeclared
            % default, which computes fbu = 0 and records the exemption as
            % ASSUMED rather than VERIFIED. Hard-setting the "verified"
            % member instead would have every joint claim a verification
            % nobody performed. This note is the future-feature marker.
            note = uilabel(b, 'WordWrap', 'on', 'Text', ...
                ['Close-fit assumed - bolt bending (fbu = 0) not yet ' ...
                 'implemented; NASA-STD-5020B 4.4.4 exemption assumed, ' ...
                 'not verified.']);
            note.Layout.Row = 6;
            note.Layout.Column = [1 3];
            note.FontColor = gui2.palette('mutedText');
        end

        function buildActionsGroup(obj, parent, row)
            panel = uipanel(parent, 'FontWeight', 'bold', 'FontSize', 13, 'Title', 'Actions');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [3 1]);
            b.ColumnWidth = {'1x'};
            b.RowHeight   = {36, 'fit', 'fit'};
            b.RowSpacing  = 6;
            b.Padding     = [6 6 6 6];

            obj.AnalyzeButton = uibutton(b, 'push', ...
                'Text', 'Analyze Single Joint', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onAnalyze());
            obj.AnalyzeButton.Layout.Row    = 1;
            obj.AnalyzeButton.Layout.Column = 1;

            % The one place a required input is reported. Kept beneath the
            % button rather than beside each field: the analyst needs the
            % list at the moment they try to run, not scattered up the page.
            obj.RequiredLabel = uilabel(b, 'WordWrap', 'on', 'Text', '');
            obj.RequiredLabel.Layout.Row    = 2;
            obj.RequiredLabel.Layout.Column = 1;
            obj.RequiredLabel.FontColor     = gui2.palette('statusWarn');

            obj.SaveJointButton = uibutton(b, 'push', ...
                'Text', 'Save to Defined Joints', ...
                'ButtonPushedFcn', @(~, ~) obj.onSaveJoint());
            obj.SaveJointButton.Layout.Row    = 3;
            obj.SaveJointButton.Layout.Column = 1;
            obj.SaveJointButton.Tooltip = ['Store this joint in the ' ...
                'defined-joints library under its name. Saved with the ' ...
                'case file and used by the bulk workflow.'];
        end

        function b = groupGrid(~, panel, rows)
            %GROUPGRID  The right column's label / value / gutter grid.
            b = uigridlayout(panel, [rows 3]);
            % The LABEL column takes the slack, not a trailing gutter, so
            % the controls sit hard against the right edge of the panel and
            % line up as one column instead of drifting with label length.
            % A narrow third column stays so the full-width rows - the
            % separation-critical checkbox, the 4.4.4 note - can still span
            % [1 3].
            b.ColumnWidth = {'1x', gui2.JointConfigPage.ValueWRight, 4};
            b.RowHeight   = repmat({'fit'}, 1, rows);
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];
        end

        function [d, lb] = addDropdown(obj, g, row, labelText, items, tip) %#ok<INUSD>
            lb = uilabel(g, 'Text', labelText, 'Tooltip', tip);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            d = uidropdown(g, 'Items', items, 'Tooltip', tip);
            d.Layout.Row = row; d.Layout.Column = 2;
            % Land on the blank sentinel ONLY when the list actually has
            % one. Required pickers (bolt, materials) do; the member type
            % does not, because a joint always threads into something and
            % the model default is a real answer rather than a guess.
            % uidropdown rejects a Value that is not in Items, so setting
            % it unconditionally threw at construction.
            if any(strcmp(items, gui2.JointConfigPage.BlankChoice))
                d.Value = gui2.JointConfigPage.BlankChoice;
            end
        end

        function c = addNumeric(~, g, row, labelText, tip)
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            lb.Tooltip = tip;
            c = uieditfield(g, 'numeric');
            c.Layout.Row = row; c.Layout.Column = 2;
            c.HorizontalAlignment = 'right';
            c.Tooltip = tip;
        end

        function items = libraryItems(obj, which)
            %LIBRARYITEMS  Blank sentinel FIRST, then the keys (A6).
            %   A required dropdown must never land on whatever sorts first
            %   in the catalogue: that analyses hardware the analyst never
            %   chose, and looks deliberate while doing it.
            items = {gui2.JointConfigPage.BlankChoice};
            if ~obj.State.LibraryOK
                return
            end
            try
                switch which
                    case 'bolt'
                        keys = obj.State.Library.boltKeys();
                    case 'boltMaterial'
                        % Role-filtered: a washer alloy is not a bolt.
                        keys = obj.State.Library.materialKeys(Role = "bolt");
                    case 'washerMaterial'
                        keys = obj.State.Library.materialKeys(Role = "washer");
                    otherwise
                        % Flange layers take any material in the library.
                        keys = obj.State.Library.materialKeys();
                end
            catch
                return
            end
            if ~isempty(keys)
                items = [items, reshape(cellstr(keys), 1, [])];
            end
        end
    end

    % ---- Controls -> AppState ---------------------------------------------
    methods (Access = private)
        function commitJoint(obj)
            %COMMITJOINT  Controls -> AppState.Joint.
            %   Suppresses its own refresh: assigning State.Joint fires
            %   JointChanged, and repopulating from the joint just marshalled
            %   would fight whatever the analyst is typing.
            if obj.Refreshing
                return
            end
            obj.Refreshing = true;
            c = onCleanup(@() obj.clearRefreshing()); %#ok<NASGU>
            obj.State.Joint = obj.buildJoint();
            % One call site per FUNNEL rather than one per handler, so the
            % gate cannot be forgotten when a control is added. There are
            % two funnels -- see commitLoadCase, which runs it as well.
            obj.validateRequired();
        end

        function joint = buildJoint(obj)
            %BUILDJOINT  model.Joint from the controls. TOTAL — never throws.
            %   An incomplete form is the normal state while working, so a
            %   blank selection marshals as the model default rather than an
            %   error. Analyze is where completeness is enforced.
            joint = obj.State.Joint;
            joint.Name      = string(obj.JointNameField.Value);
            joint.BoltCount = obj.BoltCountField.Value;

            joint.Bolt         = obj.lookupBolt();
            joint.BoltMaterial = obj.lookupBoltMaterial();
            joint.FlangeStack  = obj.collectFlangeLayers();
            % parsePositive for L1 (mustBePositiveOrNaN); parseOptional for
            % the rated loads, which are mustBeNONNEGATIVEOrNaN - a rated
            % load of zero is a legitimate value, not a typo.
            joint.BodyLengthInGrip      = obj.parsePositive(obj.BodyLengthField);
            joint.BoltRatedUltimateLoad = obj.parseOptional(obj.RatedUltField);
            joint.BoltRatedYieldLoad    = obj.parseOptional(obj.RatedYieldField);
            joint.FrustumAngle          = obj.FrustumAngleField.Value;

            joint.FrictionCoefficient = obj.FrictionField.Value;
            joint.LoadingPlaneFactor  = obj.LoadingPlaneField.Value;
            joint.ShearPlane = gui2.JointConfigPage.enumFromLabel( ...
                'model.ShearPlaneCondition', obj.ShearPlaneDropDown.Value);
            joint.SlipMode   = gui2.JointConfigPage.enumFromLabel( ...
                'model.SlipMode', obj.SlipModeDropDown.Value);
            joint.BoltAxis   = gui2.JointConfigPage.enumFromLabel( ...
                'model.BoltAxis', obj.BoltAxisDropDown.Value);
            joint.PreloadSpec    = obj.buildPreloadSpec();
            joint.ThreadedMember = obj.buildThreadedMember();
            joint.HeadWasher     = obj.buildWasher(obj.HeadWasher);
            joint.NutWasher      = obj.buildWasher(obj.NutWasher);
        end

        function ps = buildPreloadSpec(obj)
            %BUILDPRELOADSPEC  Torque control always - see buildPreloadGroup.
            ps = obj.State.Joint.PreloadSpec;
            ps.Method             = model.PreloadMethod.TorqueControl;
            ps.NominalTorque      = obj.parseOptional(obj.NominalTorqueField);
            ps.TorqueTolerance    = obj.TorqueTolField.Value;
            ps.NutFactor          = obj.NutFactorField.Value;
            ps.Uncertainty        = obj.UncertaintyField.Value;
            ps.RelaxationFraction = obj.RelaxationField.Value;
            ps.SeparationCritical = logical(obj.SeparationCriticalCheck.Value);
        end

        function commitLoadCase(obj)
            %COMMITLOADCASE  Controls -> AppState.LoadCase. Suppresses its
            %   own echo for the same reason commitJoint does.
            if obj.Refreshing
                return
            end
            obj.Refreshing = true;
            c = onCleanup(@() obj.clearRefreshing()); %#ok<NASGU>
            obj.State.LoadCase = obj.buildLoadCase();
            % The gate reads the LOAD CASE too now, so this funnel has to
            % re-run it. There are two commit funnels, not one, and only
            % commitJoint used to call the gate -- which was fine while
            % the gate asked about hardware alone. Without this, typing
            % the load that completes the form would leave Analyze
            % disabled until some unrelated joint edit happened to run it.
            obj.validateRequired();
        end

        function lc = buildLoadCase(obj)
            %BUILDLOADCASE  TOTAL, like buildJoint. Every field here is
            %   mustBeNonnegativeOrNaN, so a typed zero is a legitimate
            %   load and parseOptional keeps it.
            lc = obj.State.LoadCase;
            lc.Name                  = string(obj.CaseNameField.Value);
            lc.BoltTensileLimitLoad  = obj.parseOptional(obj.BoltTensileField);
            lc.BoltShearLimitLoad    = obj.parseOptional(obj.BoltShearField);
            lc.JointTensileLimitLoad = obj.parseOptional(obj.JointTensileField);
            lc.JointShearLimitLoad   = obj.parseOptional(obj.JointShearField);
        end

        function w = buildWasher(obj, g)
            %BUILDWASHER  One group -> model.Washer.
            %   Present unchecked marshals the MODEL DEFAULT - "no washer" -
            %   not a washer of zero thickness typed by nobody. The two are
            %   different joints.
            if ~g.Present.Value
                w = model.Washer();
                return
            end
            w = model.Washer( ...
                Thickness     = g.Thk.Value, ...
                OuterDiameter = obj.parsePositive(g.OD), ...
                InnerDiameter = obj.parsePositive(g.ID), ...
                Material      = obj.lookupMaterial(g.Material));
        end

        function applyWasher(obj, g, w)
            %APPLYWASHER  model.Washer -> one group's controls.
            %   Present is derived from the washer actually carrying
            %   something: the model default has zero thickness and no OD,
            %   which is precisely "there is no washer here".
            g.Thk.Value      = w.Thickness;
            g.OD.Value       = obj.fmtOptional(w.OuterDiameter);
            g.ID.Value       = obj.fmtOptional(w.InnerDiameter);
            obj.trySelect(g.Material, w.Material.Name);
            g.Present.Value  = (w.Thickness > 0) || ~isnan(w.OuterDiameter);
        end

        function m = buildThreadedMember(obj)
            %BUILDTHREADEDMEMBER  The type decides which engagement property
            %   is marshalled; the other stays NaN, so a number sitting in
            %   the greyed control can never reach the engine as the wrong
            %   quantity.
            m = obj.State.Joint.ThreadedMember;
            m.Type     = obj.selectedMemberType();
            m.Material = obj.lookupMaterial(obj.MemberMaterialDropDown);
            if m.Type == model.ThreadedMemberType.Insert
                m.EngagementRatio  = obj.parseOptional(obj.EngagementRatioField);
                m.EngagementLength = NaN;
            else
                m.EngagementLength = obj.parseOptional(obj.EngagementLengthField);
                m.EngagementRatio  = NaN;
            end
        end

        function layers = collectFlangeLayers(obj)
            %COLLECTFLANGELAYERS  The rows that are actually in the stack.
            %   A row counts when it has a positive thickness. That is the
            %   only rule - there is no separate Active state to disagree
            %   with it.
            %   A blank material is NOT a reason to drop it: the layer has a
            %   real thickness and belongs in the grip, and dropping it made
            %   the grip readout report zero while the analyst was still
            %   choosing materials. model.Material() carries no allowables,
            %   so the engine reports the checks that need them as not
            %   evaluated - which is the honest outcome, and the analyst is
            %   told by required-field validation, not by a silent omission.
            layers = model.FlangeLayer.empty(1, 0);
            for i = 1:gui2.JointConfigPage.MaxFlangeLayers
                t = obj.parsePositive(obj.FlangeThickness{i});
                if ~(t > 0)
                    continue
                end
                layers(end + 1) = model.FlangeLayer( ...
                    Name              = string(obj.FlangeName{i}.Value), ...
                    Material          = obj.lookupMaterial(obj.FlangeMaterial{i}), ...
                    Thickness         = t, ...
                    HoleDiameter      = obj.parsePositive(obj.FlangeHole{i}), ...
                    EdgeDistance      = obj.parsePositive(obj.FlangeEdge{i}), ...
                    CheckShearTearout = logical(obj.FlangeTearout{i}.Value)); %#ok<AGROW>
            end
        end

        function applyFlangeStack(obj, stack)
            %APPLYFLANGESTACK  model.Joint.FlangeStack -> the layer rows.
            n = gui2.JointConfigPage.MaxFlangeLayers;
            for i = 1:n
                if i <= numel(stack)
                    L = stack(i);
                    obj.FlangeName{i}.Value      = char(L.Name);
                    obj.FlangeThickness{i}.Value = obj.fmtOptional(L.Thickness);
                    obj.FlangeHole{i}.Value      = obj.fmtOptional(L.HoleDiameter);
                    obj.FlangeEdge{i}.Value      = obj.fmtOptional(L.EdgeDistance);
                    obj.FlangeTearout{i}.Value   = L.CheckShearTearout;
                    obj.trySelect(obj.FlangeMaterial{i}, L.Material.Name);
                else
                    % Rows beyond the stack are cleared, not just unticked:
                    % leaving a previous case's numbers behind an unticked
                    % box invites re-ticking them into a different joint.
                    obj.FlangeName{i}.Value      = '';
                    obj.FlangeThickness{i}.Value = '';
                    obj.FlangeHole{i}.Value      = '';
                    obj.FlangeEdge{i}.Value      = '';
                    obj.FlangeTearout{i}.Value   = true;
                    obj.trySelect(obj.FlangeMaterial{i}, "");
                end
            end
        end

        function onWasherPresentToggled(obj)
            obj.syncWasherEnables();
            obj.commitJoint();
        end

        function onSameAsHeadToggled(obj)
            %ONSAMEASHEADTOGGLED  Ticking mirrors now; unticking keeps what
            %   was mirrored and hands editing back. It NEVER blanks the
            %   values - that is the whole point of the harvested behavior.
            if obj.SameAsHeadCheck.Value
                obj.mirrorHeadToNut();
            end
            obj.syncWasherEnables();
            obj.commitJoint();
        end

        function onHeadWasherEdited(obj)
            % Live mirroring: the nut group follows every head edit while
            % Same as Head is ticked.
            if ~isempty(obj.SameAsHeadCheck) && obj.SameAsHeadCheck.Value
                obj.mirrorHeadToNut();
            end
            obj.commitJoint();
        end

        function onNutWasherEdited(obj)
            obj.commitJoint();
        end

        function mirrorHeadToNut(obj)
            %MIRRORHEADTONUT  Copy the four mirrored values, head -> nut.
            %   Present is NOT mirrored: a joint can legitimately have a
            %   washer under the head and none under the nut, so that stays
            %   the nut group's own decision.
            obj.NutWasher.OD.Value  = obj.HeadWasher.OD.Value;
            obj.NutWasher.ID.Value  = obj.HeadWasher.ID.Value;
            obj.NutWasher.Thk.Value = obj.HeadWasher.Thk.Value;
            obj.trySelect(obj.NutWasher.Material, ...
                obj.selectedKey(obj.HeadWasher.Material));
        end

        function syncWasherEnables(obj)
            %SYNCWASHERENABLES  Enable only - never read-only (A5).
            %   A group's fields are live when its washer is present. The
            %   nut group additionally greys while it is mirroring the head,
            %   because there is nothing left to choose independently.
            if isempty(obj.HeadWasher) || isempty(obj.NutWasher)
                return
            end
            states = {'off', 'on'};

            headOn = logical(obj.HeadWasher.Present.Value);
            obj.setWasherFieldsEnable(obj.HeadWasher, headOn);

            nutPresent = logical(obj.NutWasher.Present.Value);
            mirroring  = logical(obj.SameAsHeadCheck.Value);
            % Same as Head is only meaningful once there IS a nut washer.
            obj.SameAsHeadCheck.Enable = states{nutPresent + 1};
            nutOn = nutPresent && ~mirroring;
            obj.setWasherFieldsEnable(obj.NutWasher, nutOn);
        end

        function setWasherFieldsEnable(~, w, groupLive)
            %SETWASHERFIELDSENABLE  Three reasons a field here can be dead.
            %   The group has no washer, or the nut group is mirroring the
            %   head, or a resolved catalogue size owns the geometry. The
            %   first two kill everything; the third kills only the
            %   geometry, because washer MATERIAL is not in the catalogue -
            %   library washers are geometry only, so a family can never
            %   speak for it.
            states = {'off', 'on'};
            geometryLive = groupLive && ~w.Locked;

            w.Material.Enable = states{groupLive + 1};
            w.Spec.Enable     = states{groupLive + 1};
            w.OD.Enable       = states{geometryLive + 1};
            w.ID.Enable       = states{geometryLive + 1};
            w.Thk.Enable      = states{geometryLive + 1};

            % The size picker is live only once a family has offered sizes.
            hasSizes = ~strcmp(w.Size.Value, gui2.JointConfigPage.SizeNA);
            w.Size.Enable = states{(groupLive && hasSizes) + 1};
        end

        function onMemberTypeChanged(obj)
            % applyNutSpec BEFORE syncMemberType would be wrong: the picker
            % has to be reset for the new type first, and applyNutSpec ends
            % by calling syncMemberType itself.
            obj.applyNutSpec();
            obj.syncJointLoadVisibility();
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        % ---- The library cascades -----------------------------------------
        %   Three pickers, one contract (A5): resolve against the selected
        %   bolt, fill what the catalogue knows, LOCK it with Enable='off',
        %   and on any miss revert to Custom, re-enable, and SAY SO naming
        %   the family and the thread size. Never leave numbers resolved for
        %   a different bolt sitting there looking authoritative.

        function onBoltChanged(obj)
            %ONBOLTCHANGED  One bolt change invalidates three pickers.
            %   Every cascade is keyed on the bolt's thread size, so a new
            %   bolt makes all of them stale at once. Re-resolving rather
            %   than clearing keeps a still-valid family selected.
            obj.updateSpecFields(true);
            obj.applyNutSpec();
            obj.applyWasherSpec('Head');
            obj.applyWasherSpec('Nut');
            obj.updateBoltLengthChoices();
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onBoltMaterialChanged(obj)
            % Only the bolt SPEC depends on the material - a nut or washer
            % family is resolved by thread size alone.
            obj.updateSpecFields(true);
            obj.commitJoint();
        end

        function updateSpecFields(obj, autofill)
            %UPDATESPECFIELDS  Bolt + material -> the rated loads.
            %   Pure lookup, no arithmetic. autofill=false refreshes nothing
            %   and exists so a loaded case's stored overrides are not
            %   clobbered by catalogue values on repopulation.
            %
            %   A MISS BLANKS THEM. Leaving the previous pairing's ratings
            %   in place would analyse the new bolt with the old bolt's
            %   numbers - and they would look like a deliberate override.
            if ~autofill || isempty(obj.RatedUltField) || ~obj.State.LibraryOK
                return
            end
            boltKey = obj.selectedKey(obj.BoltDropDown);
            matKey  = obj.selectedKey(obj.BoltMaterialDropDown);
            if strlength(boltKey) == 0 || strlength(matKey) == 0
                return
            end

            s = [];
            try
                s = obj.State.Library.boltSpecFor(boltKey, matKey);
            catch
                s = [];
            end

            if isempty(s)
                obj.RatedUltField.Value   = '';
                obj.RatedYieldField.Value = '';
                obj.setStatus(sprintf(['No rated loads catalogued for %s in ' ...
                    '%s - the engine will derive them, or enter them under ' ...
                    'Advanced.'], boltKey, matKey));
                return
            end
            obj.RatedUltField.Value   = obj.fmtOptional(s.RatedUltimateLoad);
            obj.RatedYieldField.Value = obj.fmtOptional(s.RatedYieldLoad);
            obj.setStatus(sprintf('Rated loads filled from %s.', s.Key));
        end

        function onNutSpecChanged(obj)
            obj.applyNutSpec();
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function applyNutSpec(obj)
            %APPLYNUTSPEC  Resolve the nut family at the bolt's thread size.
            %   NEVER MARKS DIRTY - this is state sync, not an edit, and it
            %   runs during construction and repopulation. Idempotent.
            if isempty(obj.NutSpecDropDown)
                return
            end

            % Not a Nut, or Custom: nothing owns the fields. Reverting the
            % value too, so a family left selected from a previous member
            % type cannot appear to be governing.
            isNut = obj.selectedMemberType() == model.ThreadedMemberType.Nut;
            spec  = string(obj.NutSpecDropDown.Value);
            if ~isNut || spec == gui2.JointConfigPage.CustomChoice
                if ~isNut
                    obj.NutSpecDropDown.Value = gui2.JointConfigPage.CustomChoice;
                end
                obj.NutSpecLocked = false;
                obj.syncMemberType();
                return
            end

            bolt = obj.selectedBolt();
            if isempty(bolt) || isnan(bolt.NominalDiameter) || ...
                    isnan(bolt.ThreadsPerInch)
                obj.releaseNutSpec(sprintf(['Pick a bolt before choosing a ' ...
                    'nut family - %s resolves by thread size.'], spec));
                return
            end

            n = [];
            try
                n = obj.State.Library.nutFor(bolt.NominalDiameter, ...
                    bolt.ThreadsPerInch, spec);
            catch
                n = [];
            end
            if isempty(n)
                obj.releaseNutSpec(sprintf(['No %s nut catalogued at %s - ' ...
                    'reverted to Custom; enter the nut fields manually.'], ...
                    spec, obj.threadDescription(bolt)));
                return
            end

            % A nut naming a material the library no longer carries must not
            % leave a stale selection LOCKED - that is the exact failure the
            % picker exists to prevent.
            if ~obj.trySelectKey(obj.MemberMaterialDropDown, n.Material)
                obj.releaseNutSpec(sprintf(['Nut %s names material "%s", ' ...
                    'which is not in the library - reverted to Custom.'], ...
                    n.Key, n.Material));
                return
            end

            obj.EngagementLengthField.Value = obj.fmtOptional(n.Height);
            obj.NutSpecLocked = true;
            obj.syncMemberType();
            obj.setStatus(sprintf('Nut %s filled the material and engagement.', ...
                n.Key));
        end

        function releaseNutSpec(obj, message)
            %RELEASENUTSPEC  Revert to Custom, unlock, and say why (A5).
            obj.NutSpecDropDown.Value = gui2.JointConfigPage.CustomChoice;
            obj.NutSpecLocked = false;
            obj.syncMemberType();
            obj.setStatus(message);
        end

        function onWasherSpecChanged(obj, which)
            obj.applyWasherSpec(which);
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function applyWasherSpec(obj, which)
            %APPLYWASHERSPEC  Resolve a washer family into its size list.
            %   A family resolves to MANY washers at one bolt size, so this
            %   fills the SIZE picker rather than the geometry; choosing a
            %   size is what fills OD/ID/thickness.
            w = obj.washerGroup(which);
            if isempty(w.Spec)
                return
            end
            spec = string(w.Spec.Value);
            if spec == gui2.JointConfigPage.CustomChoice
                obj.releaseWasherSpec(which, '');
                return
            end

            bolt = obj.selectedBolt();
            if isempty(bolt) || isnan(bolt.NominalDiameter)
                obj.releaseWasherSpec(which, sprintf(['Pick a bolt before ' ...
                    'choosing a washer family - %s resolves by nominal ' ...
                    'diameter.'], spec));
                return
            end

            matches = [];
            try
                matches = obj.State.Library.washersFor(bolt.NominalDiameter, spec);
            catch
                matches = [];
            end
            if isempty(matches)
                obj.releaseWasherSpec(which, sprintf(['No %s washer ' ...
                    'catalogued at %g in nominal - reverted to Custom; ' ...
                    'enter the geometry manually.'], spec, bolt.NominalDiameter));
                return
            end

            labels = cell(1, numel(matches));
            tokens = cell(1, numel(matches));
            for k = 1:numel(matches)
                labels{k} = obj.washerSizeLabel(matches(k));
                tokens{k} = char(matches(k).Key);
            end
            gui2.JointConfigPage.setItemsAndData(w.Size, labels, tokens);
            % Thinnest first, and washersFor sorts ascending - so element 1
            % is the least intrusive default rather than an arbitrary one.
            w.Size.Value = tokens{1};
            obj.fillWasherFromSize(which);
        end

        function onWasherSizeChanged(obj, which)
            obj.fillWasherFromSize(which);
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function fillWasherFromSize(obj, which)
            %FILLWASHERFROMSIZE  The chosen size -> OD, ID, thickness, locked.
            w   = obj.washerGroup(which);
            key = string(w.Size.Value);
            if key == gui2.JointConfigPage.SizeNA || ~obj.State.LibraryOK
                return
            end
            entry = [];
            try
                entry = obj.State.Library.washer(key);
            catch
                entry = [];
            end
            if isempty(entry)
                obj.releaseWasherSpec(which, sprintf( ...
                    'Washer %s is no longer in the library - reverted to Custom.', key));
                return
            end

            w.OD.Value  = obj.fmtOptional(entry.OuterDiameter);
            w.ID.Value  = obj.fmtOptional(entry.InnerDiameter);
            w.Thk.Value = entry.Thickness;
            % Geometry from a catalogue means the washer IS there - ticking
            % Present spares the analyst a step that could only have one
            % answer.
            w.Present.Value = true;
            obj.setWasherLocked(which, true);
            obj.setStatus(sprintf('Washer %s filled the geometry.', entry.Key));
        end

        function reselectNutSpec(obj, member)
            %RESELECTNUTSPEC  Recover the nut family a loaded joint came from.
            %   Same defect and same remedy as reselectWasherSpec:
            %   model.ThreadedMember records the nut's MATERIAL and
            %   ENGAGEMENT LENGTH but not which catalogue nut supplied
            %   them, so a saved-and-reloaded case used to come back on
            %   Custom with the fields unlocked.
            %
            %   No reverse-lookup helper is needed on the library here.
            %   Unlike washers, a nut family resolves to exactly ONE nut at
            %   a given thread size, so re-deriving is just asking each
            %   family what it would have produced and seeing which answer
            %   matches -- nutFor is already that question.
            if isempty(obj.NutSpecDropDown) || ~obj.State.LibraryOK
                return
            end
            if member.Type ~= model.ThreadedMemberType.Nut
                return
            end
            bolt = obj.selectedBolt();
            if isempty(bolt) || isnan(bolt.NominalDiameter) || ...
                    isnan(bolt.ThreadsPerInch) || isnan(member.EngagementLength)
                return
            end

            hit = "";
            try
                specs = obj.State.Library.nutSpecs();
                for s = 1:numel(specs)
                    n = obj.State.Library.nutFor(bolt.NominalDiameter, ...
                        bolt.ThreadsPerInch, specs(s));
                    if isempty(n)
                        continue
                    end
                    % Height AND material, both exact. Height alone would
                    % match two families that happen to share a nut height
                    % but call for different alloys.
                    if abs(n.Height - member.EngagementLength) < 1e-9 && ...
                            strcmp(string(n.Material), member.Material.Name)
                        if strlength(hit) > 0
                            return   % ambiguous: claim nothing
                        end
                        hit = specs(s);
                    end
                end
            catch
                return
            end
            if strlength(hit) == 0
                return
            end

            % Through the normal cascade, so the lock and the material
            % selection are set by the one path that owns them.
            obj.NutSpecDropDown.Value = char(hit);
            obj.applyNutSpec();
            % applyNutSpec reports that it FILLED the fields. Nothing was
            % filled here -- the values were already right and the family
            % was inferred from them, which is a different claim.
            obj.setStatus(sprintf( ...
                'Nut fields match %s — family reselected.', hit));
        end

        function reselectWasherSpec(obj, which, washer)
            %RESELECTWASHERSPEC  Recover the family a loaded washer came from.
            %   model.Washer carries no catalogue key, so the picker cannot
            %   be restored from the file. It CAN be re-derived: ask the
            %   catalogue which part has exactly this geometry at this
            %   bolt's nominal diameter. One hit is enough to name the
            %   family; anything else leaves Custom alone.
            %
            %   Silent on a miss. A loaded case that simply has hand-typed
            %   washer geometry is not a problem to report, and a status
            %   line for every load that isn't catalogue hardware would
            %   train the analyst to ignore the status bar.
            w = obj.washerGroup(which);
            if isempty(w.Spec) || ~obj.State.LibraryOK
                return
            end
            if ~logical(w.Present.Value)
                return   % no washer to identify
            end
            bolt = obj.selectedBolt();
            if isempty(bolt) || isnan(bolt.NominalDiameter)
                return
            end

            hits = [];
            try
                hits = obj.State.Library.washerMatching(bolt.NominalDiameter, ...
                    washer.OuterDiameter, washer.InnerDiameter, washer.Thickness);
            catch
                return
            end
            % Exactly one, or claim nothing: two families sharing a size
            % is a real catalogue state, and picking either would assert a
            % provenance the analyst never chose.
            if numel(hits) ~= 1
                return
            end

            % Route through the normal cascade rather than writing Spec,
            % Size and the lock by hand — applyWasherSpec is what fills the
            % size list, and a second path that populated it here is the
            % kind of duplicate that drifts.
            w.Spec.Value = char(hits(1).Spec);
            obj.applyWasherSpec(which);
            if any(strcmp(w.Size.ItemsData, char(hits(1).Key)))
                w.Size.Value = char(hits(1).Key);
                obj.fillWasherFromSize(which);
            end
            obj.setStatus(sprintf( ...
                '%s washer geometry matches %s — family reselected.', ...
                which, hits(1).Key));
        end

        function releaseWasherSpec(obj, which, message)
            %RELEASEWASHERSPEC  Back to Custom with the geometry editable.
            %   Values are LEFT IN PLACE, never blanked: whatever the
            %   catalogue put there is a reasonable starting point to edit,
            %   and blanking would punish the analyst for changing their
            %   mind (the Same as Head rule, applied here).
            w = obj.washerGroup(which);
            w.Spec.Value = gui2.JointConfigPage.CustomChoice;
            gui2.JointConfigPage.setItemsAndData(w.Size, ...
                {gui2.JointConfigPage.SizeNA}, {gui2.JointConfigPage.SizeNA});
            w.Size.Value = gui2.JointConfigPage.SizeNA;
            obj.setWasherLocked(which, false);
            if ~isempty(message)
                obj.setStatus(message);
            end
        end

        function setWasherLocked(obj, which, tf)
            %SETWASHERLOCKED  Record the lock, then let syncWasherEnables
            %   act on it. Same discipline as NutSpecLocked: the cascade
            %   never writes Enable itself.
            if strcmp(which, 'Head')
                obj.HeadWasher.Locked = tf;
            else
                obj.NutWasher.Locked = tf;
            end
            obj.syncWasherEnables();
        end

        function w = washerGroup(obj, which)
            if strcmp(which, 'Head')
                w = obj.HeadWasher;
            else
                w = obj.NutWasher;
            end
        end

        function b = selectedBolt(obj)
            %SELECTEDBOLT  The library entry, or [] when none is chosen.
            b = [];
            key = obj.selectedKey(obj.BoltDropDown);
            if strlength(key) == 0 || ~obj.State.LibraryOK
                return
            end
            try
                b = obj.State.Library.bolt(key);
            catch
                b = [];
            end
        end

        function s = threadDescription(~, bolt)
            %THREADDESCRIPTION  "0.19 in - 32 TPI", for a status message.
            %   Library bolt KEYS are not parseable thread strings, so the
            %   size is described from the numbers the match was made on.
            s = sprintf('%g in - %g TPI', bolt.NominalDiameter, ...
                bolt.ThreadsPerInch);
        end

        function s = washerSizeLabel(obj, entry) %#ok<INUSL>
            %WASHERSIZELABEL  What distinguishes one match from another.
            %   Thickness, because that is the only thing that varies within
            %   a family at one bolt size - listing the key alone would make
            %   the choice arbitrary.
            if strlength(entry.SizeCode) > 0
                s = sprintf('%s - %.4f in thk', entry.SizeCode, entry.Thickness);
            else
                s = sprintf('%s - %.4f in thk', entry.Key, entry.Thickness);
            end
        end

        function populateSpecPickers(obj)
            %POPULATESPECPICKERS  Family lists, labels shown, tokens stored.
            %   Items carry "<drawing number> - <descriptor>" because the
            %   number is what an analyst cites and the descriptor is what
            %   tells them which part it is. ItemsData carries the bare
            %   token, so Value is what nutFor/washersFor match on and the
            %   composite string never becomes an identity that has to
            %   round-trip.
            if ~obj.State.LibraryOK
                return
            end
            custom = gui2.JointConfigPage.CustomChoice;
            try
                [tok, lab] = obj.State.Library.nutSpecs();
                gui2.JointConfigPage.setItemsAndData(obj.NutSpecDropDown, ...
                    [cellstr(lab), {custom}], [cellstr(tok), {custom}]);
                obj.NutSpecDropDown.Value = custom;
            catch
            end
            try
                [wtok, wlab] = obj.State.Library.washerSpecs();
                for which = {'Head', 'Nut'}
                    w = obj.washerGroup(which{1});
                    gui2.JointConfigPage.setItemsAndData(w.Spec, ...
                        [cellstr(wlab), {custom}], [cellstr(wtok), {custom}]);
                    w.Spec.Value = custom;
                end
            catch
            end
        end

        function resetSpecPickers(obj)
            %RESETSPECPICKERS  Back to Custom, unlocked, on an external load.
            %   The pickers are PAGE state, not case state: model.Joint
            %   records the resolved numbers, not which family produced
            %   them. A loaded case defines its washers and nut explicitly,
            %   so a picker left claiming ownership would be asserting a
            %   provenance the file never carried.
            if isempty(obj.NutSpecDropDown)
                return
            end
            obj.NutSpecDropDown.Value = gui2.JointConfigPage.CustomChoice;
            obj.NutSpecLocked = false;
            % syncMemberType is what turns the cleared flag into enable
            % state; refresh() ran it before this point, when the flag was
            % still set.
            obj.syncMemberType();
            obj.releaseWasherSpec('Head', '');
            obj.releaseWasherSpec('Nut',  '');
        end

        function syncMemberType(obj)
            %SYNCMEMBERTYPE  Label the material for its role, and enable the
            %   engagement control this type actually uses.
            %
            %   NEVER TOUCHES EITHER ENGAGEMENT VALUE. Each control owns its
            %   own property, so nothing has to be cleared on a type change
            %   and loading a case cannot wipe the number it just loaded.
            if isempty(obj.MemberTypeDropDown)
                return
            end
            t = obj.selectedMemberType();

            % model.ThreadedMemberType has exactly THREE members - Nut,
            % Insert, TappedHole. There is no None: a joint always threads
            % into something. The reverted build had a `case
            % model.ThreadedMemberType.None` here, which threw on every
            % switch to Insert or Tapped Hole because MATLAB evaluates a
            % case expression only when it is reached.
            if t == model.ThreadedMemberType.Nut
                obj.MemberMaterialLabel.Text = 'Nut material';
            else
                obj.MemberMaterialLabel.Text = 'Parent (host) material';
            end

            isInsert = (t == model.ThreadedMemberType.Insert);
            states   = {'off', 'on'};

            % SOLE OWNER of both engagement controls' Enable, and of the
            % member material's. A resolved nut family locks the inches
            % engagement and the material, but it does so by setting
            % NutSpecLocked and calling here - never by writing Enable
            % itself, which would race this method (A5).
            ratioOn  = isInsert;
            inchesOn = ~isInsert && ~obj.NutSpecLocked;

            obj.EngagementRatioField.Enable  = states{ratioOn + 1};
            obj.EngagementLengthField.Enable = states{inchesOn + 1};
            obj.EngagementRatioLabel.FontColor  = obj.enabledColor(ratioOn);
            obj.EngagementLengthLabel.FontColor = obj.enabledColor(inchesOn);

            obj.MemberMaterialDropDown.Enable = states{~obj.NutSpecLocked + 1};

            % The picker itself is meaningful for a Nut and nothing else.
            if ~isempty(obj.NutSpecDropDown)
                isNut = (t == model.ThreadedMemberType.Nut);
                obj.NutSpecDropDown.Enable = states{isNut + 1};
            end
        end

        function c = enabledColor(~, tf)
            if tf
                c = gui2.palette('defaultText');
            else
                c = gui2.palette('mutedText');
            end
        end

        function t = selectedMemberType(obj)
            t = gui2.JointConfigPage.memberTypeFromLabel( ...
                obj.MemberTypeDropDown.Value);
        end

        function missing = missingRequired(obj)
            %MISSINGREQUIRED  The selections Analyze cannot run without.
            %   THIS IS THE ONLY GATE. buildJoint deliberately marshals an
            %   incomplete form without complaint, because an incomplete
            %   form is the normal state while working. Completeness is
            %   enforced here, on the path where the answer has to be
            %   trustworthy - not on every keystroke.
            missing = string.empty(1, 0);
            if strlength(obj.selectedKey(obj.BoltDropDown)) == 0
                missing(end + 1) = "Bolt"; %#ok<AGROW>
            end
            if strlength(obj.selectedKey(obj.BoltMaterialDropDown)) == 0
                missing(end + 1) = "Bolt material"; %#ok<AGROW>
            end
            if strlength(obj.selectedKey(obj.MemberMaterialDropDown)) == 0
                missing(end + 1) = string(obj.MemberMaterialLabel.Text); %#ok<AGROW>
            end
            % Flange material is required only for a row actually in the
            % stack - a row with no thickness is not part of this joint.
            anyLayer = false;
            for i = 1:gui2.JointConfigPage.MaxFlangeLayers
                if obj.parsePositive(obj.FlangeThickness{i}) > 0
                    anyLayer = true;
                    if strlength(obj.selectedKey(obj.FlangeMaterial{i})) == 0
                        missing(end + 1) = sprintf("Flange layer %d material", i); %#ok<AGROW>
                    end
                end
            end

            % THE GATE NOW MATCHES WHAT THE ENGINE NEEDS, which it did not
            % before: hardware alone let Analyze enable, and the run then
            % came back with every margin NotEvaluated. A button that
            % promises an answer and delivers a page of dashes is worse
            % than one that says what is missing.
            %
            % Each of these three makes the analysis undefined rather than
            % merely trivial:
            if ~anyLayer
                % No clamped stack means no grip, and grip is upstream of
                % stiffness, preload and separation alike.
                missing(end + 1) = "A flange layer thickness"; %#ok<AGROW>
            end
            if isnan(obj.parsePositive(obj.NominalTorqueField))
                % Every NASA-STD-5020B check is written in terms of the
                % preload band. This page is torque-control only, so the
                % nominal torque IS the preload input.
                missing(end + 1) = "Nominal torque"; %#ok<AGROW>
            end
            if ~obj.anyAppliedLoad()
                % Margins are computed AGAINST applied loads. With none,
                % every ratio is zero and every margin is infinite -- a
                % result with no engineering content, reported as if it
                % had some.
                missing(end + 1) = "At least one applied limit load"; %#ok<AGROW>
            end
        end

        function tf = anyAppliedLoad(obj)
            %ANYAPPLIEDLOAD  Is a single limit load supplied anywhere?
            %   The joint-level pair counts even while hidden: visibility
            %   follows the slip mode, and a value already typed is still
            %   part of the case.
            fields = {obj.BoltTensileField, obj.BoltShearField, ...
                      obj.JointTensileField, obj.JointShearField};
            tf = false;
            for i = 1:numel(fields)
                if ~isempty(fields{i}) && ~isnan(obj.parseOptional(fields{i}))
                    tf = true;
                    return
                end
            end
        end

        function validateRequired(obj)
            %VALIDATEREQUIRED  Sole owner of AnalyzeButton.Enable.
            %   Two independent disable reasons, and they must not clobber
            %   each other: an unavailable library is reported on its own
            %   and returns, rather than falling through into the
            %   required-field branch and overwriting its message.
            if isempty(obj.AnalyzeButton)
                return
            end
            if ~obj.State.LibraryOK
                obj.AnalyzeButton.Enable = 'off';
                obj.RequiredLabel.Text = ['Hardware library not loaded - ' ...
                    'nothing can be analysed until that is fixed.'];
                return
            end
            missing = obj.missingRequired();
            if isempty(missing)
                obj.AnalyzeButton.Enable = 'on';
                obj.RequiredLabel.Text   = '';
            else
                obj.AnalyzeButton.Enable = 'off';
                obj.RequiredLabel.Text = sprintf('Required before Analyze: %s.', ...
                    strjoin(cellstr(missing), ', '));
            end
        end

        function onAnalyze(obj)
            %ONANALYZE  Marshal, run the engine, hand the Result to AppState.
            %   Its own try/catch, inside its own callback: an outer one
            %   around construction catches nothing thrown from the event
            %   loop (GUI2_SPEC.md Section 11).
            try
                r = engine.analyze(obj.buildJoint(), obj.buildLoadCase(), ...
                    obj.State.Factors);
            catch err
                % A failed run must not leave a confident verdict on
                % screen. Flag the previous result stale rather than
                % clearing it or replacing it (A3). ResultStale is
                % read-only from outside AppState - markResultStale is the
                % supported route, and it no-ops when there is no result
                % to go stale.
                obj.State.markResultStale();
                uialert(ancestor(obj.Root, 'figure'), err.message, ...
                    'Analysis failed');
                return
            end
            obj.State.setResult(r);
            % Section 8.3: the answer is on another page, so go there. An
            % analyst should never have to find the result they just asked
            % for.
            obj.goToPage("Results");
            obj.setStatus(sprintf('Analyzed "%s".', ...
                gui2.JointConfigPage.orPlaceholder(obj.State.Joint.Name, ...
                                                   'untitled joint')));
        end

        function onSaveJoint(obj)
            %ONSAVEJOINT  Store this joint in the defined-joints library.
            name = strtrim(string(obj.JointNameField.Value));
            fig  = ancestor(obj.Root, 'figure');
            if strlength(name) == 0
                uialert(fig, ['Enter a joint name before saving - the ' ...
                    'library is keyed by it.'], 'Cannot save joint');
                return
            end

            % Case-INSENSITIVE collision: letting "JT-A" and "jt-a" coexist
            % is a mapping trap (A13), because element mapping keys on the
            % name and would silently reference the wrong joint.
            lib = obj.State.JointLibrary;
            idx = find(strcmpi(string({lib.Name}), name), 1);
            if isempty(idx)
                obj.commitSavedJoint(name, []);
                return
            end

            % CloseFcn form, NOT the blocking one. uiconfirm with a return
            % value halts execution inside the callback until a human
            % answers - which deadlocks any programmatic driver, including
            % the App Testing Framework: the test cannot reach its
            % chooseDialog because the press that opened the dialog has
            % never returned. The callback form returns immediately and
            % delivers the answer through the event.
            uiconfirm(fig, sprintf( ...
                ['A joint named "%s" is already in the library. ' ...
                 'Overwrite it?'], lib(idx).Name), 'Overwrite joint', ...
                'Options',       {'Overwrite', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.onOverwriteAnswered(name, idx, evt));
        end

        function onOverwriteAnswered(obj, name, idx, evt)
            %ONOVERWRITEANSWERED  The overwrite dialog's reply.
            if ~strcmp(evt.SelectedOption, 'Overwrite')
                return
            end
            obj.commitSavedJoint(name, idx);
        end

        function commitSavedJoint(obj, name, idx)
            %COMMITSAVEDJOINT  Write the joint into the library.
            %   idx empty = append; otherwise overwrite that entry.
            lib = obj.State.JointLibrary;
            if isempty(idx)
                lib(end + 1) = struct('Name', name, 'Joint', obj.buildJoint());
                verb = 'Added';
            else
                lib(idx).Name  = name;
                lib(idx).Joint = obj.buildJoint();
                verb = 'Updated';
            end
            obj.State.JointLibrary = lib;
            obj.State.markDirty();
            obj.setStatus(sprintf('%s joint "%s" in the defined-joints library.', ...
                verb, name));
        end

        function onSlipModeChanged(obj)
            obj.syncJointLoadVisibility();
            obj.commitJoint();
        end

        function syncJointLoadVisibility(obj)
            %SYNCJOINTLOADVISIBILITY  Joint totals appear only in joint mode.
            %   5020B Eq. 84 needs them; the single-fastener default
            %   (Eq. 86) does not, and showing them always is what made
            %   them read as required.
            if isempty(obj.SlipModeDropDown)
                return
            end
            isJoint = gui2.JointConfigPage.enumFromLabel('model.SlipMode', ...
                obj.SlipModeDropDown.Value) == model.SlipMode.Joint;
            vis = {'off', 'on'};
            for h = {obj.JointTensileField, obj.JointTensileLabel, ...
                     obj.JointShearField, obj.JointShearLabel}
                h{1}.Visible = vis{isJoint + 1};
            end
        end

        function onEngagementEdited(obj)
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onBoltLengthEdited(obj)
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function onBodyLengthEdited(obj)
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function updateBoltLengthChoices(obj)
            %UPDATEBOLTLENGTHCHOICES  The selected bolt's Table III ladder.
            %   THE VALUE IS PRESERVED ACROSS THE REBUILD. Changing bolts
            %   changes which lengths are catalogued, but it does not
            %   retract the length the analyst asked for: a 1.000 in screw
            %   is still 1.000 in after switching from UNF to UNC, and
            %   silently blanking it would look like the tool deciding.
            %   An editable dropdown accepts a Value outside its Items,
            %   which is what makes that possible.
            %
            %   An uncatalogued bolt -- a custom entry, or one predating
            %   the lengths schema -- leaves just the blank item, so the
            %   control degrades to plain manual entry rather than looking
            %   broken (data.Library.boltLengths returns empty by design).
            if isempty(obj.BoltLengthField)
                return
            end
            items = {gui2.JointConfigPage.BlankChoice};
            key   = obj.selectedKey(obj.BoltDropDown);
            if strlength(key) > 0 && obj.State.LibraryOK
                try
                    L = obj.State.Library.boltLengths(key);
                    items = [items, ...
                        arrayfun(@(x) sprintf('%g', x), L, 'UniformOutput', false)];
                catch
                end
            end
            kept = gui2.JointConfigPage.lengthChoice( ...
                str2double(strtrim(string(obj.BoltLengthField.Value))));
            obj.BoltLengthField.Items = items;
            obj.BoltLengthField.Value = kept;
        end

        function updateBoltLengthLabel(obj)
            %UPDATEBOLTLENGTHLABEL  Four lines from engine.boltLengthCheck.
            %   ALL arithmetic is the engine's; this formats the struct and
            %   nothing more. boltLengthCheck is a pure query that never
            %   throws and degrades any missing input to NaN, which is why
            %   it can be called on a half-filled form.
            %
            %   Three states, and the middle one is the point (A1): when the
            %   check CANNOT RUN it is amber, not muted grey. The check is
            %   not running, and that must never read as nothing to report.
            if isempty(obj.BoltLengthLabel)
                return
            end
            j = obj.buildJoint();
            r = engine.boltLengthCheck(j);

            lines = { ...
                gui2.JointConfigPage.lineOrDash('Grip (stack + washers): %.4f in', ...
                    r.GripLength, 'Grip (stack + washers): —'), ...
                gui2.JointConfigPage.lineOrDash('Engagement Le: %.4f in', ...
                    r.Engagement, 'Engagement Le: —'), ...
                gui2.JointConfigPage.lineOrDash('Minimum bolt length: %.4f in', ...
                    r.RequiredLength, 'Minimum bolt length: —')};

            if ~r.Evaluated
                % Named cause, not a bare dash: the analyst needs to know
                % WHICH input is missing to act on it.
                lines{4} = sprintf('Not evaluated — %s', char(r.Detail));
                obj.BoltLengthLabel.FontColor  = gui2.palette('statusWarn');
                obj.BoltLengthLabel.FontWeight = 'normal';
            elseif r.Shortfall > 0
                lines{4} = sprintf('Selected %.4f in — TOO SHORT by %.4f in', ...
                    r.SuppliedLength, r.Shortfall);
                obj.BoltLengthLabel.FontColor  = gui2.palette('statusFail');
                obj.BoltLengthLabel.FontWeight = 'bold';
            else
                lines{4} = sprintf('Selected %.4f in — OK', r.SuppliedLength);
                obj.BoltLengthLabel.FontColor  = gui2.palette('mutedText');
                obj.BoltLengthLabel.FontWeight = 'normal';
            end

            % L1 IS THE LINE THAT PREDICTS WHETHER MARGINS WILL EVALUATE.
            % engine.stiffness needs it for phi, and phi is what the
            % tension checks need; without it Tension-Ultimate and -Yield
            % come back NotEvaluated with the reason buried in the Results
            % detail. Reporting it HERE says so before Analyze is pressed,
            % which is where the analyst can still do something about it.
            [l1Text, l1Missing] = obj.bodyLengthLine(j);
            lines{5} = l1Text;
            if l1Missing && ~(r.Evaluated && r.Shortfall > 0)
                % Amber unless the shortfall red is already the louder
                % problem — never demote a failure to a warning.
                obj.BoltLengthLabel.FontColor = gui2.palette('statusWarn');
            end
            obj.BoltLengthLabel.Text = lines;
        end

        function [text, missing] = bodyLengthLine(obj, j)
            %BODYLENGTHLINE  What L1 the stiffness model will actually use.
            %   NOTHING IS COMPUTED HERE. engine.stiffness returns the L1
            %   it resolved, through its own three-level precedence
            %   (explicit override, then Bolt.Length − ThreadLength, then
            %   the NASA-STD-5020B 4.7.4 estimate). Re-deriving any of that
            %   in the page would be a second implementation that could
            %   disagree with the one doing the analysis.
            missing = false;
            s = [];
            try
                s = engine.stiffness(j);
            catch
                % stiffness throws when it cannot resolve L1 at all -- the
                % one case worth saying out loud.
            end
            if isempty(s) || isnan(s.L1)
                missing = true;
                text = ['Body length L1: — stiffness cannot run, so the ' ...
                        'tension checks will report not evaluated. Supply ' ...
                        'a bolt length, a nut engagement, or L1 itself.'];
                return
            end
            if ~isnan(j.BodyLengthInGrip)
                text = sprintf('Body length L1: %.4f in — your override', s.L1);
            else
                text = sprintf(['Body length L1: %.4f in — derived from ' ...
                                'the bolt and its catalogue thread length'], s.L1);
            end
        end

        function onFlangeEdited(obj)
            obj.updateGripLabel();
            obj.updateBoltLengthLabel();
            obj.commitJoint();
        end

        function updateGripLabel(obj)
            %UPDATEGRIPLABEL  Grip length, or the honest unknown.
            %   A1: an empty stack must NOT render as "0 in". That states a
            %   grip the joint does not have, at exactly the moment an
            %   analyst is part-way through entering one.
            if isempty(obj.GripLabel)
                return
            end
            layers = obj.collectFlangeLayers();
            if isempty(layers)
                obj.GripLabel.Text = 'Grip length: — (no active layer with a thickness)';
                obj.GripLabel.FontColor = gui2.palette('mutedText');
                return
            end
            probe = model.Joint(FlangeStack = layers);
            obj.GripLabel.Text = sprintf('Grip length: %.4f in', probe.GripLength);
            obj.GripLabel.FontColor = gui2.palette('defaultText');
        end

        function m = lookupMaterial(obj, dd)
            m = model.Material();
            key = obj.selectedKey(dd);
            if strlength(key) == 0 || ~obj.State.LibraryOK
                return
            end
            try
                m = obj.State.Library.material(key);
            catch
            end
        end

        function b = lookupBolt(obj)
            b = model.Bolt();
            key = obj.selectedKey(obj.BoltDropDown);
            if strlength(key) > 0 && obj.State.LibraryOK
                try
                    b = obj.State.Library.bolt(key);
                catch
                    % A key that vanished from the library marshals as the
                    % default rather than taking the whole commit down.
                end
            end
            % Overall length is joint-specific, not a property of the
            % catalogue entry, so it comes from the form either way.
            % parsePositive, not parseOptional: Bolt.Length is
            % mustBePositiveOrNaN, so a typed zero would throw and abort
            % the commit.
            if ~isempty(obj.BoltLengthField)
                b.Length = obj.parsePositive(obj.BoltLengthField);
            end
        end

        function m = lookupBoltMaterial(obj)
            m = model.Material();
            key = obj.selectedKey(obj.BoltMaterialDropDown);
            if strlength(key) == 0 || ~obj.State.LibraryOK
                return
            end
            try
                m = obj.State.Library.material(key);
            catch
            end
        end

        function clearRefreshing(obj)
            obj.Refreshing = false;
        end
    end

    % ---- Small helpers ----------------------------------------------------
    methods (Access = private)
        function v = parseOptional(~, field)
            %PARSEOPTIONAL  Text field -> double. Blank or junk -> NaN.
            %   NaN is the model's "not supplied", and the engine reports
            %   the checks that need it as not evaluated. A typo must never
            %   take a whole commit down (buildJoint is total).
            v = str2double(strtrim(string(field.Value)));
        end

        function v = parsePositive(obj, field)
            %PARSEPOSITIVE  Text field -> a POSITIVE double, or NaN.
            %   model.Washer's OD and ID are mustBePositiveOrNaN, so a typed
            %   zero or a negative would THROW and abort the commit - which
            %   would break the guarantee that buildJoint is total. Anything
            %   that is not positive becomes NaN, the model's "not supplied".
            v = obj.parseOptional(field);
            if ~(v > 0)
                v = NaN;
            end
        end

        function s = fmtOptional(~, v)
            %FMTOPTIONAL  Double -> text field. NaN renders blank.
            if isnan(v)
                s = '';
            else
                s = sprintf('%g', v);
            end
        end

        function k = selectedKey(~, dd)
            %SELECTEDKEY  "" when the blank sentinel is showing.
            k = strtrim(string(dd.Value));
        end

        function tf = trySelectKey(obj, dd, value)
            %TRYSELECTKEY  trySelect, but reports whether it landed.
            %   The cascade needs to know: a nut naming a material the
            %   library lacks must release the lock rather than silently
            %   leave the dropdown blank AND locked.
            obj.trySelect(dd, value);
            tf = strlength(obj.selectedKey(dd)) > 0;
        end

        function trySelect(obj, dd, value)
            %TRYSELECT  Select `value` if the list has it, else the blank.
            %   Never errors, and never silently lands on a neighbour: a
            %   value the library no longer carries falls back to BLANK, so
            %   it reads as "choose one" rather than as a real selection.
            want = char(strtrim(string(value)));
            if ~isempty(want) && any(strcmp(dd.Items, want))
                dd.Value = want;
            else
                dd.Value = gui2.JointConfigPage.BlankChoice;
            end
        end
    end

    % ---- Member type labels -----------------------------------------------
    methods (Static, Access = private)
        function setItemsAndData(dd, labels, tokens)
            %SETITEMSANDDATA  Repopulate a picker, preserving the selection.
            %   ItemsData is CLEARED FIRST. Assigning Items while ItemsData
            %   is non-empty and a different length resizes them
            %   inconsistently (A5), and the two must always agree.
            %
            %   The current selection survives if the new list still offers
            %   it - a library refresh must not silently move the analyst
            %   onto a different part.
            want = '';
            if ~isempty(dd.ItemsData)
                want = char(string(dd.Value));
            end
            dd.ItemsData = {};
            dd.Items     = labels;
            dd.ItemsData = tokens;
            if ~isempty(want) && any(strcmp(tokens, want))
                dd.Value = want;
            else
                dd.Value = tokens{1};
            end
        end

        function items = enumItems(enumClass)
            %ENUMITEMS  Enum member names as dropdown items, in order.
            members = enumeration(enumClass);
            items = cellstr(string(members(:)'));
        end

        function m = enumFromLabel(enumClass, label)
            %ENUMFROMLABEL  Item text -> enum member, via the ENUMERATION.
            %   Never a string comparison against a hard-coded member name
            %   (GUI2_HARVEST.md C1). An unrecognised label falls back to
            %   the first member rather than throwing, keeping buildJoint
            %   total.
            members = enumeration(enumClass);
            idx = find(string(members) == strtrim(string(label)), 1);
            if isempty(idx)
                m = members(1);
            else
                m = members(idx);
            end
        end

        function s = orPlaceholder(value, placeholder)
            %ORPLACEHOLDER  A non-empty string, or a stated stand-in.
            s = char(strtrim(string(value)));
            if isempty(s)
                s = placeholder;
            end
        end

        function s = lengthChoice(v)
            %LENGTHCHOICE  A bolt length as the picker's Value.
            %   NaN lands on BlankChoice rather than on '' — the blank
            %   ITEM is a single space, so an empty string would sit
            %   outside the list looking identical to it while behaving
            %   differently. Both parse back to NaN.
            if isnan(v)
                s = gui2.JointConfigPage.BlankChoice;
            else
                s = sprintf('%g', v);
            end
        end

        function s = lineOrDash(fmt, v, dashText)
            %LINEORDASH  A formatted line, or the em-dash unknown (A1).
            if isnan(v)
                s = dashText;
            else
                s = sprintf(fmt, v);
            end
        end

        function items = memberTypeItems()
            %MEMBERTYPEITEMS  Display labels, in enumeration order.
            members = enumeration('model.ThreadedMemberType');
            items = cell(1, numel(members));
            for i = 1:numel(members)
                items{i} = gui2.JointConfigPage.memberTypeLabel(members(i));
            end
        end

        function s = memberTypeLabel(t)
            %MEMBERTYPELABEL  Enum -> display label. Display only.
            if t == model.ThreadedMemberType.Insert
                s = 'Helical Insert';
            elseif t == model.ThreadedMemberType.TappedHole
                s = 'Tapped Hole';
            else
                s = char(string(t));
            end
        end

        function t = memberTypeFromLabel(txt)
            %MEMBERTYPEFROMLABEL  Label -> enum, resolved through the
            %   ENUMERATION rather than by string equality against member
            %   names. GUI2_HARVEST.md C1 records the bug that came from
            %   comparing against 'TappedHole', which could never match, so
            %   the member silently behaved as bolt-only.
            want = strtrim(char(string(txt)));
            members = enumeration('model.ThreadedMemberType');
            for i = 1:numel(members)
                if strcmp(gui2.JointConfigPage.memberTypeLabel(members(i)), want)
                    t = members(i);
                    return
                end
            end
            t = model.ThreadedMemberType.Nut;
        end
    end

    % ---- Test seams -------------------------------------------------------
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

        function f = boltCountField(obj)
            f = obj.BoltCountField;
        end

        function d = flangeMaterial(obj, i)
            d = obj.FlangeMaterial{i};
        end

        function f = flangeThickness(obj, i)
            f = obj.FlangeThickness{i};
        end

        function f = flangeEdge(obj, i)
            f = obj.FlangeEdge{i};
        end

        function l = gripLabel(obj)
            l = obj.GripLabel;
        end

        function w = headWasher(obj)
            w = obj.HeadWasher;
        end

        function w = nutWasher(obj)
            w = obj.NutWasher;
        end

        function c = sameAsHeadCheck(obj)
            c = obj.SameAsHeadCheck;
        end

        function d = memberTypeDropDown(obj)
            d = obj.MemberTypeDropDown;
        end

        function d = memberMaterialDropDown(obj)
            d = obj.MemberMaterialDropDown;
        end

        function d = nutSpecDropDown(obj)
            d = obj.NutSpecDropDown;
        end

        function l = memberMaterialLabel(obj)
            l = obj.MemberMaterialLabel;
        end

        function f = engagementRatioField(obj)
            f = obj.EngagementRatioField;
        end

        function f = engagementLengthField(obj)
            f = obj.EngagementLengthField;
        end

        function f = boltLengthField(obj)
            f = obj.BoltLengthField;
        end

        function l = boltLengthLabel(obj)
            l = obj.BoltLengthLabel;
        end

        function f = bodyLengthField(obj)
            f = obj.BodyLengthField;
        end

        function f = ratedUltField(obj)
            f = obj.RatedUltField;
        end

        function f = frustumAngleField(obj)
            f = obj.FrustumAngleField;
        end

        function f = nominalTorqueField(obj)
            f = obj.NominalTorqueField;
        end

        function f = nutFactorField(obj)
            f = obj.NutFactorField;
        end

        function c = separationCriticalCheck(obj)
            c = obj.SeparationCriticalCheck;
        end

        function f = boltTensileField(obj)
            f = obj.BoltTensileField;
        end

        function f = boltShearField(obj)
            f = obj.BoltShearField;
        end

        function f = jointTensileField(obj)
            f = obj.JointTensileField;
        end

        function d = slipModeDropDown(obj)
            d = obj.SlipModeDropDown;
        end

        function d = shearPlaneDropDown(obj)
            d = obj.ShearPlaneDropDown;
        end

        function d = boltAxisDropDown(obj)
            d = obj.BoltAxisDropDown;
        end

        function b = analyzeButton(obj)
            b = obj.AnalyzeButton;
        end

        function b = saveJointButton(obj)
            b = obj.SaveJointButton;
        end

        function l = requiredLabel(obj)
            l = obj.RequiredLabel;
        end
    end
end
