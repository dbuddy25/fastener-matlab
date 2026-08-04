% +REPORT  Reporting — XLSX export (bulk) + single-joint PDF (Report Generator).
%
%   exportResults      - Bulk results table -> .xlsx or .csv (by extension;
%                         default .xlsx). For .xlsx the workbook gets a
%                         Results sheet (the full analyzeBulk table) plus a
%                         Summary sheet with counts (total / Pass / Fail /
%                         Error); returns the resolved absolute path. Thin
%                         by design — the analyzeBulk table is already
%                         export-ready; this is the stable public entry
%                         point.
%                         ✅ Phase 3.6 (tests/tExport.m).
%
%   singleJointReport  - Single-joint PDF report: title page, inputs,
%                         preload, design loads, the 15-row margins table
%                         (governing row bold, Fail rows red) + a
%                         "Governing: ..." callout, the Fig. 8
%                         separation-before-rupture narrative, and a
%                         governing-equations (citation) table for every
%                         EVALUATED check. Built on MATLAB Report Generator
%                         (mlreportgen.report.* + mlreportgen.dom.*) —
%                         errors with id
%                         "report:singleJointReport:reportGenRequired" if
%                         the toolbox is not installed/licensed. Equation
%                         citations only — full step-by-step symbolic
%                         derivations are a follow-up (see the function's
%                         header comment).
%                         ✅ Phase 3.8 (tests/tPdfReport.m, skip-guarded
%                         when Report Generator is absent).
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phase 3.
