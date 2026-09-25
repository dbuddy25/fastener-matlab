classdef tGuiExport < matlab.uitest.TestCase
    %TGUIEXPORT  Results -> Export Table as the styled workbook.
    %
    %   Run from the matlab/ folder with:
    %       runTests("GuiExport")
    %
    %   Exports the DABJ Section 9 result through the page and reads the
    %   published margins back out of the file, so the workbook is held to
    %   the same answer key as the engine and the screen.

    properties
        App
        File
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (TestMethodSetup)
        function exportTheAnswerKey(testCase)
            testCase.App = gui.FastenerApp();
            testCase.addTeardown(@() delete(testCase.App));
            c = validation.dabjSection9();
            s = testCase.App.State;
            s.Joint = c.Joint;  s.LoadCase = c.LoadCase;  s.Factors = c.Factors;
            s.setResult(engine.analyze(c.Joint, c.LoadCase, c.Factors), ...
                struct('Joint', c.Joint, 'LoadCase', c.LoadCase, 'Factors', c.Factors));
            testCase.App.navigateTo("Results");

            testCase.File = string(tempname) + ".xlsx";
            [d, n] = fileparts(testCase.File);
            testCase.addTeardown(@() tGuiExport.deleteIfPresent(testCase.File));
            testCase.addTeardown(@() tGuiExport.deleteIfPresent( ...
                fullfile(d, n + "_section.png")));
            testCase.App.page("Results").writeWorkbook(testCase.File);
        end
    end

    methods (Test)
        function thePublishedMarginsLandInTheSlideTable(testCase)
            m = readcell(testCase.File, 'Sheet', 'Slide', 'Range', 'D5:G19');
            expect = {"Tension-Ultimate", 0.69; "Separation", 0.16; ...
                      "Tension-Yield", 0.63; "Shear-Ultimate", 3.18; ...
                      "Slip", -0.65};
            for k = 1:size(expect, 1)
                row = tGuiExport.rowOf(m, expect{k, 1});
                testCase.assertNotEmpty(row, expect{k, 1} + " is missing.");
                testCase.verifyEqual(m{row, 2}, expect{k, 2}, 'AbsTol', 0.01, ...
                    expect{k, 1} + " does not match the answer key.");
            end
            testCase.verifyEqual(m{tGuiExport.rowOf(m, "Slip"), 3}, 'FAIL');
        end

        function interactionIsWrittenAsItsRatio(testCase)
            m = readcell(testCase.File, 'Sheet', 'Slide', 'Range', 'D5:G19');
            row = tGuiExport.rowOf(m, "Interaction");
            testCase.verifyTrue(startsWith(string(m{row, 2}), "R = 0.48"), ...
                'Interaction must read as R (hand calc 0.48), never as a margin.');
            testCase.verifyEqual(m{row, 3}, 'Pass');
        end

        function everyCheckIsListedAndNoneIsBlank(testCase)
            m = readcell(testCase.File, 'Sheet', 'Slide', 'Range', 'D5:G19');
            testCase.verifyEqual(size(m, 1), 15);
            for row = 1:size(m, 1)
                testCase.verifyFalse(ismissing(string(m{row, 2})) && ...
                    ~isnumeric(m{row, 2}), sprintf('Row %d has a blank value.', row));
            end
            ne = find(strcmp(m(:, 3), 'Not evaluated'));
            testCase.assertNotEmpty(ne, 'The answer key has no not-evaluated row.');
            testCase.verifyEqual(m{ne(1), 2}, char(8212), ...
                'A not-evaluated check must read as an em dash (A1).');
        end

        function theTitleCarriesTheVerdict(testCase)
            t = readcell(testCase.File, 'Sheet', 'Slide', 'Range', 'A1:A1');
            testCase.verifySubstring(t{1}, 'FAIL');
            cls = readcell(testCase.File, 'Sheet', 'Slide', 'Range', 'I1:I1');
            testCase.verifyEqual(cls{1}, 'fail');
        end

        function detailAndAboutAreFilled(testCase)
            d = readcell(testCase.File, 'Sheet', 'Detail', 'Range', 'A2:F16');
            testCase.verifyEqual(size(d, 1), 15);
            a = readcell(testCase.File, 'Sheet', 'About', 'Range', 'A2:B25');
            testCase.verifyTrue(any(strcmp(a(:, 2), char(toolVersion()))));
        end

        function theCrossSectionImageIsWritten(testCase)
            [d, n] = fileparts(testCase.File);
            png = fullfile(d, n + "_section.png");
            testCase.verifyTrue(isfile(png), ...
                'No cross-section image beside the workbook (see the status bar).');
        end
    end

    methods (Static, Access = private)
        function row = rowOf(m, name)
            row = find(strcmp(m(:, 1), char(name)), 1);
        end

        function deleteIfPresent(f)
            if isfile(f)
                delete(f);
            end
        end
    end
end
