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
        Fig
        CheckDropDown
        Html
        Links = struct('Id', {}, 'File', {}, 'Line', {})
        Check (1,1) string = ""
        LastEvent (1,1) string = ""
    end

    methods
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
            g = uigridlayout(obj.Fig, [2 3]);
            g.RowHeight   = {26, '1x'};
            g.ColumnWidth = {'fit', 220, '1x'};
            g.Padding     = [8 8 8 8];

            lb = uilabel(g, 'Text', 'Check');
            lb.Layout.Row = 1;  lb.Layout.Column = 1;
            names = sort(engine.calculationMap());
            obj.CheckDropDown = uidropdown(g, 'Items', cellstr(names), ...
                'ValueChangedFcn', @(src, ~) obj.setCheck(string(src.Value)));
            obj.CheckDropDown.Layout.Row = 1;  obj.CheckDropDown.Layout.Column = 2;
            hint = uilabel(g, 'Text', ['Click an equation to open its file ' ...
                'in the editor at that line. Arrows point from a step to the ' ...
                'function that uses it.']);
            hint.Layout.Row = 1;  hint.Layout.Column = 3;
            hint.FontColor = gui.palette('mutedText');

            here = fileparts(fileparts(mfilename("fullpath")));
            obj.Html = uihtml(g, 'HTMLSource', fullfile(here, "calcmap", "index.html"), ...
                'HTMLEventReceivedFcn', @(~, evt) obj.onHtmlEvent(evt));
            obj.Html.Layout.Row = 2;  obj.Html.Layout.Column = [1 3];
        end

        function setCheck(obj, check)
            m = engine.calculationMap(check);
            [txt, obj.Links] = gui.CalculationMapView.mermaidText(m);
            obj.Check = check;
            obj.LastEvent = "";
            obj.Html.Data = struct('graph', char(txt), ...
                'note', sprintf('%s: %d functions, %d equations, read from the code just now.', ...
                check, numel(m.Nodes), numel(obj.Links)));
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
        function [txt, links] = mermaidText(m)
            %MERMAIDTEXT  engine.calculationMap -> Mermaid flowchart text,
            %   plus the node id -> file:line table the clicks resolve.
            L = "flowchart TB";
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
                if isempty(nd.Equations)
                    L(end + 1) = sprintf('  %s["%s"]', sid, ...
                        gui.CalculationMapView.esc(title) + "<br/><i>combines the steps above</i>"); %#ok<AGROW>
                    links(end + 1) = struct('Id', sid, 'File', nd.File, 'Line', 1); %#ok<AGROW>
                    L(end + 1) = sprintf('  click %s call openNode("%s")', sid, sid); %#ok<AGROW>
                else
                    L(end + 1) = sprintf('  subgraph %s["%s"]', sid, gui.CalculationMapView.esc(title)); %#ok<AGROW>
                    L(end + 1) = "    direction TB"; %#ok<AGROW>
                    for j = 1:numel(nd.Equations)
                        e = nd.Equations(j);
                        id = sid + "E" + j;
                        label = "<b>" + gui.CalculationMapView.esc(gui.CalculationMapView.shortRef(e.Reference)) + ...
                            "</b><br/>" + gui.CalculationMapView.wrap(gui.CalculationMapView.esc(e.Formula)) + ...
                            "<br/><i>line " + e.Line + "</i>";
                        L(end + 1) = sprintf('    %s["%s"]', id, label); %#ok<AGROW>
                        L(end + 1) = sprintf('    click %s call openNode("%s")', id, id); %#ok<AGROW>
                        links(end + 1) = struct('Id', id, 'File', nd.File, 'Line', e.Line); %#ok<AGROW>
                    end
                    L(end + 1) = "  end"; %#ok<AGROW>
                end
                if nd.IsCheck
                    L(end + 1) = sprintf('  style %s stroke:#1a3a6e,stroke-width:3px', sid); %#ok<AGROW>
                end
            end
            for e = m.Edges
                L(end + 1) = sprintf('  %s --> %s', box(char(e.From)), box(char(e.To))); %#ok<AGROW>
            end
            txt = strjoin(L, newline);
        end
    end

    methods (Static, Access = private)
        function s = esc(s)
            % Mermaid entity codes, so formula text cannot break the syntax.
            s = replace(string(s), ["#", """", "<", ">"], ["#35;", "#quot;", "#lt;", "#gt;"]);
        end

        function s = shortRef(s)
            s = replace(string(s), ["NASA-STD-5020B", "NASA TM-106943", "NASA RP-1228"], ...
                                   ["5020B", "TM-106943", "RP-1228"]);
        end

        function s = wrap(s)
            % Break long formulas at spaces, about 56 characters a line.
            words = split(string(s), " ")';
            s = "";
            n = 0;
            for w = words
                if n > 0 && n + strlength(w) > 56
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
