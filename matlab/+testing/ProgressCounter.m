classdef ProgressCounter < matlab.unittest.plugins.TestRunnerPlugin
    %PROGRESSCOUNTER  Live "n of N" progress while the suite runs.
    %   Replaces the framework's row of dots with one line per test:
    %
    %      142/770  tGui2Bulk/theRunButtonGatesOnAnEmptyCase
    %      143/770  tGui2Bulk/aCancelledRunKeepsTheOldTable    ** FAILED
    %
    %   WHY. The full suite takes ~12 minutes on the machine that runs it,
    %   which is not the machine it is written on. A row of identical dots
    %   says the run is alive but not how far along it is, so there was no
    %   way to tell a slow run from a hung one without waiting it out —
    %   which is exactly the guess that was made, wrongly, on 2026-08-13.
    %
    %   DELIBERATELY JUST THE COUNT AND THE NAME. An earlier version drew a
    %   filling bar in eighths-of-a-cell and carried elapsed + ETA on every
    %   line. It was more arithmetic than the question deserved: 770 bars
    %   scrolling past is a lot of ink for one number you can already read,
    %   and per-line timing is noise when the only timing anyone acts on is
    %   the total — which runTests already prints in its summary. The name
    %   stays because it is what a stalled run points at.
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
        Total     (1,1) double = 0   % test count for the whole run
        Done      (1,1) double = 0   % finalized so far
        NameWidth (1,1) double = 62  % truncation width for the test name
    end

    methods (Access = protected)
        function runTestSuite(plugin, pluginData)
            %RUNTESTSUITE  Capture the denominator before anything runs.
            plugin.Total = numel(pluginData.TestSuite);
            plugin.Done  = 0;
            runTestSuite@matlab.unittest.plugins.TestRunnerPlugin( ...
                plugin, pluginData);
        end

        function reportFinalizedResult(plugin, pluginData)
            %REPORTFINALIZEDRESULT  One line per finished test.
            plugin.Done = plugin.Done + 1;
            r = pluginData.TestResult;

            mark = "";
            if r.Failed
                mark = "    ** FAILED";
            elseif r.Incomplete
                mark = "    ** INCOMPLETE";
            end

            fprintf("%5d/%-5d %s%s\n", plugin.Done, plugin.Total, ...
                testing.ProgressCounter.shorten(r.Name, plugin.NameWidth), ...
                mark);

            reportFinalizedResult@matlab.unittest.plugins.TestRunnerPlugin( ...
                plugin, pluginData);
        end
    end

    methods (Static, Access = private)
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
