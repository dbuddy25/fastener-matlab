classdef tElementWorkbook < matlab.unittest.TestCase
    %TELEMENTWORKBOOK  data.loadElementWorkbook — the GUI's multi-sheet
    %   force-workbook reader: ONE LOAD CASE PER SHEET, the sheet name
    %   being the load case name, each sheet carrying exactly element_id +
    %   FX..MZ. Covers: sheet name -> LoadCaseName, header auto-detect /
    %   column order + case tolerance, the documented defaults (JointName
    %   "" / PatternId "" / ScaleFactor 1 / Reversible false — the GUI
    %   owns scale and reversible), graceful skipping of non-force sheets
    %   (reported via info, never fatal), the no-parsable-sheet error, and
    %   a REGRESSION GUARD that the flat data.loadElements reader — the
    %   headless runBulk/runWorkbook interface — is untouched.
    %
    %   Fixtures are throwaway .xlsx files built with writecell(...,
    %   "Sheet", name) into tempname paths, deleted on teardown — the
    %   tWorkbook.m temp-file pattern.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Static, Access = private)
        function p = templatePath(name)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            p = string(fullfile(srcDir, "templates", name));
        end

        function f = writeTempXlsx(testCase, sheets)
            %WRITETEMPXLSX  Throwaway workbook; deleted on teardown.
            %   sheets: cell array of {sheetName, cellGrid} pairs, written
            %   in order (sheetnames() then returns the same order).
            f = string(tempname) + ".xlsx";
            for i = 1:numel(sheets)
                writecell(sheets{i}{2}, f, "Sheet", sheets{i}{1});
            end
            testCase.addTeardown(@() deleteIfPresent(f));
        end
    end

    methods (Test)
        function sheetNameBecomesLoadCase(testCase)
            % Two force sheets -> rows carrying each SHEET's name as
            % LoadCaseName, in sheet order. Expected values are the
            % fixture literals below (element 1001's FX 1560 / FZ 5590
            % mirror the data.makeTemplate demo example row -- values
            % borrowed from DABJ Sec. 9, not the row itself).
            % Also checks the documented defaults on EVERY row: the
            % workbook format has no joint/pattern/scale/reversible
            % columns, so JointName "" (the Element Mapping tab is the
            % authority), PatternId "", ScaleFactor 1, Reversible false.
            hdr = {'element_id', 'FX', 'FY', 'FZ', 'MX', 'MY', 'MZ'};
            f = tElementWorkbook.writeTempXlsx(testCase, { ...
                {"Liftoff", [hdr; ...
                    {1001, 1560,   0, 5590,  0, 0, 0}; ...
                    {1002, -150, 200, -800, 10, 5, 0}]}, ...
                {"Landing", [hdr; ...
                    {1003, 50, 120, 400, 0, 0, 0}]}});

            [el, info] = data.loadElementWorkbook(f);
            testCase.assertEqual(numel(el), 3);

            testCase.verifyEqual(el(1).ElementId, "1001");
            testCase.verifyEqual(el(1).LoadCaseName, "Liftoff");
            testCase.verifyEqual(el(1).Forces.FX, 1560);
            testCase.verifyEqual(el(1).Forces.FZ, 5590);
            testCase.verifyEqual(el(2).ElementId, "1002");
            testCase.verifyEqual(el(2).LoadCaseName, "Liftoff");
            testCase.verifyEqual(el(2).Forces.FZ, -800);
            testCase.verifyEqual(el(2).Forces.MX, 10);
            testCase.verifyEqual(el(3).ElementId, "1003");
            testCase.verifyEqual(el(3).LoadCaseName, "Landing");
            testCase.verifyEqual(el(3).Forces.FY, 120);

            for i = 1:numel(el)   % the documented GUI-owned defaults
                testCase.verifyEqual(el(i).JointName, "");
                testCase.verifyEqual(el(i).PatternId, "");
                testCase.verifyEqual(el(i).ScaleFactor, 1);
                testCase.verifyFalse(el(i).Reversible);
            end

            % info: both sheets parsed, none skipped, per-sheet row counts
            testCase.verifyEqual(info.ParsedSheetCount, 2);
            testCase.verifyEqual(info.SkippedSheetCount, 0);
            testCase.assertEqual(numel(info.Sheets), 2);
            testCase.verifyEqual(info.Sheets(1).Name, "Liftoff");
            testCase.verifyTrue(info.Sheets(1).Parsed);
            testCase.verifyEqual(info.Sheets(1).RowCount, 2);
            testCase.verifyEqual(info.Sheets(1).SkippedRowCount, 0);
            testCase.verifyEqual(info.Sheets(2).Name, "Landing");
            testCase.verifyEqual(info.Sheets(2).RowCount, 1);
        end

        function columnOrderAndCaseTolerated(testCase)
            % Shuffled column order, mixed-case header names, and a
            % friendly banner row ABOVE the header (the header-row
            % auto-detect shared with data.loadElements must lock onto
            % the real header). Expected values are the fixture literals:
            % each force column carries a distinct value so a column
            % mix-up cannot pass. Blank cells in required columns read
            % as 0 (the loadElements convention).
            f = tElementWorkbook.writeTempXlsx(testCase, { ...
                {"LC-01", [ ...
                    {'My NASTRAN export (subcase 1)', '', '', '', '', '', ''}; ...
                    {'fx', 'Fy', 'FZ', 'mx', 'MY', 'mz', 'Element_ID'}; ...
                    {10, 20, 30, 1, 2, 3, 7001}; ...
                    {40, '', 60, 4, 5, 6, 7002}]}});

            [el, info] = data.loadElementWorkbook(f);
            testCase.assertEqual(numel(el), 2);
            testCase.verifyEqual(el(1).ElementId, "7001");
            testCase.verifyEqual(el(1).LoadCaseName, "LC-01");
            testCase.verifyEqual(el(1).Forces.FX, 10);
            testCase.verifyEqual(el(1).Forces.FY, 20);
            testCase.verifyEqual(el(1).Forces.FZ, 30);
            testCase.verifyEqual(el(1).Forces.MX, 1);
            testCase.verifyEqual(el(1).Forces.MY, 2);
            testCase.verifyEqual(el(1).Forces.MZ, 3);
            testCase.verifyEqual(el(2).ElementId, "7002");
            testCase.verifyEqual(el(2).Forces.FY, 0);   % blank cell -> 0
            testCase.verifyEqual(info.ParsedSheetCount, 1);
        end

        function nonForceSheetSkippedAndReported(testCase)
            % A workbook may carry a notes/cover sheet (no recognisable
            % header) and a partially-tabular sheet missing required
            % columns — both must be SKIPPED and REPORTED via info, never
            % fatal, while the real force sheet parses. Expected values
            % are the fixture literals below.
            hdr = {'element_id', 'FX', 'FY', 'FZ', 'MX', 'MY', 'MZ'};
            f = tElementWorkbook.writeTempXlsx(testCase, { ...
                {"Notes", {'Prepared by DB'; 'For internal review only'}}, ...
                {"Partial", [{'element_id', 'FX', 'FY'}; {9001, 1, 2}]}, ...
                {"Liftoff", [hdr; {1001, 100, 0, 250, 0, 0, 0}]}});

            [el, info] = data.loadElementWorkbook(f);
            testCase.assertEqual(numel(el), 1);   % only the Liftoff row
            testCase.verifyEqual(el(1).ElementId, "1001");
            testCase.verifyEqual(el(1).LoadCaseName, "Liftoff");

            testCase.verifyEqual(info.ParsedSheetCount, 1);
            testCase.verifyEqual(info.SkippedSheetCount, 2);
            testCase.assertEqual(numel(info.Sheets), 3);
            % Notes: no row scores >= 3 known column names -> no header
            testCase.verifyEqual(info.Sheets(1).Name, "Notes");
            testCase.verifyFalse(info.Sheets(1).Parsed);
            testCase.verifySubstring(info.Sheets(1).SkipReason, "header");
            % Partial: header found (3 matches) but the four moment/force
            % columns are missing -> skipped naming the missing columns
            testCase.verifyEqual(info.Sheets(2).Name, "Partial");
            testCase.verifyFalse(info.Sheets(2).Parsed);
            testCase.verifySubstring(info.Sheets(2).SkipReason, "FZ");
            testCase.verifySubstring(info.Sheets(2).SkipReason, "MZ");
            testCase.verifyTrue(info.Sheets(3).Parsed);
        end

        function blankIdRowSkippedAndReported(testCase)
            % Within a force sheet, a row WITH content but WITHOUT an
            % element_id is skipped and reported per sheet (the
            % data.loadElements info convention). Grid row numbering:
            % header is row 1 of the sheet, so the bad row is row 3.
            hdr = {'element_id', 'FX', 'FY', 'FZ', 'MX', 'MY', 'MZ'};
            f = tElementWorkbook.writeTempXlsx(testCase, { ...
                {"Liftoff", [hdr; ...
                    {1001, 100, 0, 250, 0, 0, 0}; ...
                    {'',   999, 0,   0, 0, 0, 0}; ...
                    {1002,  50, 0, 125, 0, 0, 0}]}});

            [el, info] = data.loadElementWorkbook(f);
            testCase.assertEqual(numel(el), 2);   % rows 1001 + 1002
            testCase.verifyEqual(el(1).ElementId, "1001");
            testCase.verifyEqual(el(2).ElementId, "1002");
            testCase.verifyEqual(info.Sheets(1).SkippedRowCount, 1);
            testCase.verifyEqual(info.Sheets(1).SkippedRows, 3);
        end

        function noParsableSheetErrors(testCase)
            % A workbook where NO sheet parses must raise the documented
            % error naming what was expected — a notes-only workbook must
            % not import as an empty success.
            f = tElementWorkbook.writeTempXlsx(testCase, { ...
                {"Notes", {'This workbook has no force sheets'}}});

            testCase.verifyError( ...
                @() data.loadElementWorkbook(f), ...
                "data:loadElementWorkbook:noForceSheets");
        end

        function loadElementsRegressionGuard(testCase)
            % REGRESSION GUARD: the flat data.loadElements reader — the
            % headless runBulk/runWorkbook interface — must be UNTOUCHED
            % by the workbook reader's addition. Expected values mirror
            % tBulkParsers.loadsElements, sourced from
            % templates/elements_template.csv (= the data.makeTemplate
            % elementExampleRows: 1001 carries the demo per-bolt limit
            % loads FX 1560 / FZ 5590, borrowed from DABJ Sec. 9).
            el = data.loadElements( ...
                tElementWorkbook.templatePath("elements_template.csv"));
            testCase.assertEqual(numel(el), 3);
            testCase.verifyEqual(el(1).ElementId, "1001");
            testCase.verifyEqual(el(1).JointName, "Sample four-bolt SHCS/nut joint");
            testCase.verifyEqual(el(1).LoadCaseName, "Liftoff");
            testCase.verifyEqual(el(1).PatternId, "PLATE-1");
            testCase.verifyEqual(el(1).Forces.FX, 1560);
            testCase.verifyEqual(el(1).Forces.FZ, 5590);
            testCase.verifyEqual(el(1).ScaleFactor, 1);
            testCase.verifyFalse(el(1).Reversible);
            testCase.verifyTrue(el(2).Reversible);       % template row 1002
            testCase.verifyEqual(el(3).ScaleFactor, 1.5, "AbsTol", 1e-12);

            % Same struct shape from both readers — every downstream
            % consumer of loadElements output works on workbook output.
            hdr = {'element_id', 'FX', 'FY', 'FZ', 'MX', 'MY', 'MZ'};
            f = tElementWorkbook.writeTempXlsx(testCase, { ...
                {"Liftoff", [hdr; {1001, 1, 2, 3, 4, 5, 6}]}});
            elWb = data.loadElementWorkbook(f);
            testCase.verifyEqual(fieldnames(elWb), fieldnames(el));
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove the temp workbook if it exists.
if isfile(f)
    delete(f);
end
end
