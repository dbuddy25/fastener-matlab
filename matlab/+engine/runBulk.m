function T = runBulk(jointFile, elementsFile, settingsFile, outFile)
%RUNBULK  One-call headless bulk workflow: files in -> margins out (Phase 3.6).
%   T = engine.runBulk(jointFile, elementsFile, settingsFile, outFile) runs
%   the whole headless pipeline in one call:
%
%       library load -> parse joints -> parse settings -> apply global
%       temps -> parse elements -> analyze -> export
%
%   Inputs:
%       jointFile     joint-definition table (.csv/.xlsx) for
%                     data.loadJointLibrary (template:
%                     templates/joint_library_template.csv)
%       elementsFile  element + forces table (.csv/.xlsx) for
%                     data.loadElements (template:
%                     templates/elements_template.csv)
%       settingsFile  GLOBAL settings file (.csv/.xlsx) for
%                     data.loadSettings (template:
%                     templates/settings_template.csv). Supplies the
%                     analysis temperatures AND the safety/fitting factors:
%                       - NominalTempC/HotTempC/ColdTempC are applied to
%                         EVERY joint (ReferenceTemperature/MaxTemperature/
%                         MinTemperature) before analysis — the joint table
%                         carries no temperature columns
%                       - FSU/FSY/FSSep/FSSlip/FFU/FFY/FFSep/FFSlip build
%                         the model.Factors used for every element
%                     Empty ("" / []) or omitted -> model.Factors() defaults
%                     and the joints' own temperatures (model default 20
%                     degC) are left as-is. Backward-tolerant: a
%                     model.Factors object in this slot (the pre-Settings
%                     signature) is used directly as the factors, with
%                     temperatures likewise left as-is.
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
%                          "settings.csv", "margins.xlsx");
%
%   Orchestration only — every number comes from the already-validated
%   pieces (data.loadJointLibrary / data.loadSettings / data.loadElements
%   / engine.analyzeBulk / report.exportResults).

arguments
    jointFile    (1,1) string
    elementsFile (1,1) string
    settingsFile              = ""
    outFile      (1,1) string = ""
end

lib = data.Library.load();
jl  = data.loadJointLibrary(jointFile, lib);
el  = data.loadElements(elementsFile);

if isa(settingsFile, "model.Factors")
    factors = settingsFile;        % legacy: a Factors object in the settings slot
elseif isempty(settingsFile) || strlength(string(settingsFile)) == 0
    factors = model.Factors();     % no settings -> defaults, temps as-is
else
    s = data.loadSettings(string(settingsFile));
    factors = s.Factors;
    for i = 1:numel(jl)            % global temperatures onto every joint
        j = jl(i).Joint;
        j.ReferenceTemperature = s.NominalTempC;
        j.MaxTemperature       = s.HotTempC;
        j.MinTemperature       = s.ColdTempC;
        jl(i).Joint = j;
    end
end

T = engine.analyzeBulk(jl, el, factors);

if strlength(outFile) > 0
    report.exportResults(T, outFile);
end
end
