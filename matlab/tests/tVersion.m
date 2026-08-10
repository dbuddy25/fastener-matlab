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

        function noShellKeepsItsOwnCopyOfTheVersion(testCase)
            % THE DRIFT GUARD, and it now checks the thing that actually
            % drifts. Both shells used to hold `ToolVersion = toolVersion()`
            % as a Constant property, which looks like a single source and
            % is not: MATLAB evaluates a Constant default ONCE at class load
            % and caches it, so bumping toolVersion.m left both stale until
            % the classes were cleared. That is how this test caught a
            % 0.1.0 against a 0.2.0 in the same session.
            %
            % So the guard is no longer "do the copies agree" - there are no
            % copies. It is "does anything still keep one".
            src = fileread(fullfile(fileparts(fileparts( ...
                which("tVersion"))), "+gui2", "AppState.m"));
            testCase.verifyEmpty( ...
                regexp(src, '^\s*ToolVersion\s*=', 'once', 'lineanchors'), ...
                'gui2.AppState must not cache its own copy of the version.');
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
