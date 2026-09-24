function file = makeAnswerKeyCase(file)
%MAKEANSWERKEYCASE  Write the DABJ Section 9 answer-key case for File > Open.
%   makeAnswerKeyCase                 writes dabj9_answer_key.json in pwd
%   makeAnswerKeyCase("C:\x\y.json")  writes it there
%
%   Built from validation.dabjSection9 (the case tDabjCase checks the engine
%   against), so nothing is transcribed by hand. Also writes the book's two
%   materials and its bolt as DROP-IN library files, because Joint Config
%   picks those by name from the library, and a material added on Materials
%   & Hardware cannot be given the "bolt" role there.
%
%   Then: restart the app (drop-ins load at startup), File > Open this file,
%   press Analyze Single Joint, and compare with ANSWER_KEY_ENTRY_SHEET.md
%   section 5.
arguments
    file (1,1) string = fullfile(pwd, "dabj9_answer_key.json")
end

here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
c = validation.dabjSection9();
src = "DABJ Section 9 class problem (GUI answer-key check)";

% ---- Drop-in library entries ---------------------------------------------
drop = data.Library.dropInPath();
bm = c.Joint.BoltMaterial;
fm = c.Joint.FlangeStack(1).Material;
b  = c.Joint.Bolt;

writeEntry(fullfile(drop, "materials", "dabj9_bolt_material.json"), ...
    material(bm, ["bolt", "washer"], src));
writeEntry(fullfile(drop, "materials", "dabj9_flange_material.json"), ...
    material(fm, strings(1, 0), src));
writeEntry(fullfile(drop, "bolts", "dabj9_bolt.json"), struct( ...
    'key',                 b.Designation, ...
    'nominalDiameter',     b.NominalDiameter, ...
    'series',              string(b.Series), ...
    'tpi',                 b.ThreadsPerInch, ...
    'tensileStressArea',   b.TensileStressArea, ...
    'minorDiameter',       b.MinorDiameter, ...
    'pitchDiameter',       b.PitchDiameter, ...
    'bodyDiameter',        b.BodyDiameter, ...
    'headBearingDiameter', b.HeadBearingDiameter, ...
    'threadLength',        b.ThreadLength, ...
    'source',              src));

% ---- The case --------------------------------------------------------------
j = c.Joint;
for k = 1:numel(j.FlangeStack)
    % The book gives no edge distance and the GUI requires one; e/D = 2.0
    % stays above the Fig. 8 gate's 1.5, so none of the six margins move.
    j.FlangeStack(k).EdgeDistance = 0.75;
end

s = gui.AppState();
s.Joint    = j;
s.LoadCase = c.LoadCase;
s.Factors  = c.Factors;
s.Settings = struct('NominalTempC', j.ReferenceTemperature, ...
                    'HotTempC',     j.MaxTemperature, ...
                    'ColdTempC',    j.MinTemperature);
gui.AppState.writeCaseFile(s.toCaseStruct(), file);

fprintf("Library drop-ins written under %s\n", drop);
fprintf("Case written to %s\n", file);
fprintf("Restart the app, then File > Open that file and press Analyze Single Joint.\n");
end

function e = material(m, roles, src)
e = struct('key', m.Name);
map = ["ftu" "Ftu"; "fty" "Fty"; "fsu" "Fsu"; "fsy" "Fsy"; ...
       "fbru" "Fbru"; "fbry" "Fbry"; "e" "E"; "cte" "CTE"];
for r = 1:size(map, 1)
    v = m.(map(r, 2));
    if ~isnan(v) && v ~= 0
        e.(map(r, 1)) = v;
    end
end
if ~isempty(roles)
    e.roles = cellstr(roles);
end
e.source = src;
end

function writeEntry(file, entry)
folder = fileparts(file);
if ~isfolder(folder)
    mkdir(folder);
end
fid = fopen(file, 'w');
if fid < 0
    error("makeAnswerKeyCase:cannotWrite", "Cannot write %s.", file);
end
closer = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(entry, 'PrettyPrint', true), 'char');
end
