classdef (Abstract) Page < handle
    %PAGE  Base class for every page in the left rail (GUI2_SPEC.md Section 5).
    %   A page owns one card in the shell's content area. It holds a
    %   reference to the shared gui2.AppState, reads and writes it directly,
    %   and listens for the coarse AppState events it cares about.
    %
    %   PAGES NEVER TALK TO EACH OTHER. All cross-page effect goes through
    %   AppState. A page that reaches for another page is the bug the first
    %   build's 11,945-line class was made of.
    %
    %   VIEWS ARE PLAIN HANDLE CLASSES, not
    %   matlab.ui.componentcontainer.ComponentContainer. That class exists
    %   to make REUSABLE components that drop into App Designer; every page
    %   here is a singleton built in code, so it would be ceremony with no
    %   payoff. The Model half of MVC — one handle class, events, no
    %   view-to-view coupling — is adopted in full (GUI2_SPEC.md Section 5).
    %
    %   THE CONTRACT — five methods, of which subclasses must implement
    %   three:
    %       pageId()          string, stable id used by navigateTo. Never
    %                         change one: pre-validation dialogs and tests
    %                         name pages by it.
    %       title()           string, the rail label
    %       build(parent)     construct into the given grid cell, ONCE
    %       refresh()         re-read AppState; idempotent and cheap
    %       railStatus()      "" | "stale" | "loaded" — the rail glyph
    %
    %   LAZY CONSTRUCTION (GUI2_SPEC.md Section 10 rule 1): build() is
    %   called on FIRST NAVIGATION, not at startup. A meaningful share of
    %   users run over Remote Desktop, where render cost is the binding
    %   constraint; building ten pages' worth of widgets into the first
    %   paint is the single most expensive thing the shell could do. The
    %   shell guarantees build() runs at most once — subclasses must not
    %   defend against a second call, and must not do work in a constructor
    %   that belongs in build().
    %
    %   REFRESH MUST BE CHEAP AND IDEMPOTENT. It runs on every navigation to
    %   the page and on every event the page subscribes to. It must never
    %   call state.markDirty(): refreshing is reading, and a dirty flag set
    %   by a refresh is a lie (GUI2_HARVEST.md A4).

    properties (Constant)
        % Header height of a collapsible group, px. A collapsed group is
        % exactly this tall.
        GroupHeaderH = 24
    end

    properties (SetAccess = immutable, GetAccess = protected)
        % The one shared model. Immutable: a page is bound to its AppState
        % at construction and can never be repointed at another.
        %
        % Declared WITHOUT a (1,1) size constraint on purpose. A handle-class
        % property with size (1,1) and no explicit default makes MATLAB
        % default-construct one at class load and SHARE it across every
        % instance. The constructor assigns the real, scalar state.
        State gui2.AppState
    end

    properties (SetAccess = private)
        % True once build() has run. The shell reads this to decide whether
        % a navigation needs construction; nothing else should touch it.
        IsBuilt (1,1) logical = false
    end

    properties (Access = private)
        % Route to the shell's status bar, injected by gui2.FastenerApp via
        % attachStatus. A page never holds a reference to the app itself —
        % that would let it reach the rail and other pages' widgets, which
        % Section 5 forbids. One function handle is the whole contract.
        %
        % Empty until attached, so a page constructed outside a shell (a
        % unit test building one in isolation) still works: setStatus is a
        % no-op rather than an error.
        StatusFcn = function_handle.empty

        % Route to the shell's navigation, injected the same way and for
        % the same reason: a page that held the app could reach the rail
        % and other pages' widgets, which Section 5 forbids.
        NavigateFcn = function_handle.empty

        % Route to the shell's secondary windows. A window outlives the
        % page that opened it and must be a singleton, so the shell owns
        % it — a page that constructed its own would leak one per press.
        ShowSectionFcn = function_handle.empty
    end

    properties (Access = protected)
        % The container build() was given. Held so refresh() can reach the
        % widgets without every subclass storing it again.
        Root = []

        % AppState listeners. Stored as properties so they die with the
        % page — dangling listeners on deleted objects leak and then throw
        % (GUI2_SPEC.md Section 5).
        Listeners = event.listener.empty(1, 0)

        % Collapsible groups built by collapsibleGroup, in build order.
        %   Title  string — the header label, and the key expandGroup takes
        %   Grid   the 2-row [header; body] uigridlayout, whose RowHeight is
        %          what actually collapses
        %   Header the uibutton that toggles it
        %   Body   the uipanel every caller fills
        Groups = struct('Title', {}, 'Grid', {}, 'Header', {}, 'Body', {})
    end

    methods (Abstract)
        %PAGEID  Stable string id. Used by navigateTo and by tests.
        id = pageId(obj)

        %TITLE  Rail label.
        t = title(obj)

        %BUILD  Construct the page's widgets into `parent`. Called once.
        build(obj, parent)
    end

    methods
        function obj = Page(state)
            arguments
                state (1,1) gui2.AppState
            end
            obj.State = state;
        end

        function refresh(obj) %#ok<MANU>
            %REFRESH  Re-read AppState and update the widgets.
            %   Default: nothing. A page with no state-dependent rendering
            %   (a static placeholder, a help pane) legitimately needs no
            %   refresh, and forcing an empty override on it would be noise.
        end

        function expandGroup(obj, titleSubstring)
            %EXPANDGROUP  Open a collapsible group by (partial) title.
            %   Public because a control inside a COLLAPSED group is in an
            %   invisible hierarchy, and matlab.uitest refuses to drive one
            %   - a test that types into a collapsed group errors rather
            %   than fails. So a test opens the group first, exactly as the
            %   user would have to. Also the honest way for a later feature
            %   ("go to the field that failed validation") to reveal it.
            %
            %   Substring, not exact: titles are long sentences here
            %   ("Flange stack (clamped layers only - ...)").
            arguments
                obj             (1,1) gui2.Page
                titleSubstring  (1,1) string
            end
            g = obj.groupNamed(titleSubstring);
            gui2.Page.setGroupCollapsed(g.Grid, g.Header, g.Body, g.Title, false);
        end

        function h = groupHeader(obj, titleSubstring)
            %GROUPHEADER  The toggle button of one collapsible group.
            %   For tests that need to drive the toggle as a user does,
            %   rather than call expandGroup and bypass the very thing
            %   under test.
            h = obj.groupNamed(titleSubstring).Header;
        end

        function g = groupNamed(obj, titleSubstring)
            %GROUPNAMED  One group's handles, by partial title.
            %   ERRORS on an unknown name rather than returning empty: a
            %   silent no-op surfaces much later as a test that cannot type
            %   into a field, with nothing pointing back here.
            arguments
                obj            (1,1) gui2.Page
                titleSubstring (1,1) string
            end
            if isempty(obj.Groups)
                error('gui2:Page:noSuchGroup', ...
                    'This page has no collapsible groups.');
            end
            k = find(contains([obj.Groups.Title], titleSubstring), 1);
            if isempty(k)
                error('gui2:Page:noSuchGroup', ...
                    'No collapsible group matching "%s".', titleSubstring);
            end
            g = obj.Groups(k);
        end

        function t = collapsedGroups(obj)
            %COLLAPSEDGROUPS  Titles of the groups currently folded away.
            t = string.empty(1, 0);
            for i = 1:numel(obj.Groups)
                if strcmp(char(obj.Groups(i).Body.Visible), 'off')
                    t(end + 1) = obj.Groups(i).Title; %#ok<AGROW>
                end
            end
        end

        function s = railStatus(obj) %#ok<MANU>
            %RAILSTATUS  The rail's status GLYPH for this page.
            %   "" | "stale" | "loaded". This is the SECOND of the rail's
            %   two independent channels: the first, active-vs-idle, is
            %   carried by the state button's pressed rendering plus font
            %   weight. Status must never be expressed as the active
            %   colour, or a stale-but-active item reads as neither
            %   (GUI2_SPEC.md Section 3).
            %
            %   Default "" — no glyph. Pages that own displayed results
            %   ("stale") or imported data ("loaded") override.
            s = "";
        end
    end

    % ---- Page-facing helpers. Called by subclasses. ----------------------
    methods (Access = protected, Sealed)
        function lb = addBanner(~, parent, row, cols, text)
            %ADDBANNER  The page-scope note that sits above a page's content.
            %   ONE format for every page. These banners say what a page is
            %   and what its contents affect — they are informational, not
            %   warnings, so they all take the info palette. A page that
            %   styled its own as an amber warning would read as a problem
            %   the analyst has to resolve, and inconsistent banner styling
            %   across pages reads as a bug even when each one is legible.
            %
            %   Emphasis belongs in the WORDS ("GLOBAL — applies to every
            %   joint"), not in per-page colors.
            lb = uilabel(parent, 'Text', text);
            lb.Layout.Row    = row;
            lb.Layout.Column = cols;
            lb.WordWrap        = 'on';
            lb.VerticalAlignment = 'top';
            lb.BackgroundColor = gui2.palette('bannerInfoBg');
            lb.FontColor       = gui2.palette('bannerInfoFg');
        end

        function goToPage(obj, pageId)
            %GOTOPAGE  Ask the shell to show another page.
            %   For the handful of places where finishing an action means
            %   the answer is elsewhere - Analyze landing on Results. A
            %   no-op when unattached, so a page built outside a shell
            %   still works.
            if isempty(obj.NavigateFcn)
                return
            end
            obj.NavigateFcn(string(pageId));
        end

        function setStatus(obj, msg)
            %SETSTATUS  Write a one-line message to the shell's status bar.
            %   The route every page uses for INFORMATIONAL outcomes —
            %   "Saved preset X", "Loaded 42 elements". Errors belong in
            %   uialert; routine success does not.
            %
            %   A modal dialog for a successful action is wrong twice over:
            %   it interrupts a user who already knows what they clicked,
            %   and it blocks the App Testing Framework's gestures, so the
            %   next press or type in a test silently does nothing. Use
            %   uialert only where the user genuinely must acknowledge
            %   something before continuing.
            if isempty(obj.StatusFcn)
                return
            end
            obj.StatusFcn(string(msg));
        end

        function showSection(obj)
            %SHOWSECTION  Ask the shell for the joint cross-section window.
            %   The window is a SINGLETON owned by the shell, for the same
            %   reason navigation is: it outlives the page that opened it,
            %   and a page constructing its own would leak one per press.
            %   A no-op when unattached, like goToPage.
            if isempty(obj.ShowSectionFcn)
                return
            end
            obj.ShowSectionFcn();
        end
    end

    % ---- Shell-facing plumbing. Called by gui2.FastenerApp only. ---------
    methods (Sealed)
        function attachNavigate(obj, fcn)
            %ATTACHNAVIGATE  Give the page its route to navigation.
            arguments
                obj (1,1) gui2.Page
                fcn (1,1) function_handle
            end
            obj.NavigateFcn = fcn;
        end

        function attachStatus(obj, fcn)
            %ATTACHSTATUS  Give the page its route to the status bar.
            %   Called once by the shell as it registers the page. Pages
            %   never receive the app itself (Section 5: no page may reach
            %   another page's widgets or the rail).
            arguments
                obj (1,1) gui2.Page
                fcn (1,1) function_handle
            end
            obj.StatusFcn = fcn;
        end

        function attachShowSection(obj, fcn)
            %ATTACHSHOWSECTION  Give the page its route to the section window.
            arguments
                obj (1,1) gui2.Page
                fcn (1,1) function_handle
            end
            obj.ShowSectionFcn = fcn;
        end

        function buildOnce(obj, parent)
            %BUILDONCE  Build the page if it has not been built.
            %   The shell's lazy-construction guarantee lives here, not in
            %   each subclass, so no page can get it wrong.
            if obj.IsBuilt
                return
            end
            obj.Root    = parent;
            obj.IsBuilt = true;   % set BEFORE build() so a build that
                                  % navigates cannot recurse into itself
            obj.build(parent);
        end

        function setVisible(obj, tf)
            %SETVISIBLE  Show or hide the page's card.
            %   Visibility toggling, never construct/destroy: rebuilding a
            %   page on every navigation is the expensive thing over a
            %   remote session.
            if isempty(obj.Root) || ~isvalid(obj.Root)
                return
            end
            obj.Root.Visible = matlab.lang.OnOffSwitchState(tf);
        end
    end

    % ---- Helpers for subclasses ------------------------------------------
    methods (Access = protected)
        function listenTo(obj, eventName, handler)
            %LISTENTO  Subscribe to an AppState event for this page's life.
            %   The listener is stored on the page, so it is destroyed with
            %   the page and cannot fire into a deleted object.
            %
            %       obj.listenTo('JointChanged', @() obj.refresh());
            arguments
                obj       (1,1) gui2.Page
                eventName (1,1) string
                handler   (1,1) function_handle
            end
            obj.Listeners(end + 1) = event.listener( ...
                obj.State, char(eventName), @(~, ~) handler());
        end

        function host = collapsibleGroup(obj, parent, row, titleText, startCollapsed)
            %COLLAPSIBLEGROUP  A titled group whose body folds away (Section 7.5).
            %   host = obj.collapsibleGroup(parent, row, "Bolt") returns the
            %   container to build into, so a caller converts by replacing
            %   its uipanel + Layout lines with one call and leaves the
            %   uigridlayout that follows exactly as it was.
            %
            %   BODIES ARE BUILT EAGERLY; THIS TOGGLES VISIBILITY ONLY.
            %   Section 7.5 settled that and the reason is marshalling:
            %   buildJoint reads EVERY control to assemble a model.Joint, so
            %   a control that was never built is not a saving, it is a
            %   joint with a missing field. (Section 10's "collapsed groups
            %   stay unbuilt" predates that and is superseded by it.)
            %
            %   The row height does the collapsing, not visibility alone: a
            %   'fit' row still reserves space for a hidden child, so the
            %   body row drops to 1 px and the group shrinks to its header.
            arguments
                obj            (1,1) gui2.Page
                parent
                row            (1,1) double
                titleText      (1,1) string
                startCollapsed (1,1) logical = false
            end

            panel = uipanel(parent);
            panel.Layout.Row    = row;
            panel.Layout.Column = 1;

            pg = uigridlayout(panel, [2 1]);
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [0 0 0 0];
            pg.RowSpacing  = 0;

            % LEFT-JUSTIFIED. A centred header reads as a button that does
            % something to the form rather than as the title of the group
            % beneath it, and the disclosure triangle has to sit at a fixed
            % left edge or the eye cannot run down the column of them.
            hdr = uibutton(pg, 'push', 'FontWeight', 'bold', 'FontSize', 13, ...
                'HorizontalAlignment', 'left');
            hdr.Layout.Row = 1;

            host = uipanel(pg, 'BorderType', 'none');
            host.Layout.Row = 2;

            % Reads the CURRENT state at click time rather than capturing a
            % flag, so the closure cannot go stale against expandGroup.
            hdr.ButtonPushedFcn = @(~, ~) gui2.Page.setGroupCollapsed( ...
                pg, hdr, host, titleText, strcmp(char(host.Visible), 'on'));

            gui2.Page.setGroupCollapsed(pg, hdr, host, titleText, startCollapsed);

            obj.Groups(end + 1) = struct('Title', titleText, 'Grid', pg, ...
                'Header', hdr, 'Body', host);
        end

        function bindEdit(obj, control, callback)
            %BINDEDIT  Wire an editable control so it CANNOT forget the dirty flag.
            %   The first build's hardest-won lesson: a dirty feed wired on
            %   only one page silently discards edits made on every other
            %   page (GUI_PORT_SPEC.md Section 14 trap 2, GUI2_HARVEST.md
            %   A4). The fix there was a funnel every field builder used
            %   unconditionally; this is that funnel, moved into the base
            %   class so a new page gets it by inheriting rather than by
            %   remembering.
            %
            %   Marks dirty FIRST, then runs the control's own callback.
            %   The callback takes (src, evt), like any MATLAB callback.
            %
            %       obj.bindEdit(fld, @(~, ~) obj.onNameEdited());
            %       obj.bindEdit(fld);   % dirty only
            %
            %   Use ValueChangedFcn (fires on commit), never
            %   ValueChangingFcn (fires per keystroke) — per-keystroke
            %   callbacks are the classic remote-session killer
            %   (GUI2_SPEC.md Section 10 rule 5).
            arguments
                obj      (1,1) gui2.Page
                control  (1,1)
                callback = []
            end
            state = obj.State;
            control.ValueChangedFcn = @(s, e) gui2.Page.runEdit(state, callback, s, e);
        end
    end

    methods (Static, Access = private)
        function setGroupCollapsed(pg, hdr, host, titleText, collapsed)
            %SETGROUPCOLLAPSED  The one place a group's two states are defined.
            if collapsed
                pg.RowHeight = {gui2.Page.GroupHeaderH, 1};
                glyph = char(9654);   % right-pointing triangle
            else
                pg.RowHeight = {gui2.Page.GroupHeaderH, 'fit'};
                glyph = char(9660);   % down-pointing triangle
            end
            host.Visible = matlab.lang.OnOffSwitchState(~collapsed);
            hdr.Text     = char(string(glyph) + " " + titleText);
        end

        function runEdit(state, callback, src, evt)
            %RUNEDIT  Dirty first, then the control's own callback.
            state.markDirty();
            if ~isempty(callback)
                callback(src, evt);
            end
        end
    end
end
