classdef tFastenerToolSmoke < matlab.unittest.TestCase
    %TFASTENERTOOLSMOKE  Phase 1 acceptance: the stub entry point runs cleanly.
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
        function stubRunsWarningFree(testCase)
            % "Done when: the project opens and the stub runs."
            testCase.verifyWarningFree(@fastenerTool);
        end
    end
end
