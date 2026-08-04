classdef tMakeTemplate < matlab.unittest.TestCase
    %TMAKETEMPLATE  Step 2b acceptance: data.makeTemplate workbook generator.
    %   The generated multi-sheet .xlsx must (a) exist and be non-empty,
    %   (b) round-trip through data.loadJointLibrary — the Joints sheet's
    %   two-row header (friendly names above the MATLAB names) is handled
    %   by the reader's header-row auto-detect, and the example rows are
    %   the sample four-bolt SHCS/nut joint + the insert joint — and (c)
    %   carry a Fields data-dictionary sheet with a row per input column.
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

            testCase.verifyEqual(jl(1).Name, "Sample four-bolt SHCS/nut joint");
            j = jl(1).Joint;
            testCase.verifyEqual(j.BoltCount, 4);
            testCase.verifyEqual(j.SlipMode, model.SlipMode.Joint);
            testCase.verifyEqual(j.Bolt.NominalDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.PreloadSpec.NominalTorque, 470);
            testCase.verifyEqual(numel(j.FlangeStack), 2);

            % BodyLengthInGrip / NutHeight are populated on this row so
            % stiffness (and everything downstream of it) resolves -- see
            % data.makeTemplate's sampleNutJointRow.
            testCase.verifyEqual(j.BodyLengthInGrip, 0.50, "AbsTol", 1e-12);
            testCase.verifyEqual(j.ThreadedMember.EngagementLength, 0.328, "AbsTol", 1e-12);

            testCase.verifyEqual(jl(2).Name, "Example insert joint");
            testCase.verifyEqual(jl(2).Joint.ThreadedMember.Type, ...
                model.ThreadedMemberType.Insert);

            % HelicoilRatedLoad round-trips through the generated workbook
            % (see data.makeTemplate's insertExampleRow); no
            % HelicoilShearArea column exists to round-trip -- analysts
            % cannot type ShearEngagementArea, so it stays at the model
            % default (NaN) and engine.marginInsert derives the
            % NASA-STD-5020B Section 4.4.1 parent-material area itself from
            % StiPitchDiameter (checked below) instead.
            testCase.verifyTrue( ...
                isnan(jl(2).Joint.ThreadedMember.ShearEngagementArea));
            testCase.verifyEqual( ...
                jl(2).Joint.ThreadedMember.RatedUltimateLoad, 2600, "AbsTol", 1e-12);

            % HelicoilLengthRatio (insertExampleRow: 1.5) round-trips onto
            % EngagementRatio itself, NOT a computed EngagementLength --
            % data.loadJointLibrary stores the ratio and lets
            % engine/private/resolveEngagementLength multiply it out per
            % row at analysis time.
            testCase.verifyEqual( ...
                jl(2).Joint.ThreadedMember.EngagementRatio, 1.5, "AbsTol", 1e-12);
            testCase.verifyTrue(isnan(jl(2).Joint.ThreadedMember.EngagementLength));

            % StiPitchDiameter has no column at all (catalogue lookup, not
            % analyst input -- see data.loadJointLibrary): the generated
            % workbook's insert row still resolves it from NAS1351 3/8-24's
            % thread size (0.375 in, 24 tpi) via data.Library.insertFor,
            % matching the seeded NASM33537-3750-24 stiPitchDiameterMin.
            testCase.verifyEqual( ...
                jl(2).Joint.ThreadedMember.StiPitchDiameter, 0.402, "AbsTol", 1e-9);
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
                        "Flange1Material", "NominalTempC", "element_id", ...
                        "HelicoilRatedLoad"]
                testCase.verifyTrue(any(names == want), ...
                    "Fields sheet is missing a row for " + want);
            end
            % HelicoilShearArea is deliberately NOT a dictionary row --
            % ShearEngagementArea has no analyst-facing column at all (see
            % data.loadJointLibrary), so the Fields sheet must not document
            % one either.
            testCase.verifyFalse(any(names == "HelicoilShearArea"), ...
                "Fields sheet should no longer document a HelicoilShearArea column");
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
