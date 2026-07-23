classdef tMakeTemplate < matlab.unittest.TestCase
    %TMAKETEMPLATE  Step 2b acceptance: data.makeTemplate workbook generator.
    %   The generated multi-sheet .xlsx must (a) exist and be non-empty,
    %   (b) round-trip through data.loadJointLibrary — the Joints sheet's
    %   two-row header (friendly names above the MATLAB names) is handled
    %   by the reader's header-row auto-detect, and the example rows are
    %   the DABJ Section 9 joint + the insert joint — and (c) carry a
    %   Fields data-dictionary sheet with a row per input column.
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

    methods (Access = private)
        function f = generateWorkbook(testCase)
            %GENERATEWORKBOOK  Make a throwaway template; deleted on teardown.
            f = data.makeTemplate(string(tempname) + ".xlsx");
            testCase.addTeardown(@() deleteIfPresent(f));
        end
    end

    methods (Test)
        function generatesWorkbook(testCase)
            f = testCase.generateWorkbook();

            testCase.assertTrue(isfile(f), "makeTemplate did not create the file");
            d = dir(f);
            testCase.assertGreaterThan(d.bytes, 0, "workbook is empty");

            % Parse-back: Joints is the FIRST sheet, so the plain reader
            % (which reads sheet 1) must parse it — friendly banner row
            % skipped by the header auto-detect, examples intact.
            jl = data.loadJointLibrary(f, data.Library.load());
            testCase.assertGreaterThanOrEqual(numel(jl), 2, ...
                "expected the two example joint rows");

            testCase.verifyEqual(jl(1).Name, "DABJ Sec. 9 class problem");
            j = jl(1).Joint;
            testCase.verifyEqual(j.BoltCount, 4);
            testCase.verifyEqual(j.SlipMode, model.SlipMode.Joint);
            testCase.verifyEqual(j.Bolt.NominalDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.PreloadSpec.NominalTorque, 470);
            testCase.verifyEqual(numel(j.FlangeStack), 2);

            testCase.verifyEqual(jl(2).Name, "Example insert joint");
            testCase.verifyEqual(jl(2).Joint.ThreadedMember.Type, ...
                model.ThreadedMemberType.Insert);
        end

        function fieldsSheetHasRows(testCase)
            f = testCase.generateWorkbook();

            try
                raw = readcell(f, "Sheet", "Fields");
            catch e
                testCase.assertFail("Fields sheet could not be read: " + ...
                    string(e.message));
                return
            end
            testCase.assertGreaterThan(size(raw, 1), 20, ...
                "Fields sheet has too few dictionary rows");
            testCase.assertGreaterThanOrEqual(size(raw, 2), 5, ...
                "Fields sheet must have the five dictionary columns");

            % Column 1 = MATLAB names; spot-check a spread of entries.
            names = strings(size(raw, 1), 1);
            for r = 1:size(raw, 1)
                v = raw{r, 1};
                if ischar(v) || isstring(v)
                    names(r) = string(v);
                end
            end
            for want = ["Name", "SlipMode", "NominalTorque", "AxialZ", ...
                        "Flange1Material", "NominalTempC", "element_id"]
                testCase.verifyTrue(any(names == want), ...
                    "Fields sheet is missing a row for " + want);
            end
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
