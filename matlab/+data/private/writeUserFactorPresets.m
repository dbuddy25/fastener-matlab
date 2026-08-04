function writeUserFactorPresets(m, file)
%WRITEUSERFACTORPRESETS  Write a containers.Map name -> model.Factors to a
%   user factor-presets JSON file (Phase 3.7). See loadUserFactorPresets
%   for the on-disk shape (a name+factors array, not a name-keyed object,
%   so arbitrary preset names are safe).
arguments
    m    (1,1) containers.Map
    file (1,1) string
end

names = string(keys(m));
entries = cell(1, numel(names));
for i = 1:numel(names)
    entries{i} = struct("name", names(i), ...
                        "factors", data.toStruct(m(char(names(i)))));
end

container = struct();
container.schemaVersion = 1;
container.presets = entries;

try
    txt = jsonencode(container, "ConvertInfAndNaN", false, "PrettyPrint", true);
catch
    txt = jsonencode(container, "ConvertInfAndNaN", false);
end

parentDir = fileparts(file);
if strlength(string(parentDir)) > 0 && ~isfolder(parentDir)
    mkdir(parentDir);
end

fid = fopen(file, "w");
if fid < 0
    error("data:saveFactorPreset:cannotWrite", "Cannot open ""%s"" for writing.", file);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, "char");
end
