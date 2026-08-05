% +GUI2  The rebuilt GUI — a thin shell over the frozen engine API.
%
%   Second pass at the GUI (GUI2_SPEC.md). Built alongside +gui; BOTH stay
%   launchable until the last page lands, so there is never a window with no
%   working tool. Case files interchange: both read and write the same
%   "fastener-analysis-matlab-v1" container.
%
%   gui2.launch          — entry point: opens the app (app = gui2.launch();)
%   gui2.FastenerApp     — the shell: rail, cards, menus, status, title.
%                          Owns navigation; owns no page content and no
%                          analysis logic.
%   gui2.AppState        — the single source of truth. One handle, eleven
%                          coarse events, and THE serializer (toCaseStruct /
%                          applyCaseStruct) that File > New, File > Open and
%                          every reset go through.
%   gui2.Page            — abstract base for pages: pageId / title / build /
%                          refresh / railStatus, plus the bindEdit funnel
%                          that makes it impossible for a page to forget the
%                          dirty flag.
%   gui2.PlaceholderPage — a page naming the step that replaces it.
%   gui2.palette         — semantic color name -> RGB; the ONLY place GUI2
%                          colors live (no literal RGB triples elsewhere).
%   gui2.recentFiles     — the persisted Open Recent list (max 5, dead paths
%                          filtered on read).
%
%   BUILT (GUI2_SPEC.md Section 14, step 1):
%     - Shell: left rail with section headers and two independent state
%       channels (pressed+bold for active, a glyph for stale/loaded), card
%       area with lazily built pages, status bar, File/Help menus,
%       dirty-state window title.
%     - Case files: JSON, format "fastener-analysis-matlab-v1"; model
%       objects via data.toStruct / data.fromStruct — the tested Phase 3.7
%       round-trip core, never hand-rolled.
%     - Open Recent (new build; the first pass deferred it).
%
%   NOT BUILT YET — every rail entry is a PlaceholderPage naming its step:
%     step 2  Project, Factors, Temp Loads
%     step 3  Joint Config
%     step 4  Single Joint Results
%     step 5  Defined Joints Library
%     step 6  Element Mapping
%     step 7  Element Forces
%     step 8  Bulk Analysis
%     step 9  Materials & Hardware Library
%     step 10 Help menu documents; delete +gui
%
%   THE RULES THIS PACKAGE IS BOUND BY
%     - Pure GUI. +engine, +model, +data and +report are frozen: this layer
%       adds no equation and re-derives no number (GUI2_SPEC.md Section 1).
%     - Pages never talk to each other. All cross-page effect goes through
%       gui2.AppState (Section 5).
%     - Pass/fail comes from Result.Margins(i).Status. The view colors by
%       that field and never re-thresholds (Section 6). Interaction reports
%       R, passing iff R <= 1 — the OPPOSITE direction from MS >= 0.
%     - 9 of the engine's 15 checks are displayed; every results view and
%       export names the other 6 (Section 2).
%     - Programmatic repopulation NEVER marks the case dirty
%       (GUI2_HARVEST.md A4).
