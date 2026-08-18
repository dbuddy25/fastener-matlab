function ok = openExternal(file, fig)
%OPENEXTERNAL  Hand a document to the operating system's default viewer.
%   ok = gui2.openExternal(file, fig) opens `file` in whatever the OS uses
%   for that type, and reports failure through a uialert on `fig` rather
%   than throwing. Returns whether the handoff was made.
%
%   THE ONE PLACE THE TOOL LEAVES ITSELF. Nothing else in this codebase
%   opens an external document, and there are three platform spellings, so
%   they live here rather than at each call site:
%       Windows   winopen
%       macOS     system("open")
%       Linux     system("xdg-open")
%
%   NEVER THROWS. A viewer that is missing, a file the OS refuses, a
%   sandbox that blocks the handoff -- none of those are reasons to
%   interrupt an analysis, and none are things the analyst can fix from
%   inside the tool. They get told, and the tool carries on.
%
%   Windows is the deployment target, so winopen is the branch that
%   matters; the other two exist because development happens on macOS and
%   a dev machine silently failing to open a file would look like a bug in
%   the References window rather than a platform gap.

arguments
    file (1,1) string
    fig       = []
end

ok = false;
if ~isfile(file)
    report(fig, sprintf( ...
        'That file is no longer where the tool expected it:\n%s', file));
    return
end

try
    if ispc
        winopen(char(file));
    elseif ismac
        status = system(sprintf('open "%s" &', file));
        if status ~= 0
            error("gui2:openExternal:failed", "open returned %d", status);
        end
    else
        status = system(sprintf('xdg-open "%s" &', file));
        if status ~= 0
            error("gui2:openExternal:failed", "xdg-open returned %d", status);
        end
    end
    ok = true;
catch err
    report(fig, sprintf( ...
        'Could not hand that document to the system viewer:\n%s', err.message));
end
end

% ---- Local helpers --------------------------------------------------------
function report(fig, msg)
%REPORT  Tell the analyst, if there is a window to tell them in.
%   Called from headless code (or from a test) fig is empty, and the
%   message goes nowhere rather than erroring on a missing figure.
if ~isempty(fig) && isvalid(fig)
    uialert(fig, msg, 'Cannot open document', 'Icon', 'warning');
end
end
