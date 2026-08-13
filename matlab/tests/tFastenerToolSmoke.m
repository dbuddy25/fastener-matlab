classdef tFastenerToolSmoke < matlab.unittest.TestCase
    %TFASTENERTOOLSMOKE  The documented entry point actually opens the app.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %   or just:
    %       runtests
    %
    %   The source folder (matlab/, one level up from tests/) is added to the
    %   path for the duration of the tests, so this passes regardless of the
    %   current folder — and later tests can reach the +engine/+data packages.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function theEntryPointOpensTheApp(testCase)
            % THIS TEST USED TO PASS AGAINST A STUB. It called
            % verifyWarningFree(@fastenerTool) when fastenerTool printed a
            % banner and returned — so "the documented entry point works"
            % was true of an entry point that launched nothing, for as long
            % as it took a dead-code review to notice (2026-08-13).
            %
            % It now opens the real app, which means the handle MUST be
            % captured and torn down: discarding it would leave a window
            % open for the rest of the suite, the orphaned-figure problem
            % gui2.FastenerApp.delete was extended to prevent.
            app = fastenerTool();
            testCase.addTeardown(@() delete(app));

            testCase.verifyClass(app, "gui2.FastenerApp");
            testCase.verifyTrue(isvalid(app), ...
                'The entry point must return a live app, not a stale handle.');
        end

        function theEntryPointIsWarningFree(testCase)
            % The original Phase 1 assertion, kept — but with the handle
            % captured this time.
            testCase.verifyWarningFree(@() closeAfter(testCase, fastenerTool()));
        end
    end
end

% ---- Local helpers --------------------------------------------------------
function closeAfter(testCase, app)
%CLOSEAFTER  Register teardown for an app opened inside a verifyWarningFree.
testCase.addTeardown(@() delete(app));
end
