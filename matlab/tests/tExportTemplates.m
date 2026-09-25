classdef tExportTemplates < matlab.unittest.TestCase
    %TEXPORTTEMPLATES  The styled export template and its writer.
    %
    %   Run from the matlab/ folder with:
    %       runTests("ExportTemplates")
    %
    %   The template is built outside MATLAB (tools/make_export_templates.py),
    %   so the contract between it and report.exportLayout is checked here:
    %   a renamed or moved range fails before any export writes to the
    %   wrong cells.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function layoutMatchesTheTemplatesNamedRanges(testCase)
            names = tExportTemplates.definedNames(tExportTemplates.templateFile());
            L = report.exportLayout();
            for f = string(fieldnames(L))'
                testCase.verifyTrue(isKey(names, char(f)), ...
                    sprintf('The template has no named range "%s".', f));
                if isKey(names, char(f))
                    testCase.verifyEqual(names(char(f)), L.(f).Ref, ...
                        sprintf('"%s" moved in the template.', f));
                end
            end
        end

        function theWriterFillsEveryBlockAndKeepsTheStyling(testCase)
            f = testCase.tempXlsx();
            report.writeSingleJointWorkbook(f, tExportTemplates.sampleView());

            title = readcell(f, 'Sheet', 'Slide', 'Range', 'A1:A1');
            testCase.verifyEqual(title{1}, 'Sample: 1 of 2 displayed checks FAIL');
            m = readcell(f, 'Sheet', 'Slide', 'Range', 'D5:G6');
            testCase.verifyEqual(m{1, 2}, 0.69, 'AbsTol', 1e-12, ...
                'A margin must land as a number, so its format and colour apply.');
            testCase.verifyEqual(m{2, 3}, 'FAIL');
            d = readcell(f, 'Sheet', 'Detail', 'Range', 'A2:B3');
            testCase.verifyEqual(d{2, 2}, 'FAIL');
            a = readcell(f, 'Sheet', 'About', 'Range', 'A2:B2');
            testCase.verifyEqual(a{1, 1}, 'Tool');

            x = tExportTemplates.unzipped(testCase, f);
            sheets = tExportTemplates.allSheets(x);
            testCase.verifyTrue(contains(sheets, "<conditionalFormatting"), ...
                'The pass/fail colour rules did not survive the write.');
            colD = regexp(sheets, '<col [^>]*min="4"[^>]*>', 'match', 'once');
            w = str2double(regexp(colD, 'width="([\d.]+)"', 'tokens', 'once'));
            testCase.verifyEqual(w, 24, 'AbsTol', 1.5, ...
                'Column widths were resized on write (AutoFitWidth).');
        end

        function aViewTooBigForTheTemplateIsRefused(testCase)
            v = tExportTemplates.sampleView();
            v.Inputs = repmat({'x', 'y'}, 16, 1);
            testCase.verifyError(@() report.writeSingleJointWorkbook( ...
                testCase.tempXlsx(), v), "report:writeSingleJointWorkbook:tooBig");
        end
    end

    methods
        function f = tempXlsx(testCase)
            f = string(tempname) + ".xlsx";
            testCase.addTeardown(@() tExportTemplates.deleteIfPresent(f));
        end
    end

    methods (Static, Access = private)
        function f = templateFile()
            f = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
                "templates", "export_single.xlsx");
        end

        function v = sampleView()
            v = struct( ...
                'Title', 'Sample: 1 of 2 displayed checks FAIL', ...
                'Subtitle', 'Worst margin -0.65 (Slip)', ...
                'VerdictClass', 'fail', ...
                'Scope', 'Scope note.', ...
                'Inputs', {{'Bolt', 'NAS1351 3/8-24'; 'Preload', '470 in-lbf'}}, ...
                'Margins', {{'Tension-Ultimate', 0.69, 'Pass', 'NASA-STD-5020B Eq. 6'; ...
                             'Slip', -0.65, 'FAIL', 'NASA-STD-5020B Eq. 84'}}, ...
                'Details', {{'Tension-Ultimate', 'Pass', 0.69, 'Eq. 6', 'Ptu = 9000 lbf', ''; ...
                             'Slip', 'FAIL', -0.65, 'Eq. 84', '', ''}}, ...
                'About', {{'Tool', 'Fastener Analysis Tool'; 'Version', char(toolVersion())}});
        end

        function names = definedNames(file)
            x = string(tempname);
            unzip(file, x);
            cleanup = onCleanup(@() rmdir(x, 's'));
            txt = fileread(fullfile(x, "xl", "workbook.xml"));
            tok = regexp(txt, '<definedName name="([^"]+)"[^>]*>([^<]+)</definedName>', 'tokens');
            names = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(tok)
                names(tok{i}{1}) = string(tok{i}{2});
            end
        end

        function x = unzipped(testCase, file)
            x = string(tempname);
            unzip(file, x);
            testCase.addTeardown(@() rmdir(x, 's'));
        end

        function s = allSheets(x)
            s = "";
            for f = dir(fullfile(x, "xl", "worksheets", "*.xml"))'
                s = s + string(fileread(fullfile(f.folder, f.name)));
            end
        end

        function deleteIfPresent(f)
            if isfile(f)
                delete(f);
            end
        end
    end
end
