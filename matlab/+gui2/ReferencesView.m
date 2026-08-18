classdef ReferencesView < handle
    %REFERENCESVIEW  The documents this tool's numbers rest on (GUI step 10).
    %   Lists every entry of data.referenceDocuments with its citation, its
    %   role in the document hierarchy, and what the tool takes from it.
    %   Where a local copy exists in the configured references folder, the
    %   Open button opens it in the system viewer.
    %
    %   WHY NOTHING IS BUNDLED. GUI2_SPEC.md Sec. 3 specified this as "Help
    %   opens the bundled PDFs". It cannot be: nine of the fifteen
    %   documents are copyrighted and not ours to redistribute -- every
    %   NAS/NASM sheet says so on its face -- and they are exactly the ones
    %   the hardware catalogue is transcribed from. The citations are facts
    %   and ship freely; the files are the analyst's own. See
    %   data.referenceDocuments for the full reasoning.
    %
    %   CREATE-OR-FOCUS, like gui2.JointSectionView: opening Help >
    %   References twice must raise the one window, not litter the desktop
    %   with identical ones.
    %
    %   ITS OWN uifigure, which cannot be a child of the app window, so
    %   nothing tears it down automatically -- gui2.FastenerApp.delete does
    %   it explicitly, the same arrangement every page's dialog uses.

    properties (Access = private)
        Fig
        Table
        DetailArea
        OpenButton
        FolderLabel
        Docs
    end

    methods
        function show(obj)
            %SHOW  Open the window, or raise it if it is already open.
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                figure(obj.Fig);
                obj.refresh();
                return
            end
            obj.build();
            obj.refresh();
        end

        function delete(obj)
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                delete(obj.Fig);
            end
        end
    end

    % ---- Window -----------------------------------------------------------
    methods (Access = private)
        function build(obj)
            obj.Docs = data.referenceDocuments();

            obj.Fig = uifigure('Name', 'References — Fastener Analysis Tool', ...
                'Position', [180 140 900 620]);

            g = uigridlayout(obj.Fig, [5 1]);
            % FIXED pixel rows for the wrapping label and the detail pane.
            % A WordWrap label in a 'fit' row can chase its own height --
            % wrapping changes the height, the height changes the layout,
            % the layout re-wraps -- and the window then sits there
            % unresponsive with nothing to show for it.
            g.RowHeight   = {52, '1x', 96, 26, 26};
            g.ColumnWidth = {'1x'};
            g.Padding     = [10 10 10 10];
            g.RowSpacing  = 8;

            lb = uilabel(g, 'WordWrap', 'on', 'VerticalAlignment', 'top', ...
                'Text', ['The documents this tool''s numbers come from. Most ' ...
                         'are copyrighted and are NOT shipped with the tool — ' ...
                         'the citation is always here, and Open works when you ' ...
                         'have a copy in your references folder.']);
            lb.Layout.Row = 1;  lb.Layout.Column = 1;
            lb.BackgroundColor = gui2.palette('bannerInfoBg');
            lb.FontColor       = gui2.palette('bannerInfoFg');

            t = uitable(g);
            t.Layout.Row = 2;  t.Layout.Column = 1;
            t.ColumnName   = {'Document', 'Role', 'Publisher', 'Year', 'Local copy'};
            t.ColumnWidth  = {200, 120, 230, 60, '1x'};
            t.RowName      = {};
            t.ColumnEditable = false;
            t.ColumnSortable = true;
            t.SelectionType  = 'row';
            t.SelectionChangedFcn = @(~, evt) obj.onSelected(evt);
            obj.Table = t;

            obj.DetailArea = uitextarea(g, 'Editable', 'off');
            obj.DetailArea.Layout.Row = 3;  obj.DetailArea.Layout.Column = 1;

            bar = uigridlayout(g, [1 3]);
            bar.Layout.Row = 4;  bar.Layout.Column = 1;
            bar.RowHeight   = {'1x'};
            bar.ColumnWidth = {'fit', 'fit', '1x'};
            bar.Padding     = [0 0 0 0];
            bar.ColumnSpacing = 8;

            obj.OpenButton = uibutton(bar, 'push', 'Text', 'Open document', ...
                'Enable', 'off', ...
                'Tooltip', 'Open your local copy in the system viewer.', ...
                'ButtonPushedFcn', @(~, ~) obj.onOpen());
            obj.OpenButton.Layout.Row = 1;  obj.OpenButton.Layout.Column = 1;

            b2 = uibutton(bar, 'push', 'Text', 'Choose references folder…', ...
                'Tooltip', 'Where your copies of these documents live.', ...
                'ButtonPushedFcn', @(~, ~) obj.onChooseFolder());
            b2.Layout.Row = 1;  b2.Layout.Column = 2;

            obj.FolderLabel = uilabel(g, 'Text', '');
            obj.FolderLabel.Layout.Row = 5;  obj.FolderLabel.Layout.Column = 1;
            obj.FolderLabel.FontColor = gui2.palette('mutedText');
        end

        function refresh(obj)
            folder = gui2.referencesFolder();
            rows = cell(numel(obj.Docs), 5);
            for i = 1:numel(obj.Docs)
                d = obj.Docs(i);
                rows{i, 1} = char(d.Key);
                rows{i, 2} = char(d.Role);
                rows{i, 3} = char(d.Publisher);
                rows{i, 4} = char(d.Year);
                % NAME THE ABSENCE. "not on this machine" and "this tool
                % does not cite one" are different facts and must not
                % render alike -- the second would read as a gap in the
                % traceability rather than a gap in the analyst's folder.
                if strlength(d.File) == 0
                    rows{i, 5} = 'no file';
                elseif strlength(folder) > 0 && isfile(fullfile(folder, d.File))
                    rows{i, 5} = char(d.File);
                else
                    rows{i, 5} = 'not on this machine';
                end
            end
            obj.Table.Data = rows;
            obj.Table.Selection = [];
            obj.DetailArea.Value = {'Select a document to see what the tool takes from it.'};
            obj.OpenButton.Enable = 'off';

            if strlength(folder) == 0
                obj.FolderLabel.Text = ...
                    'References folder: not set — use "Choose references folder…" to open local copies.';
            else
                obj.FolderLabel.Text = ['References folder: ' char(folder)];
            end
        end

        function onSelected(obj, evt)
            if isempty(evt.Selection)
                obj.OpenButton.Enable = 'off';
                return
            end
            d = obj.Docs(evt.Selection(1));
            obj.DetailArea.Value = { ...
                char(d.Title), ...
                char(sprintf('%s, %s   [%s]', d.Publisher, d.Year, d.Role)), ...
                '', ...
                char(d.UsedFor)};
            obj.OpenButton.Enable = obj.localFile(d) ~= "";
        end

        function f = localFile(~, d)
            %LOCALFILE  This machine's copy, or "" when there is not one.
            f = "";
            if strlength(d.File) == 0
                return
            end
            folder = gui2.referencesFolder();
            if strlength(folder) == 0
                return
            end
            candidate = fullfile(folder, d.File);
            if isfile(candidate)
                f = string(candidate);
            end
        end

        function onOpen(obj)
            sel = obj.Table.Selection;
            if isempty(sel)
                return
            end
            f = obj.localFile(obj.Docs(sel(1)));
            if f == ""
                uialert(obj.Fig, ...
                    ['This document is not in your references folder. It is ' ...
                     'copyrighted and does not ship with the tool — the ' ...
                     'citation above is what the tool relies on.'], ...
                    'No local copy', 'Icon', 'info');
                return
            end
            gui2.openExternal(f, obj.Fig);
        end

        function onChooseFolder(obj)
            start = gui2.referencesFolder();
            if strlength(start) == 0
                start = pwd;
            end
            chosen = uigetdir(char(start), 'Choose your references folder');
            if isequal(chosen, 0)
                return          % cancelled
            end
            gui2.referencesFolder(string(chosen));
            obj.refresh();
        end
    end

    % ---- Test seams -------------------------------------------------------
    methods
        function f = figureHandle(obj)
            f = obj.Fig;
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Fig) && isvalid(obj.Fig);
        end

        function t = docTable(obj)
            t = obj.Table;
        end

        function selectRow(obj, row)
            %SELECTROW  Select a row AND run the real selection callback.
            obj.Table.Selection = row;
            obj.onSelected(struct('Selection', row));
        end

        function v = detailText(obj)
            v = obj.DetailArea.Value;
        end

        function b = openButton(obj)
            b = obj.OpenButton;
        end

        function s = folderText(obj)
            s = obj.FolderLabel.Text;
        end
    end
end
