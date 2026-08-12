function results = runTests(scope)
%RUNTESTS  Run the whole suite, or a subset, from the matlab/ folder.
%
%   runTests            every test (what a push must be green on)
%   runTests("engine")  everything EXCEPT the GUI tests — seconds, not minutes
%   runTests("gui")     the gui2 page tests only
%   runTests("Results") any test file whose name contains "Results"
%
%   WHY A SUBSET EXISTS. Six gui2 files build and tear down a real
%   FastenerApp for every single test method, and that is essentially the
%   whole runtime — the other 27 files are arithmetic against fixtures and
%   cost almost nothing. So "did I break the engine" is a question that can
%   be answered in seconds, while "is this safe to push" is the one that
%   costs eight minutes. Conflating them means paying the eight minutes to
%   learn something the short run already knew.
%
%   THE SUBSET IS FOR ITERATING, NOT FOR PUSHING. A green subset proves
%   only what it ran. Two of the failures this suite has caught were GUI
%   tests broken by an ENGINE-side change and an engine test broken by a
%   GUI-side one, so neither half reliably predicts the other. Run the
%   scope that matches what you touched while you work; run runTests
%   before you push.
%
%   Which subset matches what:
%       +engine, +model, +data, +report changes   -> runTests("engine")
%       one page in +gui2                          -> runTests("<PageName>")
%       +gui2/Page.m or FastenerApp.m              -> runTests("gui")
%       anything else, or before pushing           -> runTests
%
%   Scope matching is case-insensitive and by substring, so
%   runTests("jointconfig"), runTests("JointConfig") and
%   runTests("tGui2JointConfig") all select the same file.
%
%   FAILURES ARE REPEATED, CONDENSED, AT THE VERY BOTTOM. MATLAB's own
%   Failure Summary names the tests and says "Failed by verification",
%   which is not the same as saying what went wrong; the diagnostic that
%   names the cause is printed inline, hundreds of lines earlier. The tail
%   of a run is therefore self-contained: totals, then every failure with
%   its actual/expected. The suite runs on a different machine from the one
%   it is debugged on, and one screenshot of the end should be enough.

arguments
    scope (1,1) string = "all"
end

here    = fileparts(mfilename("fullpath"));
testDir = fullfile(here, "tests");

d = dir(fullfile(testDir, "t*.m"));
if isempty(d)
    error("runTests:noTests", "No test files found in %s.", testDir);
end
names = string({d.name});

% The split is by FILE NAME PREFIX rather than by a hand-kept list: a new
% tGui2 page file joins the slow set automatically, and a list would be one
% more thing to forget to update.
isGui = startsWith(names, "tGui2");

switch lower(scope)
    case "all"
        pick = names;
    case {"engine", "eng"}
        pick = names(~isGui);
    case "gui"
        pick = names(isGui);
    otherwise
        pick = names(contains(lower(names), lower(scope)));
        if isempty(pick)
            error("runTests:noMatch", ...
                "Nothing matches ""%s"". Use all | engine | gui | part of a file name.", ...
                scope);
        end
end

fprintf("runTests(""%s""): %d of %d files\n", scope, numel(pick), numel(names));

t0      = tic;
results = runtests(cellstr(fullfile(testDir, pick)));
elapsed = toc(t0);

fprintf("\n%s: %d passed, %d failed, %d incomplete  (%.0f s)\n", ...
    scope, nnz([results.Passed]), nnz([results.Failed]), ...
    nnz([results.Incomplete]), elapsed);

% A subset that passes has proven only what it ran, and the whole point of
% the message is to stop a green short run reading as permission to push.
if ~strcmpi(scope, "all")
    fprintf("SUBSET ONLY - run runTests before pushing.\n");
end

printFailureDetail(results);
end

% ---- Failure detail, LAST ---------------------------------------------------
function printFailureDetail(results)
%PRINTFAILUREDETAIL  Every failure's diagnostic, in one block at the end.
%   MATLAB's own Failure Summary gives names and "Failed by verification",
%   which says that something broke and nothing about what. The diagnostic
%   that actually names the cause is printed inline, hundreds of lines up,
%   interleaved with the rest of the run.
%
%   This repeats it at the BOTTOM, condensed, so the tail of the run is
%   self-contained: one screenshot carries the totals AND the reason for
%   every failure. That matters because the suite runs on a different
%   machine from the one it is debugged on.
%
%   Wrapped end to end: a run that has just told you 700 tests passed must
%   not then error while formatting its own report.
maxLines = 14;    % per failure — enough for actual/expected, not a wall
maxChars = 110;   % per line — keeps it inside a terminal width

try
    bad = results([results.Failed] | [results.Incomplete]);
    if isempty(bad)
        return
    end
    bar = repmat('=', 1, 76);
    fprintf('\n%s\nFAILURE DETAIL (%d)\n%s\n', bar, numel(bad), bar);

    for i = 1:numel(bad)
        fprintf('\n%d) %s\n', i, bad(i).Name);
        lines = diagnosticLines(bad(i));
        if isempty(lines)
            fprintf('   (no diagnostic recorded)\n');
            continue
        end
        shown = min(numel(lines), maxLines);
        for k = 1:shown
            t = lines(k);
            if strlength(t) > maxChars
                t = extractBefore(t, maxChars) + " ...";
            end
            fprintf('   %s\n', t);
        end
        if numel(lines) > shown
            fprintf('   ... %d more line(s) in the inline report above\n', ...
                numel(lines) - shown);
        end
    end
    fprintf('\n%s\n', bar);
catch
    % Never let the reporter be the thing that fails.
end
end

function lines = diagnosticLines(oneResult)
%DIAGNOSTICLINES  The interesting text from one failed TestResult.
%   Prefers the test's own message and the framework's actual/expected over
%   the full report, which carries a stack nobody reads from a photograph.
lines = string.empty(1, 0);
d = oneResult.Details;
if ~isstruct(d) || ~isfield(d, 'DiagnosticRecord')
    return
end
for r = reshape(d.DiagnosticRecord, 1, [])
    if isprop(r, 'Event') && strlength(string(r.Event)) > 0
        lines(end + 1) = "[" + string(r.Event) + "]"; %#ok<AGROW>
    end
    lines = [lines, textOf(r, 'TestDiagnosticResult')]; %#ok<AGROW>
    lines = [lines, textOf(r, 'FrameworkDiagnosticResult')]; %#ok<AGROW>
end
lines = lines(strlength(strtrim(lines)) > 0);
end

function out = textOf(rec, prop)
%TEXTOF  One diagnostic property as trimmed lines ("" when absent).
out = string.empty(1, 0);
if ~isprop(rec, prop)
    return
end
try
    v = rec.(prop);
catch
    return
end
if isempty(v)
    return
end
out = strtrim(splitlines(strjoin(string(v), newline)))';
% The separator rules the framework draws are noise in a condensed report.
out = out(~startsWith(out, "---") & ~startsWith(out, "==="));
end
