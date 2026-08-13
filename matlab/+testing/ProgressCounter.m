classdef ProgressCounter < matlab.unittest.plugins.TestRunnerPlugin
    %PROGRESSCOUNTER  Live "n of N" progress while the suite runs.
    %   Replaces the framework's row of dots with one counted line per test:
    %
    %       142/770  18%  el 1:47  eta 8:12   tGui2Bulk/theRunButtonGates
    %       143/770  19%  el 1:48  eta 8:09   tGui2Bulk/aCancelledRunKeeps  ** FAILED
    %
    %   WHY. The full suite takes ~12 minutes on the machine that runs it,
    %   which is not the machine it is written on. A row of identical dots
    %   says the run is alive but not how far along it is, so there was no
    %   way to tell a slow run from a hung one without waiting it out —
    %   which is exactly the guess that was made, wrongly, on 2026-08-13.
    %   The percentage and the ETA are the whole point; the test name is
    %   there so a stall has a place to point at.
    %
    %   ETA is elapsed/done x remaining — a flat average, deliberately. The
    %   nine tGui2* files each build a real uifigure per test method and run
    %   far slower than the engine files, so the estimate drifts as the mix
    %   changes. It is a progress indicator, not a promise.
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
        Clock                        % tic handle for elapsed/ETA
        NameWidth (1,1) double = 52  % truncation width for the test name
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
                pct = 100 * plugin.Done / plugin.Total;
            else
                pct = 0;
            end
            % Flat-average ETA. Guard the first result, where elapsed/done
            % is noise, and the last, where remaining is zero.
            remaining = plugin.Total - plugin.Done;
            if plugin.Done > 0 && remaining > 0
                eta = testing.ProgressCounter.clockText( ...
                    elapsed / plugin.Done * remaining);
            else
                eta = "  -  ";
            end

            mark = "";
            if r.Failed
                mark = "  ** FAILED";
            elseif r.Incomplete
                mark = "  ** INCOMPLETE";
            end

            fprintf("%4d/%-4d %3.0f%%  el %s  eta %s   %s%s\n", ...
                plugin.Done, plugin.Total, pct, ...
                testing.ProgressCounter.clockText(elapsed), eta, ...
                testing.ProgressCounter.shorten(r.Name, plugin.NameWidth), ...
                mark);

            reportFinalizedResult@matlab.unittest.plugins.TestRunnerPlugin( ...
                plugin, pluginData);
        end
    end

    methods (Static, Access = private)
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
