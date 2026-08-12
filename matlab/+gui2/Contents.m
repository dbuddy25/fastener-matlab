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
%   gui2.ProjectPage     — project metadata (never analyzed). Backed by
%                          AppState.Project, fires ProjectChanged.
%   gui2.FactorsPage     — the fitting factor and the four factors of
%                          safety. Backed by AppState.Factors, fires
%                          FactorsChanged. The preset UI is deferred; the
%                          data.factorPreset* API stays in place for it.
%   gui2.TempLoadsPage   — GLOBAL service temperatures (one isothermal-soak
%                          trio for every joint). Backed by AppState.Settings,
%                          fires SettingsChanged.
%   gui2.JointConfigPage — one joint and its limit loads, left column in
%                          physical stack order. Owns the library cascade
%                          (bolt -> nut spec + both washer specs), the live
%                          bolt-length readout, required-field gating, and
%                          Analyze / Save to Defined Joints. Backed by
%                          AppState.Joint + LoadCase.
%   gui2.JointSectionView— NON-MODAL to-scale axial section of the joint,
%                          opened from Joint Config and owned as a singleton
%                          by the shell. Repaints on JointChanged. Draws in
%                          DATA coordinates, never pixels. layout() is a pure
%                          static so the geometry is testable without a
%                          figure; head height and hex geometry are drawing
%                          conventions the model does not carry.
%   gui2.ElementMappingPage
%                        — FE element id -> defined joint (+ the bolt
%                          pattern it belongs to). THE authority on
%                          element -> joint: a force export carries ids and
%                          forces, not joint names. Backed by
%                          AppState.Mapping; the only editable uitable in
%                          the package, so its CellEditCallback marks the
%                          case dirty itself (Page.bindEdit reaches
%                          ValueChangedFcn controls only).
%   gui2.ElementForcesPage
%                        — imported FE forces, ONE LOAD CASE PER SHEET.
%                          Parsing stays in data.loadElementWorkbook; the
%                          page adds Merge vs Replace, the per-load-case
%                          Scale / Reversible that never come from the
%                          file, the min/max range preview that is the
%                          units sanity check, and continuous
%                          cross-validation against the mapping. Backed by
%                          AppState.Elements.
%   gui2.BulkAnalysisPage
%                        — run every mapped element against every imported
%                          load case and read it in three tiers (Joint
%                          Summary / By Load Case / By Element). One engine
%                          call; everything else is display. Owns the
%                          workflow's only hard gate, which names the page
%                          that fixes each problem. Backed by
%                          AppState.BulkTable.
%   gui2.MarginView      — how a margin is RENDERED and REDUCED, shared by
%                          Results and Bulk so the two cannot drift (A8).
%                          Holds the ratio/margin distinction: Interaction
%                          passes iff R <= 1, so its worst case across load
%                          cases is the MAXIMUM, not the minimum.
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
%     - Step 2: Project, Factors, Temp Loads — see gui2.ProjectPage,
%       gui2.FactorsPage, gui2.TempLoadsPage above.
%     - Step 3: Joint Config — see gui2.JointConfigPage above. Analyze
%       writes AppState.Result; the Results page (step 4) renders it.
%     - Step 4: Single Joint Results — gui2.ResultsPage.
%     - Step 5: Defined Joints — gui2.DefinedJointsPage.
%     - Step 6: Element Mapping — gui2.ElementMappingPage.
%     - Step 7: Element Forces — gui2.ElementForcesPage.
%     - Step 8: Bulk Analysis — gui2.BulkAnalysisPage. The bulk workflow
%       now runs end to end.
%
%   NOT BUILT YET — every remaining rail entry is a PlaceholderPage naming
%   its step:
%     step 9  Materials & Hardware
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
%     - ALL 15 of the engine's checks are displayed. The earlier rule
%       (9 shown, the other 6 named in a footer) rested on a false
%       premise — that the four Section 4.4.1 tensile modes restate
%       Tension-Ultimate. They do not: they use Pb = PpMax + FFU*FSU*n*phi
%       *PtL where Tension-Ultimate uses Ptu = FSU*FFU*PtL.
%     - Programmatic repopulation NEVER marks the case dirty
%       (GUI2_HARVEST.md A4).
