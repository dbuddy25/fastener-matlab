classdef tExport < matlab.unittest.TestCase
    %TEXPORT  Phase 3.6 acceptance: engine.runBulk + report.exportResults.
    %   The one-call headless workflow (files in -> results table ->
    %   .xlsx out) must run end to end on the bundled template CSVs with
    %   the settings file supplying the global temperatures + factors
    %   (T = engine.runBulk(jointFile, elementsFile, settingsFile,
    %   outFile)), fall back to model.Factors() defaults when the settings
    %   argument is empty/omitted (including the backward-tolerant
    %   model.Factors object in that slot), and write an .xlsx that reads
    %   back with the same row count. The numbers themselves are already
    %   pinned by tBulk / tBulkParsers — this suite covers the
    %   orchestration + export shell.
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
    end

    methods (Test)
        function runBulkEndToEnd(testCase)
            % Templates in (joints + elements + settings), results table
            % out — one call, no error, the documented column set, and the
            % DABJ template rows analyze clean.
            T = engine.runBulk( ...
                tExport.templatePath("joint_library_template.csv"), ...
                tExport.templatePath("elements_template.csv"), ...
                tExport.templatePath("settings_template.csv"));

            testCase.verifyClass(T, "table");
            testCase.assertGreaterThan(height(T), 0);

            expectedVars = ["ElementId", "JointName", "LoadCase", ...
                "Axial", "Shear", ...
                "TensionUlt", "TensionYield", "ShearUlt", "ShearTearout", ...
                "Bearing", "BearingUnderHead", "BoltThreadShear", ...
                "NutStrength", "InsertInternal", "InsertExternal", ...
                "Separation", "Slip", "SepBeforeRupture", "Interaction", ...
                "TappedParent", ...
                "WorstMargin", "GoverningCheck", "Error", "Note"];
            testCase.verifyEqual( ...
                string(T.Properties.VariableNames), expectedVars);

            % Row 1 is the template's first DABJ element: clean analysis
            testCase.verifyEqual(T.ElementId(1), "1001");
            testCase.verifyEqual(T.JointName(1), "DABJ Sec. 9 class problem");
            testCase.verifyEqual(T.Error(1), "");
            testCase.verifyFalse(isnan(T.WorstMargin(1)));
        end

        function exportWritesFile(testCase)
            % The .xlsx lands on disk and reads back with the same row
            % count (writetable -> readtable roundtrip on the Results
            % sheet, which is written first).
            T = engine.runBulk( ...
                tExport.templatePath("joint_library_template.csv"), ...
                tExport.templatePath("elements_template.csv"), ...
                tExport.templatePath("settings_template.csv"));

            f = string(tempname) + ".xlsx";
            testCase.addTeardown(@() deleteIfPresent(f));

            out = report.exportResults(T, f);
            testCase.verifyTrue(isfile(out));

            T2 = readtable(out, "TextType", "string");
            testCase.verifyEqual(height(T2), height(T));
        end

        function runBulkDefaultFactors(testCase)
            % With the settings argument omitted (or empty), runBulk must
            % behave exactly like the built-in default preset
            % model.Factors() with the joints' own temperatures — and the
            % backward-tolerant model.Factors object in the settings slot
            % must match too.
            jf = tExport.templatePath("joint_library_template.csv");
            ef = tExport.templatePath("elements_template.csv");

            Tdef = engine.runBulk(jf, ef);                    % omitted
            Temp = engine.runBulk(jf, ef, "");                % empty
            Tfac = engine.runBulk(jf, ef, model.Factors());   % legacy slot

            testCase.verifyClass(Tdef, "table");
            testCase.assertEqual(height(Tdef), height(Temp));
            testCase.assertEqual(height(Tdef), height(Tfac));
            % Same margins from all three calls (row 1 analyzes clean, so
            % the values are real numbers, not NaN)
            testCase.verifyEqual(Tdef.WorstMargin(1), Temp.WorstMargin(1), ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(Tdef.WorstMargin(1), Tfac.WorstMargin(1), ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(Tdef.TensionUlt(1), Temp.TensionUlt(1), ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(Tdef.GoverningCheck(1), Temp.GoverningCheck(1));
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove the temp export if it exists.
if isfile(f)
    delete(f);
end
end
