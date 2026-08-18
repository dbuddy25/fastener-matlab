function p = referencesFolder(newPath, store)
%REFERENCESFOLDER  Where this machine keeps its copies of the standards.
%   p = gui2.referencesFolder()          read the stored folder ("" if unset)
%   p = gui2.referencesFolder(newPath)   store it, and return what was stored
%   p = gui2.referencesFolder(_, store)  use a specific preference file
%
%   The third form exists so tests never touch the real per-user
%   preference, the same reason data.saveFactorPreset takes a file
%   argument. Nothing in the app passes it.
%
%   THE TOOL SHIPS NO STANDARDS. Nine of the fifteen documents it cites
%   are copyrighted and cannot be redistributed (see
%   data.referenceDocuments), so the References window shows citations for
%   everything and opens a file only where the analyst already has one.
%   This is where "already has one" is recorded.
%
%   Stored in prefdir(), per user, exactly like gui2.recentFiles -- not in
%   the case file (it is a property of the machine, not the analysis) and
%   not next to the install (a compiled standalone cannot reliably write
%   there).
%
%   DEFAULTS TO THE REPO'S OWN references/ FOLDER when nothing is stored
%   and that folder exists, so a developer running from source gets the
%   documents without configuring anything. That folder is gitignored, so
%   this is a convenience on a working checkout and resolves to nothing on
%   a clean one -- which is the honest answer there.
%
%   Never throws. A store that cannot be written is reported by returning
%   the value anyway: losing the preference is a worse reason to interrupt
%   an analyst than silently forgetting it, and the folder can be chosen
%   again.
%
%   Tests: tests/tReferenceDocuments.m.

arguments
    newPath (1,1) string = ""
    store   (1,1) string = ""        % "" -> this user's real preference file
end

% Resolved HERE rather than as an arguments default so the "did the caller
% supply one?" question stays answerable -- that is what decides whether
% the source-checkout fallback below applies.
usingRealStore = strlength(store) == 0;
if usingRealStore
    store = string(fullfile(prefdir(), 'fastener-tool-references.json'));
end

if strlength(newPath) > 0
    p = newPath;
    try
        fid = fopen(char(store), 'w');
        if fid >= 0
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s\n', jsonencode(struct("folder", p)));
        end
    catch
        % Preference not persisted; the choice still applies this session.
    end
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

% THE SOURCE-CHECKOUT FALLBACK APPLIES TO THE REAL STORE ONLY. A test that
% supplied its own preference file is asking what THAT file says, and
% quietly answering with the repository's own references/ folder instead
% would make an unset store indistinguishable from a set one on any
% developer machine -- which is exactly the case worth testing.
if strlength(p) == 0 && usingRealStore
    here = fileparts(mfilename("fullpath"));           % .../matlab/+gui2
    guess = fullfile(fileparts(fileparts(here)), "references");
    if isfolder(guess)
        p = string(guess);
    end
end
end
