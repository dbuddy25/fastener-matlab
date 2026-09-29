% +REPORT  Reporting — XLSX and CSV exports.
%
%   exportResults      - Bulk results table -> .xlsx or .csv (by extension;
%                         default .xlsx). For .xlsx the workbook gets a
%                         Results sheet (the full analyzeBulk table) plus a
%                         Summary sheet with counts (total / Pass / Fail /
%                         Error); returns the resolved absolute path. Thin
%                         by design — the analyzeBulk table is already
%                         export-ready; this is the stable public entry
%                         point.
%
%   Reference: ARCHITECTURE.md.
