function files = recentFiles(action, file)
%RECENTFILES  The Open Recent list, persisted between sessions.
%   files = gui2.recentFiles()               most-recent-first, existing only
%   files = gui2.recentFiles('add', path)    move/insert at the front
%   files = gui2.recentFiles('remove', path) drop an entry
%   files = gui2.recentFiles('clear')        forget everything
%   p     = gui2.recentFiles('path')         where the list is stored
%
%   The 'path' action exists so tGui2Shell can snapshot and restore the
%   file around its tests. Running the suite must not wipe the developer's
%   own recent list — a test with a side effect on the user's preferences
%   is a test that gets disabled.
%
%   Returns a string array; empty (0x1) when there is nothing to show, which
%   is what makes the caller render the "(no recent files)" placeholder
%   rather than an empty submenu (GUI2_HARVEST.md A12).
%
%   NEW BUILD, not a port: Open Recent was specified in the first pass and
%   deferred, so there is no earlier behavior to carry forward.
%
%   THREE RULES, all of which exist because the alternative is a menu that
%   lies:
%     1. Max 5 entries. A recent list is a shortcut, not a history.
%     2. Paths that no longer exist are filtered ON READ, not on write. A
%        file can be deleted, renamed, or on an unmounted share between one
%        session and the next; checking only at write time would leave dead
%        entries that fail when clicked.
%     3. Comparison is by canonical absolute path, so the same file reached
%        two ways cannot occupy two slots. On Windows, paths compare
%        case-insensitively.
%
%   Storage is prefdir/fastener-tool-recent.json — per user, outside the
%   repo, and never part of a case file. A read or write failure is
%   swallowed: a broken recent list must never stop the app opening or a
%   case saving.

arguments
    action (1,1) string = "get"
    file   (1,1) string = ""
end

MAX_ENTRIES = 5;

if action == "path"
    files = string(storePath());
    return
end

stored = readList();

switch action
    case "get"
        % nothing to do
    case "add"
        canon = canonical(file);
        if strlength(canon) > 0
            stored = [canon; stored(~pathsMatch(stored, canon))];
            if numel(stored) > MAX_ENTRIES
                stored = stored(1:MAX_ENTRIES);
            end
            writeList(stored);
        end
    case "remove"
        canon = canonical(file);
        stored = stored(~pathsMatch(stored, canon));
        writeList(stored);
    case "clear"
        stored = strings(0, 1);
        writeList(stored);
    otherwise
        error('gui2:recentFiles:badAction', ...
            'Unknown action "%s" (expected get/add/remove/clear/path).', action);
end

% Filter on READ, per rule 2 — the list on disk may name files that have
% since gone away.
if isempty(stored)
    files = strings(0, 1);
    return
end
files = stored(arrayfun(@isfile, stored));
end

% ---- helpers -------------------------------------------------------------

function p = storePath()
%STOREPATH  Per-user location for the list. Never pwd, never the repo.
p = fullfile(prefdir(), 'fastener-tool-recent.json');
end

function list = readList()
%READLIST  The stored list, or empty on any problem.
list = strings(0, 1);
f = storePath();
if ~isfile(f)
    return
end
try
    raw = jsondecode(fileread(f));
    if isfield(raw, 'recent') && ~isempty(raw.recent)
        list = string(raw.recent(:));
    end
catch
    % Corrupt or unreadable — behave as if there were no list. A broken
    % recent file must never stop the app opening.
end
end

function writeList(list)
%WRITELIST  Persist the list; a failure is swallowed.
try
    txt = jsonencode(struct('recent', {cellstr(list(:))}));
    fid = fopen(storePath(), 'w');
    if fid < 0
        return
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, txt, 'char');
catch
    % Read-only prefdir, full disk, locked file — none of these are worth
    % interrupting the user for.
end
end

function c = canonical(file)
%CANONICAL  Absolute path for comparison, or "" when it cannot be resolved.
c = "";
if strlength(file) == 0
    return
end
try
    info = dir(file);
    if isscalar(info) && ~info.isdir
        c = string(fullfile(info.folder, info.name));
        return
    end
catch
    % Fall through: an unresolvable path still compares usefully as typed.
end
c = file;
end

function tf = pathsMatch(list, target)
%PATHSMATCH  Elementwise path equality, case-insensitive on Windows.
if isempty(list)
    tf = false(size(list));
    return
end
if ispc
    tf = strcmpi(list, target);
else
    tf = strcmp(list, target);
end
end
