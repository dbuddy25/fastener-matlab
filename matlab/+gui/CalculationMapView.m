classdef CalculationMapView < handle
    %CALCULATIONMAPVIEW  One flowchart per check, each equation clickable.
    %   A secondary window like the References window: the shell owns it,
    %   raises it rather than opening a second, and closes it with the app.
    %   The map comes from engine.calculationMap, built from the code each
    %   time a check is shown; this class only draws it. Clicking an
    %   equation opens its file in the MATLAB editor at that line.
    %
    %   Drawn by Mermaid (bundled in matlab/calcmap, so it works offline)
    %   inside a uihtml panel.

    properties (Access = private)
        State
        Listener
        Fig
        CheckDropDown
        LayoutDropDown
        Html
        Links = struct('Id', {}, 'File', {}, 'Line', {})
        Check (1,1) string = ""
        LastEvent (1,1) string = ""
    end

    methods
        function obj = CalculationMapView(state)
            %CALCULATIONMAPVIEW  state (gui.AppState) supplies the values
            %   from the last Analyze; without one the map is formulas only.
            arguments
                state = []
            end
            obj.State = state;
            if ~isempty(state)
                obj.Listener = event.listener(state, 'ResultChanged', ...
                    @(~, ~) obj.onResultChanged());
            end
        end

        function show(obj, check)
            arguments
                obj
                check (1,1) string = "Tension-Ultimate"
            end
            if isempty(obj.Fig) || ~isvalid(obj.Fig)
                obj.build();
            else
                figure(obj.Fig);
            end
            obj.CheckDropDown.Value = char(check);
            obj.setCheck(check);
        end

        function delete(obj)
            delete(obj.Listener);
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                delete(obj.Fig);
            end
        end

        function c = currentCheck(obj)
            c = obj.Check;
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Fig) && isvalid(obj.Fig);
        end

        function f = figureHandle(obj)
            f = obj.Fig;
        end

        function d = layoutDropDown(obj)
            d = obj.LayoutDropDown;
        end

        function e = lastEvent(obj)
            %LASTEVENT  "rendered <n>" or "renderError <message>" from the page.
            e = obj.LastEvent;
        end

        function k = linkFor(obj, id)
            %LINKFOR  The file and line a node id opens.
            k = obj.Links(strcmp([obj.Links.Id], id));
        end

        function n = linkCount(obj)
            n = numel(obj.Links);
        end
    end

    methods (Access = private)
        function build(obj)
            obj.Fig = uifigure('Name', 'Calculation Map', ...
                'Position', [160 90 1100 760]);
            g = uigridlayout(obj.Fig, [2 5]);
            g.RowHeight   = {26, '1x'};
            g.ColumnWidth = {'fit', 220, 'fit', 130, '1x'};
            g.Padding     = [8 8 8 8];

            lb = uilabel(g, 'Text', 'Check');
            lb.Layout.Row = 1;  lb.Layout.Column = 1;
            names = sort(engine.calculationMap());
            obj.CheckDropDown = uidropdown(g, 'Items', cellstr(names), ...
                'ValueChangedFcn', @(src, ~) obj.setCheck(string(src.Value)));
            obj.CheckDropDown.Tooltip = 'Reads this check''s code and redraws; large checks take a second or two.';
            obj.CheckDropDown.Layout.Row = 1;  obj.CheckDropDown.Layout.Column = 2;
            lb = uilabel(g, 'Text', 'Layout');
            lb.Layout.Row = 1;  lb.Layout.Column = 3;
            obj.LayoutDropDown = uidropdown(g, ...
                'Items', {'Left to right', 'Top to bottom'}, ...
                'ItemsData', {'LR', 'TB'}, 'Value', 'LR', ...
                'ValueChangedFcn', @(~, ~) obj.setCheck(obj.Check));
            obj.LayoutDropDown.Layout.Row = 1;  obj.LayoutDropDown.Layout.Column = 4;
            hint = uilabel(g, 'Text', ['Click an equation to open it in the ' ...
                'editor. Arrows run from a step to the function that uses it. ' ...
                'Ctrl + wheel zooms.']);
            hint.Layout.Row = 1;  hint.Layout.Column = 5;
            hint.FontColor = gui.palette('mutedText');

            here = fileparts(fileparts(mfilename("fullpath")));
            obj.Html = uihtml(g, 'HTMLSource', fullfile(here, "calcmap", "index.html"), ...
                'HTMLEventReceivedFcn', @(~, evt) obj.onHtmlEvent(evt));
            obj.Html.Layout.Row = 2;  obj.Html.Layout.Column = [1 5];
        end

        function setCheck(obj, check)
            try
                obj.drawCheck(check);
            catch err
                % Never a silent map: the bar says what failed.
                obj.Check = check;
                obj.LastEvent = "buildError " + string(err.message);
                obj.Html.Data = struct('graph', 'flowchart LR', 'check', char(check), ...
                    'note', char("Could not build the map for " + check + ": " + err.message));
            end
        end

        function drawCheck(obj, check)
            m = engine.calculationMap(check);
            r = [];
            note = "No result yet: formulas only. Run Analyze to see this joint's numbers.";
            if ~isempty(obj.State) && ~isempty(obj.State.Result)
                r = obj.State.Result;
                note = "Values from the last Analyze.";
                if obj.State.ResultStale
                    note = "Values from the last Analyze, which is STALE: inputs changed since.";
                end
            end
            [txt, obj.Links] = gui.CalculationMapView.mermaidText(m, ...
                string(obj.LayoutDropDown.Value), r);
            obj.Check = check;
            obj.LastEvent = "";
            obj.Html.Data = struct('graph', char(txt), 'note', char(note), 'check', char(check));
        end

        function onResultChanged(obj)
            if obj.isOpen() && strlength(obj.Check) > 0
                obj.setCheck(obj.Check);
            end
        end

        function onHtmlEvent(obj, evt)
            name = string(evt.HTMLEventName);
            data = string(evt.HTMLEventData);
            obj.LastEvent = strtrim(name + " " + data);
            if name == "open"
                k = obj.linkFor(data);
                if ~isempty(k)
                    opentoline(char(k.File), k.Line);
                end
            end
        end
    end

    methods (Static)
        function [txt, links] = mermaidText(m, direction, r)
            %MERMAIDTEXT  engine.calculationMap -> Mermaid flowchart text,
            %   plus the node id -> file:line table the clicks resolve.
            %   direction "LR" (default, suits a wide screen) or "TB".
            %   r, an engine.Result, adds this joint's values and dims the
            %   equations and links the run did not use.
            arguments
                m (1,1) struct
                direction (1,1) string {mustBeMember(direction, ["LR", "TB"])} = "LR"
                r = []
            end
            mg = [];
            root = m.Nodes([m.Nodes.IsCheck]).Name;
            if ~isempty(r)
                hit = r.Margins([r.Margins.Name] == m.Check);
                if ~isempty(hit)
                    mg = hit(1);
                end
            end
            L = "flowchart " + direction;
            links = struct('Id', {}, 'File', {}, 'Line', {});
            box = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for k = 1:numel(m.Nodes)
                nd = m.Nodes(k);
                sid = "F" + k;
                box(char(nd.Name)) = sid;
                [~, fname] = fileparts(nd.File);
                title = fname + ".m";
                if nd.IsCheck
                    title = m.Check + ": " + title;
                end
                % One box per file, its equations stacked inside it. Each
                % equation is its own click target (the page binds the
                % eq-<id> class); a click elsewhere on the box opens the
                % file at its first equation.
                label = "<b>" + gui.CalculationMapView.esc(title) + "</b>";
                if nd.IsCheck && ~isempty(mg)
                    label = label + gui.CalculationMapView.resultBadge(mg);
                end
                if ~isempty(r)
                    label = label + gui.CalculationMapView.nodeValues(nd.Name, r);
                end
                first = 1;
                if isempty(nd.Equations)
                    label = label + "<br/><i>combines the steps feeding it</i>";
                else
                    first = nd.Equations(1).Line;
                end
                for j = 1:numel(nd.Equations)
                    e = nd.Equations(j);
                    id = sid + "E" + j;
                    head = gui.CalculationMapView.esc(gui.CalculationMapView.shortRef(e.Reference));
                    if strlength(e.Description) > 0
                        head = "<b>" + gui.CalculationMapView.esc(e.Description) + "</b> · " + head;
                    else
                        head = "<b>" + head + "</b>";
                    end
                    % Styles inline, not in the page's CSS: Mermaid sizes the
                    % box from them, so the content cannot overflow it.
                    dim = "";
                    ran = ~isempty(mg) && any(string(mg.Status) == ["Pass", "Fail"]);
                    if nd.IsCheck && ran && ~gui.CalculationMapView.cited(e.Reference, mg.Method)
                        dim = "opacity:0.4;";
                        head = head + " <i>(not used for this joint)</i>";
                    end
                    label = label + "<div class='eq eq-" + id + "' style='" + ...
                        "text-align:left;padding:4px 6px;margin-top:4px;" + dim + ...
                        "border-top:1px solid #d8d8dc;cursor:pointer'>" + head + ...
                        "<br/>" + gui.CalculationMapView.wrap(gui.CalculationMapView.esc(e.Formula)) + ...
                        "<br/><i>line " + e.Line + "</i></div>";
                    links(end + 1) = struct('Id', id, 'File', nd.File, 'Line', e.Line); %#ok<AGROW>
                end
                L(end + 1) = sprintf('  %s["%s"]', sid, label); %#ok<AGROW>
                L(end + 1) = sprintf('  click %s call openNode("%s")', sid, sid); %#ok<AGROW>
                links(end + 1) = struct('Id', sid, 'File', nd.File, 'Line', first); %#ok<AGROW>
                if nd.IsCheck
                    L(end + 1) = sprintf('  style %s stroke:#1a3a6e,stroke-width:3px', sid); %#ok<AGROW>
                end
            end
            for i = 1:numel(m.Edges)
                e = m.Edges(i);
                L(end + 1) = sprintf('  %s --> %s', box(char(e.From)), box(char(e.To))); %#ok<AGROW>
                % phi reaches a tension margin only on the rupture-first
                % branch; when the Fig. 8 gate is assured it did not.
                if ~isempty(mg) && e.From == "stiffness" && e.To == root && ...
                        ~contains(mg.Method, ["phi", "φ"])
                    L(end + 1) = sprintf('  linkStyle %d stroke:#c7c7cc,stroke-dasharray:4 4', i - 1); %#ok<AGROW>
                end
            end
            txt = strjoin(L, newline);
        end
    end

    methods (Static, Access = private)
        function s = resultBadge(mg)
            % The check's outcome in the app's pass / fail / not-evaluated colours.
            switch string(mg.Status)
                case "Fail",         bg = "#ffc7c7"; fg = "#cc0000"; st = "FAIL";
                case "NotEvaluated", bg = "#fff3cd"; fg = "#856404"; st = "Not evaluated";
                case "Pass",         bg = "#c7f0c7"; fg = "#006600"; st = "Pass";
                otherwise,           bg = "#e0ecf9"; fg = "#1a3a6e"; st = string(mg.Status);
            end
            if mg.Name == "Interaction"
                val = gui.MarginView.rText(mg.R);
            else
                val = "MS " + gui.MarginView.msText(mg.MS, false);
            end
            s = "<div style='margin-top:4px;padding:3px 6px;background:" + bg + ...
                ";color:" + fg + ";font-weight:bold'>" + ...
                gui.CalculationMapView.esc(val + " · " + st) + "</div>";
            if isfield(mg, 'Inputs') && ~isempty(mg.Inputs)
                parts = strings(1, 0);
                for t = reshape(mg.Inputs, 1, [])
                    u = "";
                    if strlength(t.Units) > 0
                        u = " " + t.Units;
                    end
                    parts(end + 1) = t.Symbol + " = " + gui.CalculationMapView.num(t.Value) + u; %#ok<AGROW>
                end
                s = s + "<div style='text-align:left;padding:3px 6px'><i>Inputs:</i> " + ...
                    gui.CalculationMapView.wrap(gui.CalculationMapView.esc(strjoin(parts, " · "))) + "</div>";
            end
        end

        function s = nodeValues(name, r)
            % This joint's values for the shared steps.
            parts = strings(1, 0);
            n = @gui.CalculationMapView.num;
            switch string(name)
                case "preload"
                    p = r.Preload;
                    parts = ["PpiMax " + n(p.PpiMax), "PpiMin " + n(p.PpiMin), ...
                             "thermal " + n(p.ThermalDelta), "PpMax " + n(p.PpMax), ...
                             "PpMin " + n(p.PpMin) + " lbf"];
                    if isfield(p, 'PpMinSlip') && p.PpMinSlip ~= p.PpMin
                        parts(end + 1) = "PpMinSlip " + n(p.PpMinSlip) + " lbf";
                    end
                case "designLoads"
                    d = r.DesignLoads;
                    parts = ["Ptu " + n(d.Ptu), "Pty " + n(d.Pty), ...
                             "Psu " + n(d.Psu), "Psep " + n(d.Psep) + " lbf"];
                case "separationBeforeRuptureGate"
                    g = r.Gate;
                    if isfield(g, 'Assessed') && ~g.Assessed
                        parts = "Not assessed";
                    elseif isfield(g, 'Assured') && g.Assured
                        parts = ["Assured: separation first", "Ptu_allow " + n(g.PtuAllow) + " lbf"];
                    elseif isfield(g, 'Assured')
                        parts = ["Not assured: rupture first", "Ptu_allow " + n(g.PtuAllow) + " lbf"];
                    end
            end
            s = "";
            if ~isempty(parts)
                s = "<div style='text-align:left;padding:3px 6px;background:#f4f4f6'>" + ...
                    gui.CalculationMapView.wrap(gui.CalculationMapView.esc(strjoin(parts, " · "))) + "</div>";
            end
        end

        function tf = cited(reference, method)
            % Does the margin's Method cite this equation's number? Section
            % and figure references carry no Eq. number and always count.
            tok = regexp(string(reference), "Eq\.\s*(\d+)", "tokens", "once");
            tf = isempty(tok) || contains(string(method), "Eq. " + tok(1));
        end

        function s = num(v)
            if isnan(v)
                s = "—";
            elseif abs(v) >= 1000
                s = regexprep(sprintf("%.0f", v), "(\d)(?=(\d{3})+$)", "$1,");
            else
                s = string(sprintf("%.4g", v));
            end
        end

        function s = esc(s)
            % Mermaid entity codes, so formula text cannot break the syntax.
            s = replace(string(s), ["#", """", "<", ">"], ["#35;", "#quot;", "#lt;", "#gt;"]);
        end

        function s = shortRef(s)
            s = replace(string(s), ["NASA-STD-5020B", "NASA TM-106943", "NASA RP-1228"], ...
                                   ["5020B", "TM-106943", "RP-1228"]);
        end

        function s = wrap(s)
            % Break long formulas at spaces, about 84 characters a line.
            words = split(string(s), " ")';
            s = "";
            n = 0;
            for w = words
                if n > 0 && n + strlength(w) > 84
                    s = s + "<br/>";
                    n = 0;
                elseif n > 0
                    s = s + " ";
                    n = n + 1;
                end
                s = s + w;
                n = n + strlength(w);
            end
        end
    end
end
