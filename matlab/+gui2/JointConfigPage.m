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

        LabelW = 150
        ValueW = 150

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

        MemberTypeDropDown
        MemberMaterialDropDown
        MemberMaterialLabel
        EngagementRatioField
        EngagementRatioLabel
        EngagementLengthField
        EngagementLengthLabel

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
            % 2/3 : 1/3. The left column carries the physical stack; the
            % right takes loads and assumptions from step 5. It is declared
            % now so later increments add groups rather than restructure.
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

            right = uigridlayout(g, [3 1]);
            right.Layout.Row    = 2;
            right.Layout.Column = 2;
            right.ColumnWidth   = {'1x'};
            right.RowHeight     = repmat({'fit'}, 1, 3);
            right.Padding       = [0 0 0 0];
            right.RowSpacing    = 8;

            obj.buildPreloadGroup(right, 1);
            obj.buildLoadsGroup(right, 2);
            obj.buildAssumptionsGroup(right, 3);
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

            obj.BoltLengthField.Value  = obj.fmtOptional(j.Bolt.Length);
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

            % Same as Head is PAGE state, not case state: model.Joint holds
            % the two washers independently, so a loaded case defines both
            % explicitly. Untick on an external load rather than let a
            % mirrored view claim values the file never carried.
            obj.SameAsHeadCheck.Value = false;
            obj.applyWasher(obj.HeadWasher, j.HeadWasher);
            obj.applyWasher(obj.NutWasher,  j.NutWasher);
            obj.syncWasherEnables();
        end
    end

    % ---- Layout -----------------------------------------------------------
    methods (Access = private)
        function buildBoltGroup(obj, parent, row)
            panel = uipanel(parent, 'Title', 'Bolt');
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
            obj.JointNameField = uieditfield(b, 'text');
            obj.JointNameField.Layout.Row    = 1;
            obj.JointNameField.Layout.Column = [2 3];
            lb = uilabel(b, 'Text', 'Joint name');
            lb.Layout.Row = 1; lb.Layout.Column = 1;
            obj.bindEdit(obj.JointNameField, @(~, ~) obj.commitJoint());

            obj.BoltDropDown = obj.addDropdown(b, 2, 'Bolt', ...
                obj.libraryItems('bolt'), ...
                'Fastener from the hardware library. Required.');
            obj.bindEdit(obj.BoltDropDown, @(~, ~) obj.commitJoint());

            obj.BoltMaterialDropDown = obj.addDropdown(b, 3, 'Bolt material', ...
                obj.libraryItems('boltMaterial'), ...
                'Bolt material from the hardware library. Required.');
            obj.bindEdit(obj.BoltMaterialDropDown, @(~, ~) obj.commitJoint());

            obj.BoltCountField = obj.addNumeric(b, 4, 'Bolt count nf', ...
                'Number of fasteners in the pattern.');
            obj.BoltCountField.Limits = [1 Inf];
            obj.BoltCountField.RoundFractionalValues = 'on';
            obj.BoltCountField.Value = 1;
            obj.bindEdit(obj.BoltCountField, @(~, ~) obj.commitJoint());
        end

        function buildFlangeGroup(obj, parent, row)
            panel = uipanel(parent, 'Title', 'Flange stack (clamped layers)');
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

                obj.FlangeName{i} = uieditfield(fg, 'text', 'Tooltip', tips{2});
                obj.FlangeName{i}.Layout.Row = r;
                obj.FlangeName{i}.Layout.Column = 2;
                obj.bindEdit(obj.FlangeName{i}, @(~, ~) obj.commitJoint());

                obj.FlangeMaterial{i} = uidropdown(fg, 'Items', mats, ...
                    'Value', gui2.JointConfigPage.BlankChoice, 'Tooltip', tips{3});
                obj.FlangeMaterial{i}.Layout.Row = r;
                obj.FlangeMaterial{i}.Layout.Column = 3;
                obj.bindEdit(obj.FlangeMaterial{i}, @(~, ~) obj.onFlangeEdited());

                obj.FlangeThickness{i} = uieditfield(fg, 'numeric', ...
                    'Limits', [0 Inf], 'Tooltip', tips{4});
                obj.FlangeThickness{i}.ValueDisplayFormat = '%.5f';
                obj.FlangeThickness{i}.Layout.Row = r;
                obj.FlangeThickness{i}.Layout.Column = 4;
                obj.bindEdit(obj.FlangeThickness{i}, @(~, ~) obj.onFlangeEdited());

                obj.FlangeHole{i} = uieditfield(fg, 'text', 'Tooltip', tips{5});
                obj.FlangeHole{i}.Layout.Row = r;
                obj.FlangeHole{i}.Layout.Column = 5;
                obj.bindEdit(obj.FlangeHole{i}, @(~, ~) obj.commitJoint());

                obj.FlangeEdge{i} = uieditfield(fg, 'text', 'Tooltip', tips{6});
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
            panel = uipanel(parent, 'Title', titleText);
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            nRows = 5 + double(withSameAsHead);
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
            w.Present.Layout.Row = r; w.Present.Layout.Column = [1 3];
            obj.bindEdit(w.Present, @(~, ~) obj.onWasherPresentToggled());

            if withSameAsHead
                r = r + 1;
                obj.SameAsHeadCheck = uicheckbox(b, 'Text', 'Same as Head', ...
                    'Value', false, 'Tooltip', ...
                    ['Mirror the head washer live - material, OD, ID and ' ...
                     'thickness - and grey this group. Unticking KEEPS the ' ...
                     'mirrored values and re-enables editing; it never ' ...
                     'blanks them.']);
                obj.SameAsHeadCheck.Layout.Row = r;
                obj.SameAsHeadCheck.Layout.Column = [1 3];
                obj.bindEdit(obj.SameAsHeadCheck, @(~, ~) obj.onSameAsHeadToggled());
            end

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
            % and the nut group cannot.
            if withSameAsHead
                cb = @(~, ~) obj.onNutWasherEdited();
            else
                cb = @(~, ~) obj.onHeadWasherEdited();
            end
            obj.bindEdit(w.Material, cb);
            obj.bindEdit(w.OD,       cb);
            obj.bindEdit(w.ID,       cb);
            obj.bindEdit(w.Thk,      cb);
        end

        function buildMemberGroup(obj, parent, row)
            panel = uipanel(parent, 'Title', 'Threaded member');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [4 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = repmat({'fit'}, 1, 4);
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

            [obj.MemberMaterialDropDown, obj.MemberMaterialLabel] = ...
                obj.addDropdown(b, 2, 'Nut material', ...
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
                obj.addLabelledText(b, 3, 'Engagement (x bolt D)', ...
                    ['Thread engagement as a MULTIPLE OF THE BOLT NOMINAL ' ...
                     'DIAMETER, e.g. 1.5 for 1.5D. Helical inserts are ' ...
                     'specified by length CLASS, not an absolute inch ' ...
                     'value (NASM33537 Rev 4 Sec 6.1). Helical Insert only.']);
            obj.bindEdit(obj.EngagementRatioField, @(~, ~) obj.commitJoint());

            [obj.EngagementLengthField, obj.EngagementLengthLabel] = ...
                obj.addLabelledText(b, 4, 'Engagement length Le (in)', ...
                    ['Thread engagement in INCHES - nut thread height, or ' ...
                     'tapped-hole engagement depth. Nut and Tapped Hole ' ...
                     'only. Blank leaves the thread checks not evaluated.']);
            obj.bindEdit(obj.EngagementLengthField, @(~, ~) obj.commitJoint());
        end

        function [c, lb] = addLabelledText(obj, g, row, labelText, tip)
            lb = uilabel(g, 'Text', labelText, 'Tooltip', tip);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            c = uieditfield(g, 'text', 'Tooltip', tip);
            c.Layout.Row = row; c.Layout.Column = 2;
        end

        function buildBoltLengthGroup(obj, parent, row)
            %BUILDBOLTLENGTHGROUP  Overall bolt length, and whether it fits.
            %   LAST in the left column, and deliberately so: the adequacy
            %   readout depends on the flange stack, BOTH washers and the
            %   threaded member's engagement, so it has to sit below every
            %   input it consumes. The first build put a readout above two
            %   of its own inputs.
            panel = uipanel(parent, 'Title', 'Bolt length');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [2 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = {'fit', 'fit'};
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            [obj.BoltLengthField, ~] = obj.addLabelledText(b, 1, ...
                'Overall bolt length (in)', ...
                ['OVERALL length, under-head to tip - not the thread ' ...
                 'length and not L1. Blank leaves the engine to estimate ' ...
                 'it as grip + nut height + 2*pitch (NASA-STD-5020B ' ...
                 '4.7.4), and the readout below reports "not evaluated".']);
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
            panel = uipanel(parent, 'Title', 'Advanced / overrides');
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            b = uigridlayout(panel, [4 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
            b.RowHeight   = repmat({'fit'}, 1, 4);
            b.RowSpacing  = 4;
            b.Padding     = [6 6 6 6];

            % L1 CANNOT be made automatic, despite the spec's first draft
            % saying so. engine.stiffness derives it from
            % Bolt.Length - Bolt.ThreadLength, and NO seeded bolt carries a
            % thread length: it is a per-part property that varies with the
            % ordered length, so it cannot live in a catalogue keyed by
            % thread size. Deriving it would need per-part-number library
            % entries (GUI2_SPEC.md 7.2d).
            obj.BodyLengthField = obj.addLabelledText(b, 1, ...
                'Unthreaded body length L1 (in)', ...
                ['L1 - the UNTHREADED shank length inside the clamp, used ' ...
                 'for bolt stiffness. NOT the bolt length and NOT the ' ...
                 'thread length. Required for stiffness: catalogue bolts ' ...
                 'carry no thread length, so it cannot be derived.']);
            obj.bindEdit(obj.BodyLengthField, @(~, ~) obj.commitJoint());

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
            panel = uipanel(parent, 'Title', 'Preload (torque-controlled)');
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
            obj.TorqueTolField = obj.addNumeric(b, 2, 'Torque tolerance (frac)', ...
                'Fractional torque tolerance: 0.10 means +/-10%.');
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

            obj.UncertaintyField = obj.addNumeric(b, 4, 'Uncertainty (Gamma)', ...
                'Preload uncertainty, fractional.');
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
            panel = uipanel(parent, 'Title', 'Applied loads (single joint)');
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
            panel = uipanel(parent, 'Title', 'Analysis assumptions');
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

        function b = groupGrid(~, panel, rows)
            %GROUPGRID  The standard label / value / gutter grid.
            b = uigridlayout(panel, [rows 3]);
            b.ColumnWidth = {gui2.JointConfigPage.LabelW, ...
                             gui2.JointConfigPage.ValueW, '1x'};
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
                t = obj.FlangeThickness{i}.Value;
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
                    obj.FlangeThickness{i}.Value = L.Thickness;
                    obj.FlangeHole{i}.Value      = obj.fmtOptional(L.HoleDiameter);
                    obj.FlangeEdge{i}.Value      = obj.fmtOptional(L.EdgeDistance);
                    obj.FlangeTearout{i}.Value   = L.CheckShearTearout;
                    obj.trySelect(obj.FlangeMaterial{i}, L.Material.Name);
                else
                    % Rows beyond the stack are cleared, not just unticked:
                    % leaving a previous case's numbers behind an unticked
                    % box invites re-ticking them into a different joint.
                    obj.FlangeName{i}.Value      = '';
                    obj.FlangeThickness{i}.Value = 0;
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
            obj.setWasherFieldsEnable(obj.HeadWasher, states{headOn + 1});

            nutPresent = logical(obj.NutWasher.Present.Value);
            mirroring  = logical(obj.SameAsHeadCheck.Value);
            % Same as Head is only meaningful once there IS a nut washer.
            obj.SameAsHeadCheck.Enable = states{nutPresent + 1};
            nutOn = nutPresent && ~mirroring;
            obj.setWasherFieldsEnable(obj.NutWasher, states{nutOn + 1});
        end

        function setWasherFieldsEnable(~, w, state)
            w.Material.Enable = state;
            w.OD.Enable       = state;
            w.ID.Enable       = state;
            w.Thk.Enable      = state;
        end

        function onMemberTypeChanged(obj)
            obj.syncMemberType();
            obj.syncJointLoadVisibility();
            obj.updateBoltLengthLabel();
            obj.commitJoint();
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
            obj.EngagementRatioField.Enable  = states{isInsert + 1};
            obj.EngagementLengthField.Enable = states{~isInsert + 1};
            obj.EngagementRatioLabel.FontColor  = obj.enabledColor(isInsert);
            obj.EngagementLengthLabel.FontColor = obj.enabledColor(~isInsert);
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

        function onBoltLengthEdited(obj)
            obj.updateBoltLengthLabel();
            obj.commitJoint();
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
            r = engine.boltLengthCheck(obj.buildJoint());

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
            obj.BoltLengthLabel.Text = lines;
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
    end
end
