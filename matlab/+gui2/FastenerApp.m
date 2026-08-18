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
        RailWidth   = 160
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
        StatusBox
        SummaryLabel
        RecentMenu

        % The References window (gui2.ReferencesView). Owns its own
        % uifigure, which cannot be a child of app.Fig, so closing the app
        % does not close it -- delete() below does, the same arrangement
        % the pages' dialogs use.
        ReferencesView

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

        % The joint cross-section window. A SINGLETON owned here rather than
        % by Joint Config: it is a window, it outlives the page that opened
        % it, and one per button press would litter the desktop.
        SectionView = gui2.JointSectionView.empty
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

            for e = ["FactorsChanged", "SettingsChanged"]
                app.Listeners(end + 1) = event.listener(app.State, char(e), ...
                    @(~, ~) app.refreshSummary());
            end

            app.updateTitle();
            app.refreshSummary();
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
            %   Listeners go first and independently: one that throws while
            %   being torn down must not stop the figure being destroyed,
            %   or the window survives its own app object and can never be
            %   closed again.
            try
                delete(app.Listeners(isvalid(app.Listeners)));
            catch
            end
            % The References window, for the same reason the pages below
            % need explicit deletion: it is a handle object owning a
            % uifigure, not a child of app.Fig, so it would otherwise
            % survive the app that opened it and stand there unclosable.
            try
                if ~isempty(app.ReferencesView) && isvalid(app.ReferencesView)
                    delete(app.ReferencesView);
                end
            catch
            end
            % Pages can own windows of their own — Element Mapping's paste
            % dialog — and a page is a handle object, not a child of the
            % figure, so destroying the window does not destroy the page.
            % MATLAB would run each page's destructor whenever the
            % collector next gets round to it, which is why a closed app
            % could leave dialogs standing on screen. Delete them here so
            % their windows go now rather than eventually. Individually
            % wrapped, for the same reason the listeners are.
            for i = 1:numel(app.Pages)
                try
                    if isvalid(app.Pages(i).Page)
                        delete(app.Pages(i).Page);
                    end
                catch
                end
            end
            % The section window is a separate figure and would otherwise
            % outlive the app that feeds it, repainting from an AppState
            % nothing else references any more.
            if ~isempty(app.SectionView) && isvalid(app.SectionView)
                delete(app.SectionView);
            end
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end

        function showSection(app)
            %SHOWSECTION  Open the joint cross-section window, or raise it.
            %   Reconstructs after the user has closed the window: the view
            %   deletes itself on close, so a stale handle here means gone,
            %   not hidden.
            if isempty(app.SectionView) || ~isvalid(app.SectionView)
                app.SectionView = gui2.JointSectionView(app.State);
            end
            app.SectionView.show();
        end
    end

    % ---- Static helpers ---------------------------------------------------
    methods (Static, Access = private)
        function v = settingNum(st, name)
            %SETTINGNUM  One numeric field of AppState.Settings, or NaN.
            %   Tolerant on purpose: a case file written by an older build
            %   can be missing a field, and the summary bar must degrade to
            %   NaN rather than throw and take the whole window with it.
            if isstruct(st) && isfield(st, name)
                v = double(st.(name));
            else
                v = NaN;
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
            % Tint the band while it has something to say. A status line
            % that looks identical whether or not it carries a message gets
            % read as chrome and stopped being looked at - the colour is
            % what makes a new message register without an animation.
            app.tintStatus(strlength(strtrim(string(msg))) > 0);
        end

        function refreshSummary(app)
            %REFRESHSUMMARY  Repaint the always-visible factors/temps bar.
            %   Public so tests can assert on it without a gesture, and so
            %   a later page can force a repaint after a bulk state swap.
            if isempty(app.SummaryLabel) || ~isvalid(app.SummaryLabel)
                return
            end
            f = app.State.Factors;

            % Unequal fitting factors must NOT render as a single number —
            % that would state a value the case does not hold (the summary
            % equivalent of GUI2_HARVEST.md A1). Name the mixed set instead.
            ff = [f.FFU, f.FFY, f.FFSep, f.FFSlip];
            if all(ff == ff(1))
                ffTxt = sprintf('FF %g', ff(1));
            else
                ffTxt = sprintf('FF mixed %g/%g/%g/%g', ff(1), ff(2), ff(3), ff(4));
            end

            degC = [char(176) 'C'];
            s = app.State.Settings;
            app.SummaryLabel.Text = sprintf( ...
                ['%s     FS:  yield %g · ult %g · sep %g · slip %g' ...
                 '     Temp:  nom %g · hot %g · cold %g %s'], ...
                ffTxt, f.FSY, f.FSU, f.FSSep, f.FSSlip, ...
                gui2.FastenerApp.settingNum(s, 'NominalTempC'), ...
                gui2.FastenerApp.settingNum(s, 'HotTempC'), ...
                gui2.FastenerApp.settingNum(s, 'ColdTempC'), degC);
        end

        function tintStatus(app, active)
            %TINTSTATUS  Highlight the status band when it carries a message.
            if isempty(app.StatusBox) || ~isvalid(app.StatusBox)
                return
            end
            if active
                app.StatusBox.BackgroundColor = gui2.palette('statusActiveBg');
                app.StatusLabel.FontColor     = gui2.palette('statusActiveFg');
            else
                app.StatusBox.BackgroundColor = gui2.palette('footerBg');
                app.StatusLabel.FontColor     = gui2.palette('mutedText');
            end
        end

        function t = summaryText(app)
            %SUMMARYTEXT  Current text of the always-live summary bar.
            %   A read-only seam for tests, so they assert on what the bar
            %   actually shows rather than re-deriving it.
            t = string(app.SummaryLabel.Text);
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
            root = uigridlayout(app.Fig, [3 2]);
            root.ColumnWidth = {gui2.FastenerApp.RailWidth, '1x'};
            root.RowHeight   = {'1x', 26, 26};
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

            % Transient messages sit directly under the content; the
            % always-live summary is the bottom-most band. Ordering matters:
            % the status line changes, the footer does not, and a changing
            % line below a static one reads as the page shifting.
            % Ruled top and bottom. The status line sits between the page
            % content and the always-live footer, and three unbounded bands
            % of text stacked at the foot of the window read as one blurred
            % region - the rules are what make it three things.
            statusBox = uipanel(root, 'BorderType', 'line', ...
                'BorderColor', gui2.palette('rule'));
            app.StatusBox = statusBox;
            statusBox.Layout.Row    = 2;
            statusBox.Layout.Column = [1 2];
            sg = uigridlayout(statusBox, [1 1]);
            sg.RowHeight   = {'1x'};
            sg.ColumnWidth = {'1x'};
            sg.Padding     = [8 0 8 0];

            app.StatusLabel = uilabel(sg, 'Text', '', ...
                'HorizontalAlignment', 'left');
            app.StatusLabel.Layout.Row    = 1;
            app.StatusLabel.Layout.Column = 1;

            % Always-live summary of the factors and temperatures every
            % analysis on every page runs with. These are global, they are
            % edited two pages away from where they are used, and there is
            % no other way to see them without navigating off whatever you
            % are doing. Read-only: this bar shows state, it never sets it.
            %
            % A filled band pinned to the bottom, not a bare label: two
            % unstyled text rows stacked at the foot of the window read as
            % a layout mistake rather than as chrome.
            footer = uipanel(root, 'BorderType', 'none', ...
                'BackgroundColor', gui2.palette('footerBg'));
            footer.Layout.Row    = 3;
            footer.Layout.Column = [1 2];
            fg = uigridlayout(footer, [1 1]);
            fg.RowHeight   = {'1x'};
            fg.ColumnWidth = {'1x'};
            fg.Padding     = [8 0 8 0];

            % Centered: the band spans the full window, and right-justified
            % text in a full-width band leaves a large dead area on the
            % left. 'right' is a one-word change if that reads better.
            app.SummaryLabel = uilabel(fg, 'Text', '', ...
                'HorizontalAlignment', 'center');
            app.SummaryLabel.Layout.Row    = 1;
            app.SummaryLabel.Layout.Column = 1;
            app.SummaryLabel.FontColor     = gui2.palette('footerFg');
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
            %   Step 1 shipped the shell with a PlaceholderPage naming the
            %   step that replaces it. Step 2 swaps in the three setup
            %   pages below; steps 3+ do the same for the rest, one at a
            %   time. The ids are the contract and must not change.
            s = app.State;
            specs = { ...
                "SETUP",        "", gui2.ProjectPage(s); ...
                "",             "", gui2.FactorsPage(s); ...
                "",             "", gui2.TempLoadsPage(s); ...
                "SINGLE JOINT", "", gui2.JointConfigPage(s); ...
                "",             "", gui2.ResultsPage(s); ...
                "BULK",        "1", gui2.DefinedJointsPage(s); ...
                "",            "2", gui2.ElementMappingPage(s); ...
                "",            "3", gui2.ElementForcesPage(s); ...
                "",            "4", gui2.BulkAnalysisPage(s); ...
                "REFERENCE",    "", gui2.HardwareLibraryPage(s)};
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

                % The page's only route back into the shell. A function
                % handle, not the app: a page that held the app could reach
                % the rail and other pages' widgets, which Section 5 forbids.
                pg.attachStatus(@(m) app.setStatus(m));
                pg.attachNavigate(@(id) app.navigateTo(id));
                pg.attachShowSection(@() app.showSection());

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
            uimenu(mHelp, 'Text', 'User Guide', ...
                'MenuSelectedFcn', @(~, ~) app.onHelpUserGuide());
            uimenu(mHelp, 'Text', 'References...', ...
                'MenuSelectedFcn', @(~, ~) app.onHelpReferences());
            uimenu(mHelp, 'Text', 'About', 'Separator', 'on', ...
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
            %   STATES THE CHECK SCOPE, and it used to state it wrongly:
            %   "displays 9 of the 15 checks ... the other 6 are computed
            %   and not displayed" was true of the first build and false
            %   from the moment the results table showed all 15. A dialog
            %   whose whole job is telling the analyst what the tool does
            %   and does not cover is the worst place in the app for a
            %   stale claim about coverage, so it is corrected here rather
            %   than left for a reader to catch.
            msg = sprintf([ ...
                'Fastener Analysis Tool (MATLAB) v%s\n' ...
                'NASA-STD-5020B bolted-joint margins.\n\n' ...
                'Displays all 15 checks the engine computes: 14 margin ' ...
                'rows plus the Fig. 8 separation-before-rupture gate, ' ...
                'which selects a branch rather than carrying a margin.\n\n' ...
                'Case files: JSON, format "%s".'], ...
                toolVersion(), app.State.CaseFormat);
            uialert(app.Fig, msg, 'About — Fastener Analysis Tool', 'Icon', 'info');
        end

        function onHelpUserGuide(app)
            %ONHELPUSERGUIDE  Build the guide PDF if needed, then open it.
            %   IT USED TO OPEN USER_GUIDE.md. Handing an analyst a .md
            %   file is wrong twice over -- on Windows it opens in Notepad
            %   or in nothing, and it reads as source rather than as a
            %   document -- and the content was wrong too: that file's
            %   workflows are typed at the Command Window, which someone
            %   running the packaged app never sees. report.userGuide
            %   writes a PDF about the application instead.
            %
            %   GENERATED, NOT SHIPPED. Report Generator is already a
            %   dependency, so this costs the build nothing, removes a
            %   file from the mcc line, and cannot go stale: the guide is
            %   produced by the version that is running.
            %
            %   Cached per version, so only the first open waits.
            f = report.userGuide();
            if ~isfile(f)
                d = uiprogressdlg(app.Fig, 'Indeterminate', 'on', ...
                    'Title', 'User guide', ...
                    'Message', 'Building the guide (first open only)...');
                closer = onCleanup(@() delete(d)); %#ok<NASGU>
                try
                    f = report.userGuide(f);
                catch err
                    clear closer
                    uialert(app.Fig, sprintf([ ...
                        'Could not build the user guide.\n\n%s'], ...
                        err.message), 'User guide', 'Icon', 'warning');
                    return
                end
            end
            gui2.openExternal(f, app.Fig);
        end

        function onHelpReferences(app)
            %ONHELPREFERENCES  The documents this tool's numbers rest on.
            %   Create-or-focus: the view owns its own uifigure and raises
            %   it rather than opening a second one.
            if isempty(app.ReferencesView) || ~isvalid(app.ReferencesView)
                app.ReferencesView = gui2.ReferencesView();
            end
            app.ReferencesView.show();
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
            app.confirmDiscard('starting a new case', @() app.commitNewCase());
        end

        function commitNewCase(app)
            %COMMITNEWCASE  The blank case, once discarding is agreed.
            app.State.newCase();
            app.setStatus(['New case — choose a bolt and materials on ' ...
                'Joint Config to begin.']);
        end

        function onFileOpen(app)
            %ONFILEOPEN  Pick a case file and load it.
            %   Confirms BEFORE the file picker. Asking after the user has
            %   chosen a file, then refusing, wastes the choice they just
            %   made.
            app.confirmDiscard('opening another case', @() app.pickAndOpen());
        end

        function pickAndOpen(app)
            %PICKANDOPEN  The file picker, once discarding is agreed.
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
            app.confirmDiscard('opening another case', @() app.loadPath(file));
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

        function confirmDiscard(app, actionText, onProceed)
            %CONFIRMDISCARD  Run onProceed once destroying unsaved edits is agreed.
            %   Asks only when dirty, but ALWAYS when dirty — including with
            %   no file open. Cancel is both the default (Enter) and the
            %   Esc/close action: destroying work must never be the path of
            %   least resistance.
            %
            %   CONTINUATION-PASSING, and it has to be. This used the
            %   BLOCKING uiconfirm - the form that returns a choice - which
            %   halts execution inside the callback until a human answers.
            %   That deadlocks any programmatic driver, including the App
            %   Testing Framework: the test cannot reach its answer because
            %   the press that opened the dialog has never returned. Nothing
            %   exercised File > New, so it sat silent; the first test to
            %   touch it would have hung the whole ~8-minute run.
            %
            %   The consequence is that this CANNOT return a boolean - the
            %   answer arrives later, through the event. Every caller passes
            %   what it wants done instead. Matches DefinedJointsPage and
            %   JointConfigPage, which already use the CloseFcn form.
            if ~app.State.IsDirty
                onProceed();
                return
            end
            uiconfirm(app.Fig, sprintf( ...
                'You have unsaved changes. Discard them before %s?', actionText), ...
                'Unsaved Changes', ...
                'Options',       {'Discard Changes', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'Icon',          'question', ...
                'CloseFcn', @(~, evt) app.onDiscardAnswered(evt, onProceed));
        end

        function onDiscardAnswered(~, evt, onProceed)
            %ONDISCARDANSWERED  Run the continuation only on an explicit Discard.
            %   Every other way out of the dialog - Cancel, Esc, the close
            %   box - leaves the work alone. Anything but an exact match on
            %   'Discard Changes' is treated as Cancel, so a dialog dismissed
            %   by its figure being destroyed at test teardown can never
            %   discard a case on its way out.
            if strcmp(evt.SelectedOption, 'Discard Changes')
                onProceed();
            end
        end

        function onCloseRequest(app)
            %ONCLOSEREQUEST  Confirm before closing away unsaved changes.
            %   The prompt is wrapped: anything that throws in here - a
            %   half-built AppState, a listener firing during teardown -
            %   would otherwise abort the callback and leave the window
            %   with no way to close it. A user must always be able to
            %   quit; the worst case is losing the confirmation, not being
            %   trapped in the application.
            %
            %   Note the shape change: the window no longer closes when this
            %   returns, because with a dirty case it returns while the
            %   question is still on screen. Closing IS the continuation.
            try
                app.confirmDiscard('closing', @() app.closeNow());
            catch err
                warning('gui2:FastenerApp:closePromptFailed', ...
                    'Unsaved-changes prompt failed (%s); closing anyway.', ...
                    err.message);
                app.closeNow();
            end
        end

        function closeNow(app)
            %CLOSENOW  Destroy the app. Guarded so a double call is harmless.
            %   The catch above can reach here after the try already did.
            if isvalid(app)
                delete(app);
            end
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
                    toolVersion());
            else
                t = sprintf('Fastener Analysis Tool — %s', app.State.CurrentFile);
            end
            if app.State.IsDirty
                t = ['* ' t];
            end
            app.Fig.Name = t;
        end
    end

    % ---- Test seams -------------------------------------------------------
    %   File > New is reachable from a test ONLY because confirmDiscard is
    %   now the CloseFcn form: the call returns while the question is still
    %   on screen. Under the blocking form these seams would have hung the
    %   run rather than exposed anything.
    %
    %   Following the suite's rule (tGui2DefinedJoints, "Load / rename /
    %   delete"), tests DO NOT answer the dialog - they assert that nothing
    %   changed while the question is outstanding, and let the dialog die
    %   with the figure at teardown.
    methods
        function v = openReferences(app)
            %OPENREFERENCES  Help > References, without the menu gesture.
            %   matlab.uitest cannot select a menu item, and cannot press a
            %   control on the main window while a second uifigure holds
            %   focus, so the window is opened and inspected through seams.
            app.onHelpReferences();
            v = app.ReferencesView;
        end

        function v = referencesView(app)
            %REFERENCESVIEW  The window handle, or empty if never opened.
            v = app.ReferencesView;
        end

        function items = helpMenuItems(app)
            %HELPMENUITEMS  The Help menu's item labels, in order.
            items = strings(1, 0);
            for m = app.Fig.Children'
                if isa(m, 'matlab.ui.container.Menu') && strcmp(m.Text, 'Help')
                    % Children come back in reverse creation order.
                    kids = flip(m.Children);
                    for k = kids'
                        items(end+1) = string(k.Text); %#ok<AGROW>
                    end
                end
            end
        end

        function requestFileNew(app)
            app.onFileNew();
        end

        function requestOpenPath(app, file)
            app.openPath(file);
        end

        function v = sectionView(app)
            v = app.SectionView;
        end
    end
end
