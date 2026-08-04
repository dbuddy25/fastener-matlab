function c = loadCase(file)
%LOADCASE  Deserialize an analysis case JSON file written by data.saveCase
%   (Phase 3.7).
%   c = data.loadCase(file) -> struct with:
%       Joint     (1,1) model.Joint    — always present
%       LoadCase  (1,1) model.LoadCase — present when saved
%       Factors   (1,1) model.Factors  — present when saved
%       Name      (1,1) string         — present when saved
%
%   jsondecode reads the file, then each part is rebuilt via
%   data.fromStruct. Lossless: re-running engine.analyze on the result
%   reproduces the same margins as the original case (tests/tCaseIO.m).
%
%   Example:
%       c2 = data.loadCase(f);
%       r2 = engine.analyze(c2.Joint, c2.LoadCase, c2.Factors);

arguments
    file (1,1) string
end

if ~isfile(file)
    error("data:loadCase:fileNotFound", "Case file not found: %s", file);
end

raw = jsondecode(fileread(file));

if ~isfield(raw, "Joint")
    error("data:loadCase:missingJoint", ...
        "%s has no Joint field — not a valid case file.", file);
end

c = struct();
c.Joint = data.fromStruct(raw.Joint);
if isfield(raw, "LoadCase")
    c.LoadCase = data.fromStruct(raw.LoadCase);
end
if isfield(raw, "Factors")
    c.Factors = data.fromStruct(raw.Factors);
end
if isfield(raw, "Name")
    c.Name = string(raw.Name);
end
end
