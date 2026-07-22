classdef tFastenerToolSmoke < matlab.unittest.TestCase
    %TFASTENERTOOLSMOKE  A1 acceptance: the stub entry point runs cleanly.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %   or just:
    %       runtests

    methods (Test)
        function stubRunsWarningFree(testCase)
            % "Done when: the project opens and the stub runs."
            testCase.verifyWarningFree(@fastenerTool);
        end
    end
end
