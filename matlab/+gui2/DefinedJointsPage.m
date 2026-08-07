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
    %   INCREMENT 1 shipped the list, the empty state and the count.
    %   INCREMENT 2 (this one) adds the summary. The load / rename / delete
    %   actions land next. Joint Config was rebuilt this way after the
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
            if ~hasSelection
                return
            end

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
