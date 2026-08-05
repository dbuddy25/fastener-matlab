classdef FastenerApp < handle
    %FASTENERAPP  The GUI shell: left rail, card area, menus, status, title.
    %   Step 1 of the rebuild (GUI2_SPEC.md Section 14). This class owns the
    %   window and the navigation; it owns NO analysis logic and NO page
    %   content. Pages are gui2.Page subclasses registered in pageSpecs()
    %   and built lazily on first navigation.
    %
    %   WHAT THIS CLASS IS ALLOWED TO DO
    %     - build the window, the rail, the card area, the status bar, the
    %       menu bar
    %     - navigate between pages
    %     - drive File > New / Open / Save / Save As through gui2.AppState's
    %       serializer, and confirm before discarding unsaved work
    %     - keep the window title in step with dirty + current file
    %
    %   WHAT IT MUST NEVER DO
    %     - compute a margin, an area, or a threshold. The engine does that,
    %       and the view renders what comes back (GUI2_SPEC.md Section 6).
    %     - reach into a page's widgets. Cross-page effect goes through
    %       AppState (Section 5).
    %
    %   ERROR HANDLING (GUI2_SPEC.md Section 11): every file/engine call is
    %   wrapped in try/catch INSIDE ITS OWN CALLBACK. A try/catch around
    %   window construction catches nothing thrown later from a callback —
    %   the callback runs from the event loop, not from the constructor.
    %
    %   Launch with gui2.launch.

    properties (Constant, Access = private)
        % Rail geometry.
        RailWidth   = 190
        RailRowH    = 30
        RailSectionH = 26

        % Rail status glyphs — the channel that is SEPARATE from
        % active/idle (GUI2_SPEC.md Section 3).
        GlyphStale  = char(9679)   % filled circle
        GlyphLoaded = char(10003)  % check mark
    end

    properties (SetAccess = private)
        Fig

        % Declared WITHOUT a default. A handle-class property default is
        % evaluated once at class load and SHARED by every instance, so
        % "= gui2.AppState()" would hand every window the same state
        % object. The constructor assigns the real one.
        State gui2.AppState
    end

    properties (Access = private)
        % Layout
        RailGrid
        CardGrid
        StatusLabel
        RecentMenu

        % Pages, in rail order. Struct array:
        %   Section  string — rail section header ("" continues the previous)
        %   Prefix   string — bulk step number shown before the label
        %   Page     gui2.Page
        %   Button   matlab.ui.control.StateButton
        %   Glyph    matlab.ui.control.Label
        Pages = struct('Section', {}, 'Prefix', {}, 'Page', {}, ...
                       'Button', {}, 'Glyph', {})

        % pageId of the page currently shown; "" before the first navigation.
        ActiveId (1,1) string = ""

        % AppState listeners, held so they die with the app.
        Listeners = event.listener.empty(1, 0)
    end

    % ---- Construction -----------------------------------------------------
    methods
        function app = FastenerApp()
            %FASTENERAPP  Build the window; returns once it is on screen.
            app.State = gui2.AppState();

            app.Fig = uifigure('Position', [80 80 1250 820], 'Visible', 'off');
            app.Fig.CloseRequestFcn = @(~, ~) app.onCloseRequest();

            % Library first: the rest of the shell reports its failure, and
            % File > Save refuses while it is unavailable.
            app.State.loadLibrary();

            app.buildMenus();
            app.buildLayout();
            app.buildRail();

            % One listener drives the title; one drives the rail glyphs.
            % Coarse by design — a per-field feed would be the thing
            % Section 5 exists to avoid.
            app.Listeners(end + 1) = event.listener(app.State, ...
                'DirtyChanged', @(~, ~) app.updateTitle());
            for e = ["ResultChanged", "BulkChanged", "ElementsChanged", ...
                     "JointLibraryChanged"]
                app.Listeners(end + 1) = event.listener(app.State, char(e), ...
                    @(~, ~) app.refreshRailGlyphs());
            end

            app.updateTitle();
            app.navigateTo(app.Pages(1).Page.pageId());

            app.Fig.Visible = 'on';

            % Non-blocking, and only AFTER the window is up: a modal dialog
            % during construction would leave the user staring at nothing.
            % While the library is unavailable that failure owns the status
            % bar (see setStatus), so put it there directly — setStatus
            % itself would refuse.
            if strlength(app.State.LibraryLoadError) > 0
                app.StatusLabel.Text = ['Hardware library not loaded — ' ...
                    'saving is disabled until this is fixed.'];
                uialert(app.Fig, char(app.State.LibraryLoadError), ...
                    'Library not loaded');
            end
        end

        function delete(app)
            %DELETE  Close the window when the app object is destroyed.
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end
    end

    % ---- Public shell surface: what pages and tests call ------------------
    methods
        function setStatus(app, msg)
            %SETSTATUS  One-line message in the bottom status bar.
            %   The ONLY way to write the status bar. Pages call this rather
            %   than reaching for the label.
            %
            %   While the hardware library is unavailable, that failure owns
            %   the status bar: no page message may overwrite the one
            %   explanation the user needs. Two independent disable reasons
            %   must not clobber each other (GUI2_HARVEST.md, Shell / File
            %   operations).
            if ~app.State.LibraryOK && strlength(app.State.LibraryLoadError) > 0
                return
            end
            app.StatusLabel.Text = char(msg);
        end

        function navigateTo(app, pageId)
            %NAVIGATETO  Show a page by id. THE one navigation entry point.
            %   Builds the page on first visit, swaps visibility, refreshes
            %   it from AppState, and updates the rail. Nothing else in the
            %   app may touch page visibility or the rail buttons — the
            %   pre-validation dialogs of later steps call this by name
            %   rather than poking widgets (GUI2_SPEC.md Section 4).
            %
            %   Navigation is a DISPLAY action: it must never mark the case
            %   dirty and never invalidate a result (GUI2_HARVEST.md A3/A4).
            arguments
                app    (1,1) gui2.FastenerApp
                pageId (1,1) string
            end
            idx = app.indexOf(pageId);
            if isempty(idx)
                error('gui2:FastenerApp:unknownPage', ...
                    'No page with id "%s".', pageId);
            end

            for i = 1:numel(app.Pages)
                app.Pages(i).Page.setVisible(false);
            end

            entry = app.Pages(idx);
            % Create the card ONLY on first build. Calling newCard() on
            % every navigation would leak an orphan uigridlayout per visit
            % — the page keeps the first one as its Root, and the rest sit
            % in the figure forever.
            if ~entry.Page.IsBuilt
                entry.Page.buildOnce(app.newCard());
            end
            entry.Page.setVisible(true);

            % Refresh AFTER the card is visible so the page sizes its
            % widgets against real geometry.
            try
                entry.Page.refresh();
            catch err
                uialert(app.Fig, err.message, 'Page refresh failed');
            end

            app.ActiveId = pageId;
            app.refreshRailSelection();
            app.refreshRailGlyphs();
        end

        function id = activePageId(app)
            %ACTIVEPAGEID  Id of the page currently shown ("" before the first).
            id = app.ActiveId;
        end

        function p = page(app, pageId)
            %PAGE  The gui2.Page instance for an id. For tests and dialogs.
            idx = app.indexOf(pageId);
            if isempty(idx)
                error('gui2:FastenerApp:unknownPage', ...
                    'No page with id "%s".', pageId);
            end
            p = app.Pages(idx).Page;
        end

        function ids = pageIds(app)
            %PAGEIDS  All page ids, in rail order.
            ids = strings(1, numel(app.Pages));
            for i = 1:numel(app.Pages)
                ids(i) = app.Pages(i).Page.pageId();
            end
        end
    end

    % ---- Layout -----------------------------------------------------------
    methods (Access = private)
        function buildLayout(app)
            %BUILDLAYOUT  Root grid: rail | cards, with the status bar under both.
            root = uigridlayout(app.Fig, [2 2]);
            root.ColumnWidth = {gui2.FastenerApp.RailWidth, '1x'};
            root.RowHeight   = {'1x', 22};
            root.Padding     = [4 4 4 4];
            root.RowSpacing  = 4;
            root.ColumnSpacing = 6;

            app.RailGrid = uigridlayout(root, [1 1]);
            app.RailGrid.Layout.Row    = 1;
            app.RailGrid.Layout.Column = 1;
            app.RailGrid.Padding       = [0 0 0 0];
            app.RailGrid.RowSpacing    = 2;
            app.RailGrid.ColumnWidth   = {'1x'};
            app.RailGrid.Scrollable    = 'on';

            % Every page's card occupies THE SAME single cell of this grid.
            % One cell plus Visible toggling is what makes navigation a
            % property write rather than a relayout.
            app.CardGrid = uigridlayout(root, [1 1]);
            app.CardGrid.Layout.Row    = 1;
            app.CardGrid.Layout.Column = 2;
            app.CardGrid.Padding       = [0 0 0 0];
            app.CardGrid.RowHeight     = {'1x'};
            app.CardGrid.ColumnWidth   = {'1x'};

            app.StatusLabel = uilabel(root, 'Text', '', ...
                'HorizontalAlignment', 'left');
            app.StatusLabel.Layout.Row    = 2;
            app.StatusLabel.Layout.Column = [1 2];
        end

        function g = newCard(app)
            %NEWCARD  A fresh container for a page to build into.
            %   Called ONCE per page, on first navigation. All cards share
            %   the same single grid cell; only one is ever visible, so
            %   navigation is a property write rather than a relayout.
            g = uigridlayout(app.CardGrid, [1 1]);
            g.Layout.Row    = 1;
            g.Layout.Column = 1;
            g.Padding       = [0 0 0 0];
            g.RowHeight     = {'1x'};
            g.ColumnWidth   = {'1x'};
            g.Visible       = 'off';
        end
    end

    % ---- The rail ---------------------------------------------------------
    methods (Access = private)
        function specs = pageSpecs(app)
            %PAGESPECS  The rail contents, in order (GUI2_SPEC.md Section 3).
            %   Section: header text; "" continues the previous section.
            %   Prefix:  the bulk step number. The rail is the ONE place the
            %            1-4 scheme lives — no page or status hint may
            %            restate it with different numbers.
            %
            %   Bolt Sizing is deliberately absent. Help is on the menu bar,
            %   not the rail.
            %
            %   Step 1 ships the shell only, so every entry is a
            %   PlaceholderPage naming the step that replaces it. Steps 2+
            %   swap real gui2.Page subclasses in here one at a time; the
            %   ids are the contract and must not change.
            s = app.State;
            specs = { ...
                "SETUP",        "", gui2.PlaceholderPage(s, "Project",     "Project",                      2); ...
                "",             "", gui2.PlaceholderPage(s, "Factors",     "Factors",                      2); ...
                "",             "", gui2.PlaceholderPage(s, "TempLoads",   "Temp Loads",                   2); ...
                "SINGLE JOINT", "", gui2.PlaceholderPage(s, "JointConfig", "Joint Config",                 3); ...
                "",             "", gui2.PlaceholderPage(s, "Results",     "Single Joint Results",         4); ...
                "BULK",        "1", gui2.PlaceholderPage(s, "DefinedJoints", "Defined Joints Library",     5); ...
                "",            "2", gui2.PlaceholderPage(s, "ElementMapping", "Element Mapping",           6); ...
                "",            "3", gui2.PlaceholderPage(s, "ElementForces", "Element Forces",             7); ...
                "",            "4", gui2.PlaceholderPage(s, "BulkAnalysis", "Bulk Analysis",               8); ...
                "REFERENCE",    "", gui2.PlaceholderPage(s, "HardwareLibrary", "Materials & Hardware Library", 9)};
        end

        function buildRail(app)
            %BUILDRAIL  Section headers and one state button per page.
            %   Section headers are uilabels, so they cannot be selected —
            %   the thing neither a uitabgroup nor a uilistbox can do
            %   cleanly (GUI2_SPEC.md Section 3).
            specs = app.pageSpecs();
            n = size(specs, 1);

            % Row plan first: a header row for each named section, then one
            % row per page, then a filler row that absorbs slack so the
            % items stay pinned to the top.
            heights = {};
            rows    = zeros(1, n);
            for i = 1:n
                if strlength(specs{i, 1}) > 0
                    heights{end + 1} = gui2.FastenerApp.RailSectionH; %#ok<AGROW>
                end
                heights{end + 1} = gui2.FastenerApp.RailRowH; %#ok<AGROW>
                rows(i) = numel(heights);
            end
            heights{end + 1} = '1x';
            app.RailGrid.RowHeight = heights;

            % Two columns: the label button, and the status-glyph label.
            app.RailGrid.ColumnWidth = {'1x', 18};

            for i = 1:n
                section = specs{i, 1};
                prefix  = specs{i, 2};
                pg      = specs{i, 3};

                if strlength(section) > 0
                    lbl = uilabel(app.RailGrid, 'Text', char(section));
                    lbl.FontSize  = 10;
                    lbl.FontColor = gui2.palette('navSectionFg');
                    lbl.FontWeight = 'bold';
                    lbl.VerticalAlignment = 'bottom';
                    lbl.Layout.Row    = rows(i) - 1;
                    lbl.Layout.Column = [1 2];
                end

                if strlength(prefix) > 0
                    label = sprintf('%s  %s', prefix, pg.title());
                else
                    label = char(pg.title());
                end

                % A STATE button, not a push button: MATLAB renders the
                % pressed state natively, so the active item adapts to the
                % viewer's light/dark theme. A hand-picked BackgroundColor
                % would not.
                b = uibutton(app.RailGrid, 'state', 'Text', label);
                b.HorizontalAlignment = 'left';
                b.FontColor = gui2.palette('navIdleFg');
                b.Layout.Row    = rows(i);
                b.Layout.Column = 1;
                % Capture the ID STRING, not the page handle: the callback
                % should not keep a reference to the object it navigates to,
                % and steps 2+ replace these page objects wholesale.
                id = pg.pageId();
                b.ValueChangedFcn = @(s, ~) app.onRailClicked(s, id);

                % The status glyph: the rail's SECOND channel. Blank until
                % a page reports "stale" or "loaded".
                gl = uilabel(app.RailGrid, 'Text', '', ...
                    'HorizontalAlignment', 'center');
                gl.Layout.Row    = rows(i);
                gl.Layout.Column = 2;

                app.Pages(end + 1) = struct( ...
                    'Section', section, 'Prefix', prefix, ...
                    'Page', pg, 'Button', b, 'Glyph', gl);
            end
        end

        function onRailClicked(app, btn, pageId)
            %ONRAILCLICKED  Rail item pressed.
            %   A state button toggles itself, so clicking the ALREADY
            %   active item would otherwise un-press it and leave the rail
            %   showing no selection while the page is still on screen.
            %   Re-assert and stop.
            if strcmp(app.ActiveId, pageId)
                btn.Value = true;
                return
            end
            app.navigateTo(pageId);
        end

        function refreshRailSelection(app)
            %REFRESHRAILSELECTION  Radio-group behaviour + the bold accent.
            %   Active is pressed AND bold. Colour is not used here: it
            %   belongs to the status glyph, and if both channels used
            %   colour a stale-but-active item would read as neither
            %   (GUI2_SPEC.md Section 3).
            for i = 1:numel(app.Pages)
                isActive = strcmp(app.Pages(i).Page.pageId(), app.ActiveId);
                app.Pages(i).Button.Value = isActive;
                if isActive
                    app.Pages(i).Button.FontWeight = 'bold';
                    app.Pages(i).Button.FontColor  = gui2.palette('navActiveFg');
                else
                    app.Pages(i).Button.FontWeight = 'normal';
                    app.Pages(i).Button.FontColor  = gui2.palette('navIdleFg');
                end
            end
        end

        function refreshRailGlyphs(app)
            %REFRESHRAILGLYPHS  Ask every page for its status glyph.
            %   Cheap: railStatus() reads AppState flags and returns a
            %   string. Pages that have never been built still answer, so
            %   the rail can show that Element Forces holds data before the
            %   user has ever opened it.
            for i = 1:numel(app.Pages)
                switch app.Pages(i).Page.railStatus()
                    case "stale"
                        app.Pages(i).Glyph.Text = gui2.FastenerApp.GlyphStale;
                        app.Pages(i).Glyph.FontColor = gui2.palette('navStaleFg');
                    case "loaded"
                        app.Pages(i).Glyph.Text = gui2.FastenerApp.GlyphLoaded;
                        app.Pages(i).Glyph.FontColor = gui2.palette('navLoadedFg');
                    otherwise
                        app.Pages(i).Glyph.Text = '';
                end
            end
        end

        function idx = indexOf(app, pageId)
            %INDEXOF  Position of a page id in the rail, or [] if unknown.
            idx = [];
            for i = 1:numel(app.Pages)
                if strcmp(app.Pages(i).Page.pageId(), pageId)
                    idx = i;
                    return
                end
            end
        end
    end

    % ---- Menus ------------------------------------------------------------
    methods (Access = private)
        function buildMenus(app)
            %BUILDMENUS  File / Help (GUI2_SPEC.md Section 4).
            %   There is deliberately NO "Load Example Case" item. The DABJ
            %   fixture served its purpose as the validated answer key, and
            %   a menu slip away from overwriting real work is the wrong
            %   place for it — it stays reachable from the command line via
            %   validation.dabjSection9.
            mFile = uimenu(app.Fig, 'Text', 'File');
            uimenu(mFile, 'Text', 'New', 'Accelerator', 'N', ...
                'MenuSelectedFcn', @(~, ~) app.onFileNew());
            uimenu(mFile, 'Text', 'Open...', 'Accelerator', 'O', ...
                'MenuSelectedFcn', @(~, ~) app.onFileOpen());
            app.RecentMenu = uimenu(mFile, 'Text', 'Open Recent');
            uimenu(mFile, 'Text', 'Save', 'Accelerator', 'S', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.onFileSave());
            uimenu(mFile, 'Text', 'Save As...', ...
                'MenuSelectedFcn', @(~, ~) app.onFileSaveAs());
            app.rebuildRecentMenu();

            mHelp = uimenu(app.Fig, 'Text', 'Help');
            uimenu(mHelp, 'Text', 'About', ...
                'MenuSelectedFcn', @(~, ~) app.onHelpAbout());
        end

        function rebuildRecentMenu(app)
            %REBUILDRECENTMENU  Open Recent: max 5, dead paths filtered.
            %   Rebuilt from scratch every time, never appended to — an
            %   accumulated menu is the same class of bug as accumulated
            %   table styles.
            delete(app.RecentMenu.Children);
            files = gui2.recentFiles();
            if isempty(files)
                % Name the absence rather than showing an empty submenu
                % (GUI2_HARVEST.md A12).
                m = uimenu(app.RecentMenu, 'Text', '(no recent files)');
                m.Enable = 'off';
                return
            end
            for i = 1:numel(files)
                f = files(i);
                uimenu(app.RecentMenu, 'Text', char(f), ...
                    'MenuSelectedFcn', @(~, ~) app.openPath(f));
            end
        end

        function onHelpAbout(app)
            %ONHELPABOUT  Version and scope, as a plain info alert.
            %   States the check scope explicitly: this build displays 9 of
            %   the engine's 15 checks, and a user must never have to
            %   discover that (GUI2_SPEC.md Section 2).
            msg = sprintf([ ...
                'Fastener Analysis Tool (MATLAB) v%s\n' ...
                'NASA-STD-5020B bolted-joint margins.\n\n' ...
                'Displays 9 of the 15 checks the engine computes; the ' ...
                'other 6 are computed and not displayed. Every results ' ...
                'view and export names them.\n\n' ...
                'Case files: JSON, format "%s".'], ...
                app.State.ToolVersion, app.State.CaseFormat);
            uialert(app.Fig, msg, 'About — Fastener Analysis Tool', 'Icon', 'info');
        end
    end

    % ---- File operations --------------------------------------------------
    methods (Access = private)
        function onFileNew(app)
            %ONFILENEW  Reset to a genuinely blank case.
            %   Confirms whenever dirty — INCLUDING when no file is open.
            %   Unsaved edits are just as real before the case has a
            %   filename, and skipping that case is the classic way File >
            %   New silently destroys work.
            if ~app.confirmDiscard('starting a new case')
                return
            end
            app.State.newCase();
            app.setStatus(['New case — choose a bolt and materials on ' ...
                'Joint Config to begin.']);
        end

        function onFileOpen(app)
            %ONFILEOPEN  Pick a case file and load it.
            %   Confirms BEFORE the file picker. Asking after the user has
            %   chosen a file, then refusing, wastes the choice they just
            %   made.
            if ~app.confirmDiscard('opening another case')
                return
            end
            [f, p] = uigetfile('*.json', 'Open Case');
            if isequal(f, 0)
                return
            end
            app.loadPath(string(fullfile(p, f)));
        end

        function openPath(app, file)
            %OPENPATH  Confirm, then load. The Open Recent entry point.
            %   Open Recent bypasses onFileOpen, so the confirm lives here
            %   too — but loadPath must NOT confirm, or File > Open would
            %   ask twice.
            if ~app.confirmDiscard('opening another case')
                return
            end
            app.loadPath(file);
        end

        function loadPath(app, file)
            %LOADPATH  Load a case from a known path. Assumes discard is agreed.
            %   Its own try/catch: this runs from a menu callback, so an
            %   outer try/catch around construction would never see the
            %   error (GUI2_SPEC.md Section 11).
            arguments
                app  (1,1) gui2.FastenerApp
                file (1,1) string
            end
            if ~isfile(file)
                uialert(app.Fig, sprintf( ...
                    'No longer on disk:\n%s', file), 'Open failed');
                gui2.recentFiles('remove', file);
                app.rebuildRecentMenu();
                return
            end
            try
                st = gui2.AppState.readCaseFile(file);
            catch err
                uialert(app.Fig, err.message, 'Open failed');
                return
            end
            app.State.applyCaseStruct(st);
            app.State.clearDirty(file);
            gui2.recentFiles('add', file);
            app.rebuildRecentMenu();
            app.setStatus(sprintf('Opened %s', file));

            % NOTE (step 3): the first build reported the library keys a
            % case referenced but the library does not have, leaving
            % required material dropdowns blank rather than substituting.
            % That check belongs to the pages that own those dropdowns and
            % lands with Joint Config — see GUI2_HARVEST.md, Shell / File
            % operations, "File > Open".
        end

        function onFileSave(app)
            %ONFILESAVE  Save to the current file; falls through to Save As.
            if strlength(app.State.CurrentFile) == 0
                app.onFileSaveAs();
                return
            end
            app.saveToFile(app.State.CurrentFile);
        end

        function onFileSaveAs(app)
            %ONFILESAVEAS  Pick a path and save; the extension is appended.
            [f, p] = uiputfile('*.json', 'Save Case As', 'case.json');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));
            if ~endsWith(file, ".json", "IgnoreCase", true)
                file = file + ".json";
            end
            app.saveToFile(file);
        end

        function saveToFile(app, file)
            %SAVETOFILE  Serialize the case and write it.
            %   Refuses while the hardware library is unavailable: the joint
            %   cannot be fully serialized, and a partial file is worse than
            %   none.
            if ~app.State.LibraryOK
                uialert(app.Fig, ['Cannot save: the hardware library failed ' ...
                    'to load, so the case cannot be serialized.'], 'Save failed');
                return
            end
            try
                container = app.State.toCaseStruct();
                gui2.AppState.writeCaseFile(container, file);
            catch err
                uialert(app.Fig, err.message, 'Save failed');
                return
            end
            app.State.clearDirty(file);
            gui2.recentFiles('add', file);
            app.rebuildRecentMenu();
            app.setStatus(sprintf('Saved %s', file));
        end

        function tf = confirmDiscard(app, actionText)
            %CONFIRMDISCARD  True when it is safe to destroy unsaved edits.
            %   Asks only when dirty, but ALWAYS when dirty — including with
            %   no file open. Cancel is both the default (Enter) and the
            %   Esc/close action: destroying work must never be the path of
            %   least resistance.
            if ~app.State.IsDirty
                tf = true;
                return
            end
            choice = string(uiconfirm(app.Fig, sprintf( ...
                'You have unsaved changes. Discard them before %s?', actionText), ...
                'Unsaved Changes', ...
                'Options',       {'Discard Changes', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'Icon',          'question'));
            tf = (choice == "Discard Changes");
        end

        function onCloseRequest(app)
            %ONCLOSEREQUEST  Confirm before closing away unsaved changes.
            if ~app.confirmDiscard('closing')
                return
            end
            delete(app);
        end
    end

    % ---- Title ------------------------------------------------------------
    methods (Access = private)
        function updateTitle(app)
            %UPDATETITLE  Window title from CurrentFile + IsDirty.
            %   Version when nothing is open, the file path when a case is,
            %   prefixed "* " when dirty (GUI2_SPEC.md Section 4).
            if strlength(app.State.CurrentFile) == 0
                t = sprintf('Fastener Analysis Tool v%s — NASA-STD-5020B', ...
                    app.State.ToolVersion);
            else
                t = sprintf('Fastener Analysis Tool — %s', app.State.CurrentFile);
            end
            if app.State.IsDirty
                t = ['* ' t];
            end
            app.Fig.Name = t;
        end
    end
end
