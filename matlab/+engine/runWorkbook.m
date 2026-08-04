function T = runWorkbook(workbookFile, outFile)
%RUNWORKBOOK  One-call bulk run from a SINGLE multi-sheet workbook (Step 2c).
%   T = engine.runWorkbook(workbookFile) runs the whole bulk pipeline on
%   ONE .xlsx — the data.makeTemplate fill-in workbook (or any workbook
%   with the same three input sheets):
%
%       Joints    -> data.loadJointLibrary(workbookFile, lib, "Joints")
%       Elements  -> data.loadElements(workbookFile, "Elements")
%       Settings  -> data.loadSettings(workbookFile, "Settings")
%
%   then applies the global temperatures + factors to every joint (the
%   same private/applyGlobalSettings step engine.runBulk performs) and
%   returns the engine.analyzeBulk results table — one row per element.
%   Both table readers auto-detect the header row, so the template's
%   friendly-name banner rows need no cleanup.
%
%   T = engine.runWorkbook(workbookFile, outFile) also writes the results
%   via report.exportResults (.xlsx Results + Summary sheets, or .csv by
%   extension). outFile MUST be a different file from workbookFile — the
%   tool refuses to write results into the workbook it just read, so a
%   mis-typed path can never clobber the filled input sheets. Omit outFile
%   (or pass "") to just get T back.
%
%   The streamlined bulk flow (see USER_GUIDE.md Section 4):
%       f = data.makeTemplate("analysis_template.xlsx");   % generate the template
%       % ... fill the Joints / Elements / Settings sheets in Excel ...
%       T = engine.runWorkbook("analysis_template.xlsx", "margins.xlsx");
%
%   Split input files instead? engine.runBulk(jointFile, elementsFile,
%   settingsFile, outFile) is the same pipeline over three separate
%   .csv/.xlsx files.
%
%   Orchestration only — every number comes from the already-validated
%   pieces (data.loadJointLibrary / data.loadElements / data.loadSettings
%   / engine.analyzeBulk / report.exportResults).
%
%   Call graph:
%       Precedents (calls)      data.Library.load, data.loadJointLibrary,
%                               data.loadElements, data.loadSettings,
%                               engine.private.applyGlobalSettings (shared
%                               with engine.runBulk), engine.analyzeBulk,
%                               report.exportResults, engine.private.samePath
%                               (shared with engine.runBulk's own outFile
%                               guard).
%       Dependents (called by)  (entry point) — no other engine/gui
%                               function calls it; exercised directly by
%                               tests/tWorkbook.m.
%       Tests                   tests/tWorkbook.m
%                               workbookRunsFreshTemplateWithoutCrashing,
%                               workbookWritesResults,
%                               workbookRefusesInPlaceOutput (the
%                               outFile == workbookFile guard).
%
%   Validation status/coverage: VALIDATION.md's Structural/non-numeric
%   table, row "Single-workbook end-to-end".

arguments
    workbookFile (1,1) string
    outFile      (1,1) string = ""
end

if ~isfile(workbookFile)
    error("engine:runWorkbook:fileNotFound", ...
        "Workbook not found: %s", workbookFile);
end

lib = data.Library.load();
jl  = data.loadJointLibrary(workbookFile, lib, "Joints");
el  = data.loadElements(workbookFile, "Elements");
s   = data.loadSettings(workbookFile, "Settings");

[jl, factors] = applyGlobalSettings(jl, s);   % shared with engine.runBulk
T = engine.analyzeBulk(jl, el, factors);

if strlength(outFile) > 0
    if samePath(outFile, workbookFile)
        error("engine:runWorkbook:outFileIsInput", ...
            "outFile must be a different file from the input workbook (%s) — writing results into the input would risk clobbering the filled sheets. Use a separate results file, e.g. ""margins.xlsx"".", ...
            workbookFile);
    end
    report.exportResults(T, outFile);
end
end
