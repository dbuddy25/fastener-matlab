classdef ProgressCounter < matlab.unittest.plugins.TestRunnerPlugin
    %PROGRESSCOUNTER  Live filling progress bar while the suite runs.
    %   Replaces the framework's row of dots with one bar line per test:
    %
    %    142/770 ████████▌░░░░░░░░░░░░░░░░░░░  18%  1:47  tGui2Bulk/theRunBu
    %    143/770 ████████▋░░░░░░░░░░░░░░░░░░░  19%  1:48  tGui2Bulk/aCancell  ** FAILED
    %
    %   WHY. The full suite takes ~12 minutes on the machine that runs it,
    %   which is not the machine it is written on. A row of identical dots
    %   says the run is alive but not how far along it is, so there was no
    %   way to tell a slow run from a hung one without waiting it out —
    %   which is exactly the guess that was made, wrongly, on 2026-08-13.
    %
    %   EIGHTHS, NOT WHOLE CELLS. At 28 cells a whole-cell bar advances
    %   once every ~28 tests, so most lines would look identical to the one
    %   above them — the dots problem again, with wider dots. The bar is
    %   drawn to 1/8 of a cell using U+2588 and its partial-block siblings
    %   (▏▎▍▌▋▊▉), giving 224 distinct states across the run. At 770 tests
    %   that is roughly one visible step every 3-4 tests, so consecutive
    %   lines differ and the thing actually reads as filling.
    %
    %   The glyphs are U+2588 / U+2591 and U+258F..U+2589, all present in
    %   Consolas and the other default MATLAB console fonts. If a font ever
    %   lacks them the bar degrades to boxes — cosmetic only; the count and
    %   percentage beside it carry the same information.
    %
    %   FAILURES ARE MARKED INLINE as well as in the end-of-run block that
    %   runTests prints. Seeing "** FAILED" at test 143 of 770 means you can
    %   stop a doomed 12-minute run at 90 seconds instead of reading the
    %   verdict at the end.
    %
    %   Uses reportFinalizedResult, the documented per-result hook (R2019a+;
    %   this project targets R2026a). runTests wires it up with
    %   DiagnosticsRecordingPlugin — which printFailureDetail needs for
    %   Details.DiagnosticRecord — and no text-output plugin, so this is the
    %   only per-test output and the dots do not double up.
    %
    %   Not exercised by the suite itself: it IS the suite runner, so a test
    %   would have to run a nested runner to see it. runTests falls back to
    %   runtests() and says so loudly if constructing this path throws.

    properties (Access = private)
        Total   (1,1) double = 0     % test count for the whole run
        Done    (1,1) double = 0     % finalized so far
        Clock                        % tic handle for elapsed
        BarWidth  (1,1) double = 28  % bar cells (x8 sub-steps = 224 states)
        NameWidth (1,1) double = 34  % truncation width for the test name
    end

    methods (Access = protected)
        function runTestSuite(plugin, pluginData)
            %RUNTESTSUITE  Capture the denominator and start the clock.
            plugin.Total = numel(pluginData.TestSuite);
            plugin.Done  = 0;
            plugin.Clock = tic;
            runTestSuite@matlab.unittest.plugins.TestRunnerPlugin( ...
                plugin, pluginData);
        end

        function reportFinalizedResult(plugin, pluginData)
            %REPORTFINALIZEDRESULT  One line per finished test.
            plugin.Done = plugin.Done + 1;
            r = pluginData.TestResult;

            elapsed = toc(plugin.Clock);
            if plugin.Total > 0
                frac = plugin.Done / plugin.Total;
            else
                frac = 0;
            end

            mark = "";
            if r.Failed
                mark = "  ** FAILED";
            elseif r.Incomplete
                mark = "  ** INCOMPLETE";
            end

            fprintf("%4d/%-4d %s %3.0f%%  %5s  %s%s\n", ...
                plugin.Done, plugin.Total, ...
                testing.ProgressCounter.barText(frac, plugin.BarWidth), ...
                floor(100 * frac), ...   % floor: 100% only on the last test
                testing.ProgressCounter.clockText(elapsed), ...
                testing.ProgressCounter.shorten(r.Name, plugin.NameWidth), ...
                mark);

            reportFinalizedResult@matlab.unittest.plugins.TestRunnerPlugin( ...
                plugin, pluginData);
        end
    end

    methods (Static, Access = private)
        function s = barText(frac, cells)
            %BARTEXT  A proportional bar drawn to 1/8 of a cell.
            %   frac in [0,1]; cells is the bar width in characters.
            %
            %   Each cell holds 8 sub-steps, so the fill in sub-steps is
            %   floor(frac*cells*8). Computing it ONCE, on the total,
            %   rather than separately on the whole and partial parts, is
            %   what keeps the bar monotonic: split rounding can make a
            %   later test draw a shorter bar than an earlier one.
            %
            %   FLOOR, NOT ROUND, so a completely full bar means FINISHED.
            %   With round(), test 769 of 770 already filled every cell —
            %   the one moment the bar most needs to be honest is the one
            %   where you are deciding whether it is safe to walk away.
            frac  = min(max(frac, 0), 1);
            eighths = floor(frac * cells * 8);
            full    = floor(eighths / 8);
            part    = eighths - full * 8;        % 0..7

            % U+258F..U+2589 are 1/8..7/8 blocks; index 0 means the cell is
            % empty, so it takes the same glyph as the unfilled remainder.
            partials = [char(9617), char(9615), char(9614), char(9613), ...
                        char(9612), char(9611), char(9610), char(9609)];

            if full >= cells
                s = string(repmat(char(9608), 1, cells));
                return
            end
            s = string([repmat(char(9608), 1, full), ...
                        partials(part + 1), ...
                        repmat(char(9617), 1, cells - full - 1)]);
        end

        function s = clockText(seconds)
            %CLOCKTEXT  Seconds as m:ss (h:mm:ss past an hour).
            seconds = max(0, round(seconds));
            if seconds >= 3600
                s = string(sprintf("%d:%02d:%02d", ...
                    floor(seconds / 3600), ...
                    mod(floor(seconds / 60), 60), ...
                    mod(seconds, 60)));
            else
                s = string(sprintf("%d:%02d", ...
                    floor(seconds / 60), mod(seconds, 60)));
            end
        end

        function s = shorten(name, width)
            %SHORTEN  Keep a test name inside one terminal line.
            %   Trims from the FRONT: the leading package/class prefix is
            %   the repeated part, and the method name is what identifies
            %   the test.
            s = string(name);
            if strlength(s) > width
                s = "..." + extractAfter(s, strlength(s) - (width - 3));
            end
        end
    end
end
