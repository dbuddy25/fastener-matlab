classdef JointConfigPage < gui2.Page
    %JOINTCONFIGPAGE  Define one joint and its limit loads (GUI2_SPEC.md 3).
    %   Rebuilt in verified increments after the first attempt was reverted:
    %   one 2,276-line pass produced a page that could only be checked by
    %   watching a failure count move. Each increment here ends with the
    %   suite green before the next begins.
    %
    %   BUILT SO FAR: the page shell, the Identity + Bolt group, and the
    %   flange stack with its grip readout. Later: threaded member,
    %   washers, the right column, the actions, and last and alone, the
    %   library auto-fill cascades.
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
            left.RowHeight     = {'fit', 'fit'};
            left.Padding       = [0 0 0 0];
            left.RowSpacing    = 8;

            obj.buildBoltGroup(left, 1);
            obj.buildFlangeGroup(left, 2);

            obj.listenTo('JointChanged', @() obj.refresh());
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
            fg.ColumnWidth   = {44, 120, 150, 66, 76, 76, 66};
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

        function d = addDropdown(obj, g, row, labelText, items, tip)
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row = row; lb.Layout.Column = 1;
            lb.Tooltip = tip;
            d = uidropdown(g, 'Items', items, ...
                'Value', gui2.JointConfigPage.BlankChoice);
            d.Layout.Row = row; d.Layout.Column = 2;
            d.Tooltip = tip;
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
                    HoleDiameter      = obj.parseOptional(obj.FlangeHole{i}), ...
                    EdgeDistance      = obj.parseOptional(obj.FlangeEdge{i}), ...
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

        function onFlangeEdited(obj)
            obj.updateGripLabel();
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
            if strlength(key) == 0 || ~obj.State.LibraryOK
                return
            end
            try
                b = obj.State.Library.bolt(key);
            catch
                % A key that vanished from the library marshals as the
                % default rather than taking the whole commit down.
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
    end
end
