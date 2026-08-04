% +GUI  Programmatic uifigure app — Phase 4, a thin shell over the engine API.
%
%   gui.launch         — entry point: opens the app (app = gui.launch();)
%   gui.FastenerApp    — the app class (plain .m classdef, no .mlapp)
%   gui.palette        — semantic color name -> RGB; the ONLY place GUI
%                        colors live (no literal RGB triples elsewhere)
%   gui.askChoice      — blocking multi-choice uiconfirm wrapper
%   gui.confirmDiscard — "discard unsaved changes?" dialog (Cancel default)
%   gui.exportBulkWorkbook — bulk-results .xlsx writer: values via
%                        writecell (always), then best-effort Excel COM
%                        styling on Windows; a formatting failure never
%                        loses the workbook. Its hex color constants are
%                        Excel FILE values, deliberately not gui.palette.
%
%   Built (GUI_PORT_SPEC.md Section 14, step 1 + slice 1):
%     - App shell: File/Help menus, status bar with per-tab hints,
%       dirty-state window title, case save/load (JSON, format
%       "fastener-analysis-matlab-v1"; model objects via data.toStruct/
%       fromStruct — the tested Phase 3.7 round-trip core).
%     - Project & Factors tab: project metadata + all eight model.Factors
%       fields (factor presets deferred).
%     - Joint Config tab (library-backed dropdowns + numeric fields) ->
%       Analyze -> Results tab (15-margin table, worst margin, governing
%       check, Fig. 8 narrative).
%   Remaining planned tabs are labelled placeholders (Phase 4.5-4.11);
%   degC/degF + unit-system toggle is Phase 4.12.
%
%   Hard rule: NO analysis logic in the GUI — every control feeds
%   model.* objects into engine.analyze, and the tabs render engine.Result.
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md Phase 4 + GUI_PORT_SPEC.md.
