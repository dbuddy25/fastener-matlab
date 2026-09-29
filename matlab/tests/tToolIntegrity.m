classdef tToolIntegrity < matlab.unittest.TestCase
    %TTOOLINTEGRITY  toolIntegrity: is the calculation code the release's?
    %
    %   Run from the matlab/ folder with:
    %       runTests("ToolIntegrity")
    %
    %   Every test works on a temp copy of a tiny code tree (Root=), so the
    %   checkout is never fingerprinted.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function noFingerprintMeansRunningFromSource(testCase)
            r = testCase.tree();
            [st, changed, txt] = toolIntegrity(Root=r);
            testCase.verifyEqual(st, "source");
            testCase.verifyEmpty(changed);
            testCase.verifySubstring(txt, "source");
        end

        function anUntouchedReleaseMatches(testCase)
            r = testCase.tree();
            toolIntegrity(Write=true, Root=r);
            [st, changed] = toolIntegrity(Root=r);
            testCase.verifyEqual(st, "release");
            testCase.verifyEmpty(changed);
        end

        function anEditedEquationIsNamed(testCase)
            r = testCase.tree();
            toolIntegrity(Write=true, Root=r);
            tToolIntegrity.write(fullfile(r, "+engine", "marginX.m"), "MS = P / Q - 2;");
            [st, changed, txt] = toolIntegrity(Root=r);
            testCase.verifyEqual(st, "modified");
            testCase.verifyEqual(changed, "+engine/marginX.m");
            testCase.verifySubstring(txt, "MODIFIED");
        end

        function anAddedFileCountsAsAChange(testCase)
            % A new file can shadow a released function.
            r = testCase.tree();
            toolIntegrity(Write=true, Root=r);
            tToolIntegrity.write(fullfile(r, "+engine", "private", "shadow.m"), "x = 1;");
            [st, changed] = toolIntegrity(Root=r);
            testCase.verifyEqual(st, "modified");
            testCase.verifyEqual(changed, "+engine/private/shadow.m");
        end

        function aRemovedFileCountsAsAChange(testCase)
            r = testCase.tree();
            toolIntegrity(Write=true, Root=r);
            delete(fullfile(r, "+model", "Thing.m"));
            [st, changed] = toolIntegrity(Root=r);
            testCase.verifyEqual(st, "modified");
            testCase.verifyEqual(changed, "+model/Thing.m");
        end

        function theExportAboutSheetCarriesTheState(testCase)
            c = report.aboutRows();
            testCase.verifyTrue(any(strcmp(c(:, 1), 'Calculation code')));
        end
    end

    methods
        function r = tree(testCase)
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            r = string(fx.Folder);
            tToolIntegrity.write(fullfile(r, "top.m"), "v = 1;");
            tToolIntegrity.write(fullfile(r, "+engine", "marginX.m"), "MS = P / Q - 1;");
            tToolIntegrity.write(fullfile(r, "+model", "Thing.m"), "t = 2;");
            tToolIntegrity.write(fullfile(r, "+data", "private", "helper.m"), "h = 3;");
        end
    end

    methods (Static, Access = private)
        function write(f, txt)
            d = fileparts(f);
            if ~isfolder(d)
                mkdir(d);
            end
            fid = fopen(f, 'w');
            fprintf(fid, '%s', txt);
            fclose(fid);
        end
    end
end
