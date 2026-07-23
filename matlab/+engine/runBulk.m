function T = runBulk(jointLibFile, elementsFile, factors, outFile)
%RUNBULK  One-call headless bulk workflow: files in -> margins out (Phase 3.6).
%   T = engine.runBulk(jointLibFile, elementsFile, factors, outFile) runs
%   the whole headless pipeline in one call:
%
%       library load -> parse joints -> parse elements -> analyze -> export
%
%   Inputs:
%       jointLibFile  joint-definition table (.csv/.xlsx) for
%                     data.loadJointLibrary (template:
%                     templates/joint_library_template.csv)
%       elementsFile  element + forces table (.csv/.xlsx) for
%                     data.loadElements (template:
%                     templates/elements_template.csv)
%       factors       model.Factors (optional; omitted or [] -> the
%                     built-in default preset, model.Factors())
%       outFile       optional .xlsx/.csv path; when given, the results
%                     table is also written via report.exportResults
%
%   Output: the engine.analyzeBulk results table — one row per element
%   (identity, resolved per-bolt Axial/Shear, the 15 margin MS columns,
%   WorstMargin/GoverningCheck, Error, Note). See engine.analyzeBulk for
%   the column details and the joint-slip bolt-pattern aggregation (the
%   nf check: joint slip evaluates only when the pattern's element count
%   equals Joint.BoltCount; otherwise Slip is NaN with a Note).
%
%   Headless usage (the Headless Release in one line):
%       T = engine.runBulk("joint_library.csv", "elements.csv", ...
%                          model.Factors(), "margins.xlsx");
%
%   Orchestration only — every number comes from the already-validated
%   pieces (data.loadJointLibrary / data.loadElements / engine.analyzeBulk
%   / report.exportResults).

arguments
    jointLibFile (1,1) string
    elementsFile (1,1) string
    factors                    = model.Factors()
    outFile      (1,1) string  = ""
end

if isempty(factors)
    factors = model.Factors();   % explicit [] -> built-in default preset
end

lib = data.Library.load();
jl  = data.loadJointLibrary(jointLibFile, lib);
el  = data.loadElements(elementsFile);
T   = engine.analyzeBulk(jl, el, factors);

if strlength(outFile) > 0
    report.exportResults(T, outFile);
end
end
