function p = userDataFolder(newPath, store)
%USERDATAFOLDER  Where this machine keeps the tool's user data.
%   p = data.userDataFolder()          the folder in use
%   p = data.userDataFolder(newPath)   store a chosen folder, return it
%   p = data.userDataFolder(_, store)  use a specific preference file
%
%   The folder holds fastener_library.json (custom entries), the
%   fastener_library\<category>\ drop-in folders and
%   fastener_factor_presets.json. data.Library.userPath and the factor
%   presets both resolve through here, so the three always move together.
%
%   Default: userpath (usually Documents\MATLAB), or prefdir() when
%   userpath is empty. An analyst may choose another folder, a synced
%   OneDrive one for example, from Hardware Library > Choose Library Folder.
%   The choice is per machine, stored in prefdir() like gui.referencesFolder,
%   because it is a property of the machine rather than of a case.
%
%   None of this is inside the toolbox, so installing a newer version
%   never touches it. A chosen folder that cannot be found (a sync not yet
%   finished, a drive not mounted) is still returned: falling back to the
%   default would quietly split the library across two places.
%
%   The store argument exists so tests never touch the real preference.
%   runTests goes further: it sets FASTENER_TOOL_DATA_FOLDER to a temp
%   folder for the run, which wins over the stored choice, so no test
%   (the GUI's included) reads or writes the real user's library.
arguments
    newPath (1,1) string = ""
    store   (1,1) string = ""
end
if strlength(store) == 0
    override = string(getenv("FASTENER_TOOL_DATA_FOLDER"));
    if strlength(override) > 0 && strlength(newPath) == 0
        p = override;
        return
    end
    store = string(fullfile(prefdir(), 'fastener-tool-data-folder.json'));
end

if strlength(newPath) > 0
    p = newPath;
    fid = fopen(char(store), 'w');
    if fid < 0
        error("data:userDataFolder:notSaved", ...
            'Could not save the folder choice to %s.', store);
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s\n', jsonencode(struct("folder", p)));
    return
end

p = "";
try
    if isfile(store)
        raw = jsondecode(fileread(store));
        if isfield(raw, "folder")
            p = string(raw.folder);
        end
    end
catch
    p = "";
end
if strlength(p) > 0
    return
end

up = userpath();
if isempty(up) || strlength(string(up)) == 0
    % PREFDIR, NOT THE INSTALL DIRECTORY. From source that would write
    % private data into the repository; a compiled build cannot reliably
    % write there at all. prefdir() is per-user and always writable.
    p = string(prefdir());
else
    p = string(up);
end
end
