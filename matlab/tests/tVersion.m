classdef tVersion < matlab.unittest.TestCase
    %TVERSION  toolVersion is the ONE definition, and it reaches the output.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   WHY THIS EXISTS. The version string was copy-pasted into three
    %   unrelated layers - fastenerTool, gui.FastenerApp and
    %   gui2.AppState - with a comment asking a human to keep them in
    %   sync and nothing that would fail if one drifted. A report could
    %   then claim a different version from the window title, and the
    %   only symptom would be on a PDF nobody re-reads.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function versionIsASingleSemverString(testCase)
            v = toolVersion();
            testCase.verifyClass(v, "string");
            testCase.verifyTrue(isscalar(v));
            testCase.verifyTrue(~isempty(regexp(v, "^\d+\.\d+\.\d+$", "once")), ...
                'The version must be MAJOR.MINOR.PATCH and nothing else.');
        end

        function everyShellReportsTheSameVersion(testCase)
            % The drift guard, on the constant a test can actually see.
            testCase.verifyEqual(gui2.AppState.ToolVersion, toolVersion());

            % gui.FastenerApp.ToolVersion is deliberately NOT asserted here:
            % it is a PRIVATE constant, so reading it from a test errors
            % with MATLAB:class:GetProhibited. Nothing is lost. It now reads
            % toolVersion() rather than carrying its own literal, so it
            % cannot drift by construction - which is the property this test
            % was protecting - and +gui is slated for deletion at step 10.
        end

        function theCaseFormatIsNotTiedToTheToolVersion(testCase)
            % Bumping a release must never invalidate a user's saved
            % cases, so the case-file tag has to be independent of - and
            % must not contain - the version string.
            testCase.verifyFalse( ...
                contains(gui2.AppState.CaseFormat, toolVersion()), ...
                'The case format must not embed the tool version.');
        end
    end
end
