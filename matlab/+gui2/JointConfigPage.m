classdef JointConfigPage < gui2.Page
    %JOINTCONFIGPAGE  Define one joint and its limit loads (GUI2_SPEC.md 3).
    %   Rebuilt in verified increments after the first attempt was reverted:
    %   one 2,276-line pass produced a page that could only be checked by
    %   watching a failure count move. Each increment here ends with the
    %   suite green before the next begins.
    %
    %   STEP 1 (this one): the page shell and the Identity + Bolt group.
    %   Later: flange stack, threaded member, washers, the right column,
    %   the actions, and last and alone, the library auto-fill cascades.
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
    end

    properties (Access = private)
        JointNameField
        BoltDropDown
        BoltMaterialDropDown
        BoltCountField

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
            left.RowHeight     = {'fit'};
            left.Padding       = [0 0 0 0];
            left.RowSpacing    = 8;

            obj.buildBoltGroup(left, 1);

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
                    otherwise
                        keys = obj.State.Library.materialKeys(Role = "bolt");
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
    end
end
