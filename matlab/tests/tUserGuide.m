classdef tUserGuide < matlab.unittest.TestCase
    %TUSERGUIDE  The bundled HTML user guide (matlab/userguide).
    %
    %   Run from the matlab/ folder with:
    %       runTests("UserGuide")
    %
    %   Nothing here opens a browser. The guide is static files, so what can
    %   rot is a broken link, a network dependency on an offline machine, or
    %   a check the engine gained that the Results page never documented.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function theIndexIsWhereHelpLooks(testCase)
            testCase.verifyTrue(isfile(gui.userGuidePath()), ...
                "Help > User Guide opens a file that is not there.");
        end

        function everyLocalLinkAndImageResolves(testCase)
            [files, folder] = tUserGuide.guideFiles("*.html");
            targets = strings(0, 1);
            for f = files
                txt  = fileread(fullfile(folder, f));
                refs = regexp(txt, '(?:href|src)="([^"]*)"', 'tokens');
                refs = string(cellfun(@(c) c{1}, refs, 'UniformOutput', false));
                % img/ is build output (tools/captureUserGuideScreens), gitignored.
                refs = refs(~startsWith(refs, ["#", "mailto:", "img/"]) & refs ~= "");
                refs = extractBefore(refs + "#", "#");
                for r = refs(:)'
                    targets(end + 1, 1) = r; %#ok<AGROW>
                    testCase.verifyTrue(isfile(fullfile(folder, r)), ...
                        sprintf('%s links to "%s", which does not exist.', f, r));
                end
            end
            % Companion: an empty harvest would pass the loop above vacuously.
            testCase.verifyTrue(any(targets == "guide.css"), ...
                "No page linked the stylesheet; the link harvest found nothing.");
            testCase.verifyTrue(any(targets == "Results.html"));
        end

        function nothingLoadsFromTheNetwork(testCase)
            % Work machines are often offline; the guide must still render.
            [files, folder] = tUserGuide.guideFiles(["*.html", "*.css"]);
            testCase.assertNotEmpty(files);
            for f = files
                txt = fileread(fullfile(folder, f));
                testCase.verifyEmpty(regexp(txt, 'https?://', 'once'), ...
                    sprintf('%s reaches the network.', f));
            end
        end

        function resultsDocumentsEveryCheckTheEngineReports(testCase)
            txt = fileread(gui.userGuidePath("Results.html"));
            documented = regexp(txt, 'data-check="([^"]+)"', 'tokens');
            documented = string(cellfun(@(c) c{1}, documented, 'UniformOutput', false));

            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            reported = [r.Margins.Name];

            testCase.verifyNumElements(reported, 15);
            testCase.verifyEqual(sort(documented), sort(reported), ...
                "The Results page's check table and the engine's rows differ.");
        end
    end

    methods (Test)
        function theForceWorkbookColumnsAreWhatTheReaderNeeds(testCase)
            % The guide's "Required: Yes" columns for Import Workbook... must
            % be enough for the reader, and each one must be necessary.
            txt = fileread(gui.userGuidePath("ElementForces.html"));
            rows = regexp(txt, '<tr><td>(.*?)</td><td>Yes</td>', 'tokens');
            cols = strings(1, 0);
            for i = 1:numel(rows)
                c = regexp(rows{i}{1}, '<code>([^<]+)</code>', 'tokens');
                cols = [cols, string(cellfun(@(x) x{1}, c, 'UniformOutput', false))]; %#ok<AGROW>
            end
            testCase.assertNumElements(cols, 7, ...
                "Could not read the required columns from ElementForces.html.");

            dir0 = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            ok = fullfile(dir0, "ok.xlsx");
            tUserGuide.writeForces(ok, cols);
            el = data.loadElementWorkbook(ok);
            testCase.verifyNumElements(el, 1, ...
                "A workbook with exactly the documented columns did not import.");

            for k = 1:numel(cols)
                f = fullfile(dir0, "no_" + k + ".xlsx");
                tUserGuide.writeForces(f, cols([1:k-1, k+1:end]));
                testCase.verifyError(@() data.loadElementWorkbook(f), ...
                    "data:loadElementWorkbook:noForceSheets", ...
                    sprintf('The guide calls "%s" required, but the reader imports without it.', cols(k)));
            end
        end
    end

    methods (Static, Access = private)
        function writeForces(file, cols)
            vals = num2cell([1001, 1:numel(cols) - 1]);
            writecell([cellstr(cols); vals], file, 'Sheet', 'Quasistatic');
        end

        function [names, folder] = guideFiles(patterns)
            folder = fileparts(gui.userGuidePath());
            names = strings(1, 0);
            for p = patterns
                d = dir(fullfile(folder, p));
                names = [names, string({d.name})]; %#ok<AGROW>
            end
        end
    end
end
