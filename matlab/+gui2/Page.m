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

    properties (Access = protected)
        % The container build() was given. Held so refresh() can reach the
        % widgets without every subclass storing it again.
        Root = []

        % AppState listeners. Stored as properties so they die with the
        % page — dangling listeners on deleted objects leak and then throw
        % (GUI2_SPEC.md Section 5).
        Listeners = event.listener.empty(1, 0)
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

    % ---- Shell-facing plumbing. Called by gui2.FastenerApp only. ---------
    methods (Sealed)
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
        function runEdit(state, callback, src, evt)
            %RUNEDIT  Dirty first, then the control's own callback.
            state.markDirty();
            if ~isempty(callback)
                callback(src, evt);
            end
        end
    end
end
