classdef DefinedJointsPage < gui2.Page
    %DEFINEDJOINTSPAGE  The case's saved joints (GUI2_SPEC.md Section 3).
    %
    %   A VIEW OVER AppState.JointLibrary, which already exists and is
    %   already written by Joint Config's "Save to Defined Joints" and
    %   already serialized into the case file. This page adds no storage
    %   of its own and computes nothing: it lists what is saved, shows a
    %   summary of the selection, and offers the three management actions
    %   the bulk workflow needs (load back into Joint Config, rename,
    %   delete).
    %
    %   CASE-SCOPED, and the page says so. Defined Joints travels with the
    %   analysis: it is saved in the case file and every entry is a joint
    %   this case defined. Materials & Hardware is the other library and is
    %   APP-scoped (baseline plus custom, persisted to library.json, shared
    %   across every case). GUI2_SPEC.md Section 15 resolved the two pages'
    %   naming collision; the scope difference still has to be stated
    %   in-page, because the rail labels alone do not carry it.
    %
    %   THE SUMMARY IS DELIBERATELY PARTIAL, AND SAYS SO. GUI2_HARVEST.md
    %   asks for a summary that mirrors the Joint Config panels field for
    %   field, and warns that the two must change together or the summary
    %   goes stale while still looking current. That warning is the reason
    %   NOT to mirror all ~60 fields here: the job on this page is to
    %   confirm WHICH saved joint you are about to load or delete, not to
    %   audit one. So it shows the identifying fields, and the panel title
    %   states that loading the joint is how you see everything. A summary
    %   that is declared partial cannot silently mislead; a sixty-row one
    %   that quietly drops a field can.
    %
    %   NOTHING IS COMPUTED. Every value is read straight off the stored
    %   model.Joint (GripLength is the model's own dependent property, not
    %   arithmetic done here). No preload band, no allowables -- that is
    %   engine.summary's job and it needs a load case and factors, neither
    %   of which a defined joint carries.
    %
    %   A RENAME OR A DELETE HAS CONSEQUENCES OUTSIDE THIS PAGE. Element
    %   mapping keys on the joint NAME, so a rename that did not carry the
    %   mapping with it would silently orphan every mapped element -- the
    %   rows would still name the old joint and resolve to nothing. Rename
    %   therefore retargets AppState.Mapping in the same commit, and delete
    %   states how many elements it is about to strand BEFORE asking, not
    %   after. (Element Mapping is not built yet, but Mapping is already
    %   case state and already loads from a case file, so the orphaning is
    %   reachable today.)
    %
    %   INCREMENT 1 shipped the list, the empty state and the count.
    %   INCREMENT 2 added the summary. INCREMENT 3 (this one) adds load /
    %   rename / delete. Joint Config was rebuilt this way after the
    %   single-pass attempt failed -- each increment diagnosable from one
    %   stack trace.
    %
    %   Backed by AppState.JointLibrary, listens to JointLibraryChanged.

    properties (Access = private)
        List          % uilistbox of saved joint names
        CountLabel
        EmptyLabel
        SummaryPanel
        SummaryValues % struct: row key -> value uilabel
        NoSelectionLabel
        NameField
        LoadButton
        RenameButton
        DeleteButton
    end

    properties (Constant, Access = private)
        % Row key -> display name, in render order. The keys are also the
        % SummaryValues field names, so a row cannot be built without a
        % label or updated without a row.
        SummaryRows = [ ...
            "Bolt",        "Bolt"
            "BoltMat",     "Bolt material"
            "BoltCount",   "Fasteners in joint"
            "Stack",       "Clamped stack"
            "Grip",        "Grip length"
            "Member",      "Threaded member"
            "MemberMat",   "Member material"
            "Torque",      "Nominal torque"
            "NutFactor",   "Nut factor K"
            "ShearPlane",  "Shear plane"]
    end

    methods
        function obj = DefinedJointsPage(state)
            obj@gui2.Page(state);
        end

        function id = pageId(~)
            id = "DefinedJoints";
        end

        function t = title(~)
            t = "Defined Joints";
        end

        function build(obj, parent)
            g = uigridlayout(parent, [4 2]);
            g.RowHeight   = {'fit', 'fit', '1x', 'fit'};
            g.ColumnWidth = {260, '1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;

            obj.addBanner(g, 1, [1 2], ...
                ['Case-scoped: these joints are saved in the case file and ' ...
                 'travel with this analysis. The bulk workflow maps ' ...
                 'elements onto them by name. Materials & Hardware is the ' ...
                 'other library and is app-scoped — shared across every case.']);

            obj.CountLabel = uilabel(g, 'FontWeight', 'bold');
            obj.CountLabel.Layout.Row    = 2;
            obj.CountLabel.Layout.Column = 1;

            obj.List = uilistbox(g, 'Items', {}, 'Multiselect', 'off', ...
                'ValueChangedFcn', @(~, ~) obj.showSelection());
            obj.List.Layout.Row    = 3;
            obj.List.Layout.Column = 1;

            obj.buildSummary(g, 3, 2);

            % The empty state is a SIBLING of the list, not text stuffed
            % into it as a fake item: a placeholder item is selectable and
            % would arrive at the actions as if it named a joint (A12).
            obj.EmptyLabel = uilabel(g, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', ...
                'FontColor', gui2.palette('mutedText'), ...
                'Text', ['No joints saved yet. Build one on Joint Config ' ...
                         'and press "Save to Defined Joints" — it is ' ...
                         'stored under the joint name.']);
            obj.EmptyLabel.Layout.Row    = 3;
            obj.EmptyLabel.Layout.Column = 2;

            obj.NoSelectionLabel = uilabel(g, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', ...
                'FontColor', gui2.palette('mutedText'), ...
                'Text', 'Select a joint to see its summary.');
            obj.NoSelectionLabel.Layout.Row    = 3;
            obj.NoSelectionLabel.Layout.Column = 2;

            obj.buildActions(g, 4, 1);

            obj.listenTo('JointLibraryChanged', @() obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            %REFRESH  AppState.JointLibrary -> the list. Never marks dirty.
            if ~obj.IsBuilt
                return
            end
            names = obj.savedNames();
            n = numel(names);

            % Assigning Items resets Value, so the selection has to be
            % re-applied by NAME. Re-applying by index would follow the
            % row number instead of the joint: delete the row above the
            % selection and the summary would silently switch joints
            % while the highlight never appeared to move.
            wanted = obj.selectedName();

            % Rebuild from state rather than mutating in place (A-series
            % invariant): the array is the truth, the list is a rendering
            % of it, and a partial update is how the two drift apart.
            % The empty case is assigned literally rather than through
            % cellstr, whose shape for an empty string array is a detail
            % this page should not depend on.
            if n == 0
                obj.List.Items = {};
            else
                obj.List.Items = cellstr(names);
            end
            obj.List.Visible = n > 0;

            if n > 0
                keep = find(strcmp(names, wanted), 1);
                if isempty(keep)
                    keep = 1;   % the selected joint is gone: fall to the top
                end
                obj.List.Value = obj.List.Items{keep};
            end

            if n == 1
                obj.CountLabel.Text = '1 saved joint';
            else
                obj.CountLabel.Text = sprintf('%d saved joints', n);
            end
            obj.showSelection();
        end
    end

    % ---- Actions ------------------------------------------------------
    methods (Access = private)
        function buildActions(obj, parent, row, col)
            %BUILDACTIONS  Rename field + the three management buttons.
            %   RENAME IS AN IN-PAGE FIELD, NOT A DIALOG. The only stock
            %   text-entry dialog is inputdlg, which is a legacy figure
            %   dialog and BLOCKS -- the same trap uiconfirm's return-value
            %   form set for the test suite (a press that opens it never
            %   returns, so no programmatic driver can answer it). A field
            %   and a button need no dialog machinery at all.
            g = uigridlayout(parent, [2 3]);
            g.RowHeight   = {'fit', 'fit'};
            g.ColumnWidth = {'1x', '1x', '1x'};
            g.Padding     = [0 0 0 0];
            g.RowSpacing  = 4;
            g.Layout.Row    = row;
            g.Layout.Column = col;

            obj.NameField = uieditfield(g, 'text', ...
                'Tooltip', ['The selected joint''s name. Edit it and press ' ...
                            'Rename; element mappings follow the new name.']);
            obj.NameField.Layout.Row    = 1;
            obj.NameField.Layout.Column = [1 3];

            obj.LoadButton = uibutton(g, 'push', 'Text', 'Load', ...
                'ButtonPushedFcn', @(~, ~) obj.onLoad());
            obj.LoadButton.Layout.Row    = 2;
            obj.LoadButton.Layout.Column = 1;
            obj.LoadButton.Tooltip = ['Copy this joint onto Joint Config ' ...
                'and go there.'];

            obj.RenameButton = uibutton(g, 'push', 'Text', 'Rename', ...
                'ButtonPushedFcn', @(~, ~) obj.onRename());
            obj.RenameButton.Layout.Row    = 2;
            obj.RenameButton.Layout.Column = 2;

            obj.DeleteButton = uibutton(g, 'push', 'Text', 'Delete', ...
                'ButtonPushedFcn', @(~, ~) obj.onDelete());
            obj.DeleteButton.Layout.Row    = 2;
            obj.DeleteButton.Layout.Column = 3;
        end

        function onLoad(obj)
            %ONLOAD  Copy the selected joint onto Joint Config.
            name = obj.selectedName();
            if strlength(name) == 0
                return
            end
            % Confirm ONLY when there is something to lose. The joint on
            % Joint Config is worth protecting when it is neither the
            % untouched default nor already stored under some name --
            % anything else and the dialog is noise, and a dialog that is
            % usually noise is one people learn to click through.
            if obj.currentJointIsUnsavedWork()
                fig = ancestor(obj.Root, 'figure');
                uiconfirm(fig, ['The joint on Joint Config has not been ' ...
                    'saved to this library. Loading "' char(name) ...
                    '" replaces it. Continue?'], 'Replace current joint', ...
                    'Options',       {'Load', 'Cancel'}, ...
                    'DefaultOption', 'Cancel', ...
                    'CancelOption',  'Cancel', ...
                    'CloseFcn', @(~, evt) obj.onLoadAnswered(name, evt));
                return
            end
            obj.commitLoad(name);
        end

        function onLoadAnswered(obj, name, evt)
            if strcmp(evt.SelectedOption, 'Load')
                obj.commitLoad(name);
            end
        end

        function commitLoad(obj, name)
            obj.State.Joint = obj.jointNamed(name);
            obj.State.markDirty();
            obj.setStatus(sprintf('Loaded "%s" onto Joint Config.', name));
            obj.goToPage("JointConfig");
        end

        function onRename(obj)
            %ONRENAME  Rename the selection, carrying its mappings with it.
            old = obj.selectedName();
            new = strtrim(string(obj.NameField.Value));
            if strlength(old) == 0
                return
            end
            if strlength(new) == 0
                obj.setStatus('Enter a name — the library is keyed by it.');
                return
            end
            if strcmp(old, new)
                return
            end

            % Case-INSENSITIVE collision, the same rule Joint Config's save
            % uses (A13). "JT-A" and "jt-a" coexisting is a mapping trap:
            % element mapping keys on the name and would reference the
            % wrong joint. A rename that only changes CASE is still a
            % rename, so the entry itself is excluded from the check.
            lib = obj.State.JointLibrary;
            idx = find(strcmpi(string({lib.Name}), old), 1);
            others = setdiff(1:numel(lib), idx);
            if any(strcmpi(string({lib(others).Name}), new))
                obj.setStatus(sprintf( ...
                    'A joint named "%s" is already in the library.', new));
                obj.NameField.Value = char(old);
                return
            end

            lib(idx).Name = new;
            obj.State.JointLibrary = lib;
            obj.retargetMapping(old, new);
            obj.State.markDirty();
            obj.List.Value = char(new);
            obj.showSelection();
            obj.setStatus(sprintf('Renamed "%s" to "%s".', old, new));
        end

        function onDelete(obj)
            %ONDELETE  Remove the selection, after saying what it costs.
            name = obj.selectedName();
            if strlength(name) == 0
                return
            end
            % Name the mapped elements in the prompt. Deleting a joint that
            % elements still reference leaves those rows pointing at
            % nothing, and the analyst is the only one who can decide that
            % is acceptable -- so they have to be told before, not after.
            n = numel(obj.mappedElements(name));
            msg = sprintf('Delete "%s" from this case''s defined joints?', name);
            if n == 1
                msg = [msg ' 1 mapped element will be left without a joint.'];
            elseif n > 1
                msg = sprintf('%s %d mapped elements will be left without a joint.', msg, n);
            end

            fig = ancestor(obj.Root, 'figure');
            uiconfirm(fig, msg, 'Delete joint', ...
                'Options',       {'Delete', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'CloseFcn', @(~, evt) obj.onDeleteAnswered(name, evt));
        end

        function onDeleteAnswered(obj, name, evt)
            if ~strcmp(evt.SelectedOption, 'Delete')
                return
            end
            lib = obj.State.JointLibrary;
            idx = find(strcmpi(string({lib.Name}), name), 1);
            if isempty(idx)
                return
            end
            lib(idx) = [];
            obj.State.JointLibrary = lib;   % fires the refresh
            obj.State.markDirty();
            obj.setStatus(sprintf('Deleted "%s".', name));
        end

        function tf = currentJointIsUnsavedWork(obj)
            %CURRENTJOINTISUNSAVEDWORK  Is there Joint Config work to lose?
            %   False for the untouched default, and false when the joint
            %   is already stored under some name.
            tf = false;
            j = obj.State.Joint;
            if isequal(j, model.Joint())
                return
            end
            lib = obj.State.JointLibrary;
            for i = 1:numel(lib)
                if isequal(lib(i).Joint, j)
                    return
                end
            end
            tf = true;
        end

        function j = jointNamed(obj, name)
            j   = model.Joint();
            lib = obj.State.JointLibrary;
            idx = find(strcmpi(string({lib.Name}), name), 1);
            if ~isempty(idx)
                j = lib(idx).Joint;
            end
        end

        function ids = mappedElements(obj, name)
            %MAPPEDELEMENTS  Element ids pointing at this joint name.
            m = obj.State.Mapping;
            if isempty(m)
                ids = strings(1, 0);
                return
            end
            hit = strcmpi(string({m.JointName}), name);
            ids = string({m(hit).ElementID});
        end

        function retargetMapping(obj, old, new)
            %RETARGETMAPPING  Point this joint's element rows at the new name.
            %   Without this a rename silently orphans every mapped
            %   element: Element Mapping keys on the NAME, so the rows
            %   would still say the old one and resolve to nothing.
            m = obj.State.Mapping;
            if isempty(m)
                return
            end
            hit = strcmpi(string({m.JointName}), old);
            if ~any(hit)
                return
            end
            [m(hit).JointName] = deal(new);
            obj.State.Mapping = m;
        end
    end

    % ---- The summary --------------------------------------------------
    methods (Access = private)
        function buildSummary(obj, parent, row, col)
            %BUILDSUMMARY  The read-only panel describing the selection.
            %   Fixed rows, built once and re-texted on selection: the row
            %   set never varies, so rebuilding the grid per selection
            %   would be churn with nothing to show for it.
            rows = gui2.DefinedJointsPage.SummaryRows;

            obj.SummaryPanel = uipanel(parent, 'FontWeight', 'bold', ...
                'FontSize', 13, 'Title', 'Summary');
            obj.SummaryPanel.Layout.Row    = row;
            obj.SummaryPanel.Layout.Column = col;

            g = uigridlayout(obj.SummaryPanel, [size(rows, 1) + 1, 2]);
            g.RowHeight   = [repmat({'fit'}, 1, size(rows, 1)), {'fit'}];
            g.ColumnWidth = {150, '1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 3;

            obj.SummaryValues = struct();
            for i = 1:size(rows, 1)
                name = uilabel(g, 'Text', char(rows(i, 2)), ...
                    'FontColor', gui2.palette('mutedText'));
                name.Layout.Row    = i;
                name.Layout.Column = 1;

                value = uilabel(g, 'Text', '', 'WordWrap', 'on');
                value.Layout.Row    = i;
                value.Layout.Column = 2;
                obj.SummaryValues.(rows(i, 1)) = value;
            end

            % States the summary's scope in the page rather than leaving
            % the analyst to infer it from what is absent. See the class
            % header: a partial summary that says so cannot mislead.
            note = uilabel(g, 'WordWrap', 'on', ...
                'FontColor', gui2.palette('mutedText'), ...
                'Text', ['Identifying fields only — load the joint into ' ...
                         'Joint Config to see or change every field. ' ...
                         'Applied loads are not stored with a joint; they ' ...
                         'come from the load case or the bulk element table.']);
            note.Layout.Row    = size(rows, 1) + 1;
            note.Layout.Column = [1 2];
        end

        function showSelection(obj)
            %SHOWSELECTION  Render the selected joint, or the right prompt.
            %   THREE mutually exclusive states share this cell — empty
            %   library, nothing selected, and a selection. Exactly one is
            %   ever visible, which is why they can overlap; two visible at
            %   once is the uigridlayout stacking bug, not a layout that
            %   merely looks crowded.
            name = obj.selectedName();
            hasLibrary   = ~isempty(obj.State.JointLibrary);
            hasSelection = hasLibrary && strlength(name) > 0;

            obj.EmptyLabel.Visible       = ~hasLibrary;
            obj.NoSelectionLabel.Visible = hasLibrary && ~hasSelection;
            obj.SummaryPanel.Visible     = hasSelection;

            % Disabled rather than hidden: buttons that vanish move the
            % layout under the cursor, and all three are meaningless
            % without a selection anyway.
            obj.LoadButton.Enable   = hasSelection;
            obj.RenameButton.Enable = hasSelection;
            obj.DeleteButton.Enable = hasSelection;
            obj.NameField.Enable    = hasSelection;

            if ~hasSelection
                obj.NameField.Value = '';
                return
            end
            obj.NameField.Value = char(name);

            j    = obj.selectedJoint();
            rows = gui2.DefinedJointsPage.SummaryRows;
            text = obj.summaryText(j);
            for i = 1:size(rows, 1)
                obj.SummaryValues.(rows(i, 1)).Text = char(text.(rows(i, 1)));
            end
        end

        function t = summaryText(~, j)
            %SUMMARYTEXT  model.Joint -> one display string per summary row.
            %   Reads stored values only. Anything unset reads as an em
            %   dash, never as a zero or a blank: A1 — an unknown must not
            %   be presentable as a fine value.
            t = struct();
            t.Bolt      = gui2.DefinedJointsPage.orDash(j.Bolt.Designation);
            t.BoltMat   = gui2.DefinedJointsPage.orDash(j.BoltMaterial.Name);
            t.BoltCount = string(j.BoltCount);

            n = numel(j.FlangeStack);
            if n == 0
                t.Stack = "—";
            elseif n == 1
                t.Stack = "1 layer";
            else
                t.Stack = sprintf("%d layers", n);
            end
            % GripLength is model.Joint's own dependent property. Summing
            % the layers here would be a second implementation of it.
            t.Grip = gui2.DefinedJointsPage.dim(j.GripLength, "in");

            m = j.ThreadedMember;
            member = string(m.Type);
            if strlength(m.HostName) > 0
                member = member + " in " + m.HostName;
            end
            t.Member    = member;
            t.MemberMat = gui2.DefinedJointsPage.orDash(m.Material.Name);

            t.Torque     = gui2.DefinedJointsPage.dim(j.PreloadSpec.NominalTorque, "in-lbf");
            t.NutFactor  = gui2.DefinedJointsPage.dim(j.PreloadSpec.NutFactor, "");
            t.ShearPlane = string(j.ShearPlane);
        end
    end

    methods (Static, Access = private)
        function s = orDash(v)
            s = string(v);
            if strlength(strtrim(s)) == 0
                s = "—";
            end
        end

        function s = dim(v, unit)
            %DIM  A dimensioned number, or an em dash when it is not set.
            if isnan(v)
                s = "—";
            elseif strlength(unit) > 0
                s = sprintf("%g %s", v, unit);
            else
                s = sprintf("%g", v);
            end
        end
    end

    % ---- Test seams ---------------------------------------------------
    methods
        function l = listBox(obj)
            l = obj.List;
        end

        function p = summaryPanel(obj)
            p = obj.SummaryPanel;
        end

        function v = summaryValue(obj, key)
            %SUMMARYVALUE  The value label for one summary row.
            v = obj.SummaryValues.(key);
        end

        function l = noSelectionLabel(obj)
            l = obj.NoSelectionLabel;
        end

        function f = nameField(obj)
            f = obj.NameField;
        end

        function b = loadButton(obj)
            b = obj.LoadButton;
        end

        function b = renameButton(obj)
            b = obj.RenameButton;
        end

        function b = deleteButton(obj)
            b = obj.DeleteButton;
        end

        function l = countLabel(obj)
            l = obj.CountLabel;
        end

        function l = emptyLabel(obj)
            l = obj.EmptyLabel;
        end
    end

    methods
        function name = selectedName(obj)
            %SELECTEDNAME  The selected joint's name, "" when none.
            %   Reads the control, not a cached field: a cached copy is
            %   one more thing that can disagree with what is on screen.
            name = "";
            if isempty(obj.List) || ~isvalid(obj.List)
                return
            end
            v = obj.List.Value;
            if isempty(v)
                return
            end
            name = string(v);
        end
    end

    methods (Access = private)
        function j = selectedJoint(obj)
            %SELECTEDJOINT  The stored model.Joint for the selection.
            %   Case-INSENSITIVE match, the same rule Joint Config's save
            %   collision test uses (A13): the two must agree, or a name
            %   that save treats as a duplicate would look like a separate
            %   joint here.
            j   = model.Joint();
            lib = obj.State.JointLibrary;
            if isempty(lib)
                return
            end
            idx = find(strcmpi(string({lib.Name}), obj.selectedName()), 1);
            if ~isempty(idx)
                j = lib(idx).Joint;
            end
        end

        function names = savedNames(obj)
            %SAVEDNAMES  The saved joint names, in stored order.
            %   Stored order, NOT sorted: Joint Config appends, so the
            %   order is the order the analyst defined them in, and
            %   re-sorting would move a row out from under a selection.
            lib = obj.State.JointLibrary;
            if isempty(lib)
                names = strings(1, 0);
                return
            end
            names = string({lib.Name});
        end
    end
end
