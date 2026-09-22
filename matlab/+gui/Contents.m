% +GUI  The rebuilt GUI — a thin shell over the frozen engine API.
%
%   Design spec: GUI_SPEC.md. Rules cited as "A1".."A13": CONVENTIONS.md.
%
%   gui.launch          — entry point: opens the app (app = gui.launch();)
%   gui.FastenerApp     — the shell: rail, cards, menus, status, title.
%                          Owns navigation; owns no page content and no
%                          analysis logic.
%   gui.AppState        — the single source of truth. One handle, eleven
%                          coarse events, and THE serializer (toCaseStruct /
%                          applyCaseStruct) that File > New, File > Open and
%                          every reset go through.
%   gui.Page            — abstract base for pages: pageId / title / build /
%                          refresh / railStatus, plus the bindEdit funnel
%                          that makes it impossible for a page to forget the
%                          dirty flag.
%   gui.HardwareLibraryPage — Materials & Hardware: the six data.Library
%                        sections, read-only, with their source citations.
%   gui.ProjectPage     — project metadata (never analyzed). Backed by
%                          AppState.Project, fires ProjectChanged.
%   gui.FactorsPage     — the fitting factor and the four factors of
%                          safety. Backed by AppState.Factors, fires
%                          FactorsChanged. The preset UI is deferred; the
%                          data.factorPreset* API stays in place for it.
%   gui.TempLoadsPage   — GLOBAL service temperatures (one isothermal-soak
%                          trio for every joint). Backed by AppState.Settings,
%                          fires SettingsChanged.
%   gui.BoltSizingPage  — gut check on bolt size: material + one limit-load
%                          pair, swept over every library bolt with
%                          engine.boltSizingSweep (bolt capability only).
%                          Scratch inputs, not saved in the case.
%   gui.JointConfigPage — one joint and its limit loads, left column in
%                          physical stack order. Owns the library cascade
%                          (bolt -> nut spec + both washer specs), the live
%                          bolt-length readout, required-field gating, and
%                          Analyze / Save to Defined Joints. Backed by
%                          AppState.Joint + LoadCase.
%   gui.JointSectionView— NON-MODAL to-scale axial section of the joint,
%                          opened from Joint Config and owned as a singleton
%                          by the shell. Repaints on JointChanged. Draws in
%                          DATA coordinates, never pixels. layout() is a pure
%                          static so the geometry is testable without a
%                          figure; head height and hex geometry are drawing
%                          conventions the model does not carry.
%   gui.ElementMappingPage
%                        — FE element id -> defined joint (+ the bolt
%                          pattern it belongs to). THE authority on
%                          element -> joint: a force export carries ids and
%                          forces, not joint names. Backed by
%                          AppState.Mapping; the only editable uitable in
%                          the package, so its CellEditCallback marks the
%                          case dirty itself (Page.bindEdit reaches
%                          ValueChangedFcn controls only).
%   gui.ElementForcesPage
%                        — imported FE forces, ONE LOAD CASE PER SHEET.
%                          Parsing stays in data.loadElementWorkbook; the
%                          page adds Merge vs Replace, the per-load-case
%                          Scale / Reversible that never come from the
%                          file, the min/max range preview that is the
%                          units sanity check, and continuous
%                          cross-validation against the mapping. Backed by
%                          AppState.Elements.
%   gui.BulkAnalysisPage
%                        — run every mapped element against every imported
%                          load case and read it in three tiers (Joint
%                          Summary / By Load Case / By Element). One engine
%                          call; everything else is display. Owns the
%                          workflow's only hard gate, which names the page
%                          that fixes each problem. Backed by
%                          AppState.BulkTable.
%   gui.MarginView      — how a margin is RENDERED and REDUCED, shared by
%                          Results and Bulk so the two cannot drift (A8).
%                          Holds the ratio/margin distinction: Interaction
%                          passes iff R <= 1, so its worst case across load
%                          cases is the MAXIMUM, not the minimum.
%   gui.palette         — semantic color name -> RGB; the ONLY place GUI
%                          colors live (no literal RGB triples elsewhere).
%   gui.recentFiles     — the persisted Open Recent list (max 5, dead paths
%                          filtered on read).
%
%   Shell: left rail with section headers and two independent state
%   channels (pressed+bold for active, a glyph for stale/loaded), card area
%   with lazily built pages, status bar, File/Help menus, dirty-state
%   window title. Case files are JSON, format "fastener-analysis-matlab-v1";
%   model objects go through data.toStruct / data.fromStruct, never
%   hand-rolled. Help menu: User Guide, References. Materials & Hardware
%   browses all six data.Library sections read-only, with an origin filter
%   and every entry's source citation on screen.
%
%   THE RULES THIS PACKAGE IS BOUND BY
%     - Pure GUI. +engine, +model, +data and +report are frozen: this layer
%       adds no equation and re-derives no number (GUI_SPEC.md Section 1).
%     - Pages never talk to each other. All cross-page effect goes through
%       gui.AppState (Section 5).
%     - Pass/fail comes from Result.Margins(i).Status. The view colors by
%       that field and never re-thresholds (Section 6). Interaction reports
%       R, passing iff R <= 1 — the OPPOSITE direction from MS >= 0.
%     - ALL 15 of the engine's checks are displayed: the four Section
%       4.4.1 tensile modes do not restate Tension-Ultimate — they use
%       Pb = PpMax + FFU*FSU*n*phi*PtL where Tension-Ultimate uses
%       Ptu = FSU*FFU*PtL.
%     - Programmatic repopulation NEVER marks the case dirty
%       (CONVENTIONS.md A4).
