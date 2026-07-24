function file = saveCase(caseStruct, file)
%SAVECASE  Serialize an analysis case (Joint + optional LoadCase/Factors/
%   Name) to a JSON file (Phase 3.7).
%   file = data.saveCase(caseStruct, file) where caseStruct is a struct
%   with:
%       Joint     (1,1) model.Joint    — required
%       LoadCase  (1,1) model.LoadCase — optional
%       Factors   (1,1) model.Factors  — optional
%       Name      (1,1) string         — optional, cosmetic case label
%
%   `file` is optional; when omitted a temp file is used. A ".json"
%   extension is appended when missing. Returns the resolved path (string).
%
%   Each present field is serialized via data.toStruct and wrapped in a
%   container struct with a schemaVersion, then jsonencode'd
%   (PrettyPrint when the running MATLAB supports it) with
%   ConvertInfAndNaN=false so the model's NaN "unconfigured" sentinels
%   round-trip as the literal JSON token NaN (which jsondecode accepts)
%   instead of being collapsed to null.
%
%   Round-trip lossless: re-running engine.analyze on data.loadCase(file)
%   reproduces the same margins as the original Joint/LoadCase/Factors —
%   see tests/tCaseIO.m (caseRoundTripsLossless).
%
%   Example:
%       c = validation.dabjSection9();
%       f = data.saveCase(struct(Joint=c.Joint, LoadCase=c.LoadCase, ...
%                                Factors=c.Factors), [tempname '.json']);
%       c2 = data.loadCase(f);

arguments
    caseStruct (1,1) struct
    file       (1,1) string = string(tempname) + ".json"
end

if ~isfield(caseStruct, "Joint") || ~isa(caseStruct.Joint, "model.Joint")
    error("data:saveCase:missingJoint", ...
        "caseStruct.Joint is required and must be a model.Joint.");
end

container = struct();
container.schemaVersion = 1;
container.Joint = data.toStruct(caseStruct.Joint);

if isfield(caseStruct, "LoadCase") && ~isempty(caseStruct.LoadCase)
    container.LoadCase = data.toStruct(caseStruct.LoadCase);
end
if isfield(caseStruct, "Factors") && ~isempty(caseStruct.Factors)
    container.Factors = data.toStruct(caseStruct.Factors);
end
if isfield(caseStruct, "Name") && strlength(string(caseStruct.Name)) > 0
    container.Name = string(caseStruct.Name);
end

file = string(file);
if ~endsWith(file, ".json", "IgnoreCase", true)
    file = file + ".json";
end

try
    txt = jsonencode(container, "ConvertInfAndNaN", false, "PrettyPrint", true);
catch
    % Older MATLAB releases without the PrettyPrint name-value pair.
    txt = jsonencode(container, "ConvertInfAndNaN", false);
end

fid = fopen(file, "w");
if fid < 0
    error("data:saveCase:cannotWrite", "Cannot open ""%s"" for writing.", file);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, "char");
end
