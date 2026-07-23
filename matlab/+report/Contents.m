% +REPORT  Reporting — XLSX export now; PDF (Report Generator) later.
%
%   exportResults - Bulk results table -> .xlsx or .csv (by extension;
%                   default .xlsx). For .xlsx the workbook gets a Results
%                   sheet (the full analyzeBulk table) plus a Summary
%                   sheet with counts (total / Pass / Fail / Error);
%                   returns the resolved absolute path. Thin by design —
%                   the analyzeBulk table is already export-ready; this
%                   is the stable public entry point.
%                   ✅ Phase 3.6 (tests/tExport.m).
%
%   Later (Phase 3.8): single-joint PDF report (summary + all margins +
%   worked-equation derivations).
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phase 3.
