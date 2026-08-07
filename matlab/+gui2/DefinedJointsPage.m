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
    %   INCREMENT 1 of the step-5 build: the list, the empty state, the
    %   scope banner and the count. The summary panel and the three
    %   actions land next, one increment each. Joint Config was rebuilt
    %   this way after the single-pass attempt failed -- each increment
    %   diagnosable from one stack trace.
    %
    %   Backed by AppState.JointLibrary, listens to JointLibraryChanged.

    properties (Access = private)
        List          % uilistbox of saved joint names
        CountLabel
        EmptyLabel
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

            obj.List = uilistbox(g, 'Items', {}, 'Multiselect', 'off');
            obj.List.Layout.Row    = 3;
            obj.List.Layout.Column = 1;

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
            obj.List.Visible      = n > 0;
            obj.EmptyLabel.Visible = n == 0;

            if n == 1
                obj.CountLabel.Text = '1 saved joint';
            else
                obj.CountLabel.Text = sprintf('%d saved joints', n);
            end
        end
    end

    % ---- Test seams ---------------------------------------------------
    methods
        function l = listBox(obj)
            l = obj.List;
        end

        function l = countLabel(obj)
            l = obj.CountLabel;
        end

        function l = emptyLabel(obj)
            l = obj.EmptyLabel;
        end
    end

    methods (Access = private)
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
