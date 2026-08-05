classdef PlaceholderPage < gui2.Page
    %PLACEHOLDERPAGE  A page that names the step which will replace it.
    %   Step 1 ships the shell, so every rail entry is one of these. Steps 2
    %   onward swap real gui2.Page subclasses into gui2.FastenerApp's
    %   pageSpecs one at a time; the PAGE IDS ARE THE CONTRACT and must
    %   survive the swap, because navigateTo, the pre-validation dialogs of
    %   later steps, and the tests all name pages by id.
    %
    %   It exists to prove the shell end to end — lazy construction,
    %   visibility swapping, refresh on navigation, and the rail's two state
    %   channels — with nothing else in the way.
    %
    %   It also demonstrates the empty-state convention (GUI2_HARVEST.md
    %   A12): NAME THE ABSENCE. "Not built yet — step 4" is honest; a blank
    %   panel is the thing a user cannot tell apart from a broken one.

    properties (Access = private)
        Id      (1,1) string
        Label   (1,1) string
        Step    (1,1) double
        BuildCount (1,1) double = 0
        RefreshCount (1,1) double = 0
    end

    methods
        function obj = PlaceholderPage(state, id, label, step)
            %PLACEHOLDERPAGE  (state, id, rail label, replacing step number)
            arguments
                state (1,1) gui2.AppState
                id    (1,1) string
                label (1,1) string
                step  (1,1) double
            end
            obj@gui2.Page(state);
            obj.Id    = id;
            obj.Label = label;
            obj.Step  = step;
        end

        function id = pageId(obj)
            id = obj.Id;
        end

        function t = title(obj)
            t = obj.Label;
        end

        function build(obj, parent)
            %BUILD  A centred note naming the step that replaces this page.
            obj.BuildCount = obj.BuildCount + 1;

            g = uigridlayout(parent, [3 1]);
            g.RowHeight   = {'1x', 'fit', '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [6 6 6 6];

            lbl = uilabel(g, 'HorizontalAlignment', 'center', ...
                'FontSize', 14, 'FontWeight', 'bold', ...
                'Text', char(obj.Label));
            lbl.FontColor  = gui2.palette('defaultText');
            lbl.Layout.Row = 2;

            sub = uilabel(g, 'HorizontalAlignment', 'center', ...
                'Text', sprintf('Not built yet — arrives in step %d.', obj.Step));
            sub.FontColor  = gui2.palette('mutedText');
            sub.Layout.Row = 3;
            sub.VerticalAlignment = 'top';
        end

        function refresh(obj)
            %REFRESH  Nothing to render; counted so the shell test can prove
            %   navigation refreshes the page it lands on.
            obj.RefreshCount = obj.RefreshCount + 1;
        end
    end

    % ---- Test seams -------------------------------------------------------
    %   Counters rather than mocks: the shell's contract is "build once,
    %   refresh on every navigation", and those are the two numbers that
    %   state it. Public getters so tGui2Shell can assert without reaching
    %   into private properties.
    methods
        function n = buildCount(obj)
            n = obj.BuildCount;
        end

        function n = refreshCount(obj)
            n = obj.RefreshCount;
        end
    end
end
