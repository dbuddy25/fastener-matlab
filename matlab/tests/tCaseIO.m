classdef tCaseIO < matlab.unittest.TestCase
    %TCASEIO  Phase 3.7 acceptance: case save/load (JSON round-trip via
    %   data.toStruct/fromStruct) + factor presets (built-in + user).
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

    methods (Test)
        function caseRoundTripsLossless(testCase)
            % The strongest round-trip proof: re-analyze BOTH the original
            % and the save->load copy of the DABJ Section 9 case and verify
            % every published margin still matches, to a tight tolerance.
            c = validation.dabjSection9();

            f = data.saveCase(struct(Joint=c.Joint, LoadCase=c.LoadCase, ...
                                     Factors=c.Factors), [tempname '.json']);
            testCase.addTeardown(@() deleteIfPresent(f));
            testCase.verifyTrue(isfile(f));

            c2 = data.loadCase(f);
            testCase.verifyClass(c2.Joint, "model.Joint");
            testCase.verifyClass(c2.LoadCase, "model.LoadCase");
            testCase.verifyClass(c2.Factors, "model.Factors");

            r1 = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            r2 = engine.analyze(c2.Joint, c2.LoadCase, c2.Factors);

            names = ["Tension-Ultimate", "Tension-Yield", "Shear-Ultimate", ...
                     "Interaction", "Separation", "Slip"];
            for i = 1:numel(names)
                ms1 = marginMS(r1, names(i));
                ms2 = marginMS(r2, names(i));
                testCase.verifyEqual(ms2, ms1, "AbsTol", 1e-9, ...
                    sprintf("Margin ""%s"" drifted across the JSON round-trip.", names(i)));
            end
            testCase.verifyEqual(r2.WorstMargin, r1.WorstMargin, "AbsTol", 1e-9);
            testCase.verifyEqual(r2.GoverningCheck, r1.GoverningCheck);

            % Spot-check a few reconstructed fields directly.
            testCase.verifyEqual(c2.Joint.BoltCount, c.Joint.BoltCount);
            testCase.verifyEqual(c2.Joint.PreloadSpec.NominalTorque, ...
                c.Joint.PreloadSpec.NominalTorque, "AbsTol", 1e-9);
            testCase.verifyEqual(c2.Joint.SlipMode, c.Joint.SlipMode);
            testCase.verifyClass(c2.Joint.SlipMode, "model.SlipMode");
            testCase.verifyEqual(numel(c2.Joint.FlangeStack), ...
                numel(c.Joint.FlangeStack));
            testCase.verifyEqual(c2.Joint.FlangeStack(1).Material.Ftu, ...
                c.Joint.FlangeStack(1).Material.Ftu, "AbsTol", 1e-9);
        end

        function factorPresetBuiltIn(testCase)
            f = data.factorPreset("NASA-STD-5020B");
            testCase.verifyClass(f, "model.Factors");
            testCase.verifyEqual(f.FSU, 1.4);
            testCase.verifyEqual(f.FSY, 1.25);
            testCase.verifyEqual(f.FSSep, 1.0);
            testCase.verifyEqual(f.FSSlip, 1.0);
            testCase.verifyEqual(f.FFU, 1.15);
            testCase.verifyEqual(f.FFY, 1.0);
            testCase.verifyEqual(f.FFSep, 1.0);
            testCase.verifyEqual(f.FFSlip, 1.0);
        end

        function factorPresetUnknownErrors(testCase)
            testCase.verifyError(@() data.factorPreset("NotARealPreset"), ...
                "data:factorPreset:unknown");
        end

        function userPresetSaveLoad(testCase)
            f = string(tempname) + ".json";
            testCase.addTeardown(@() deleteIfPresent(f));

            custom = model.Factors(FSU=1.5, FSY=1.3, FSSep=1.1, FSSlip=1.05, ...
                                   FFU=1.2, FFY=1.05, FFSep=1.05, FFSlip=1.05);
            data.saveFactorPreset("My Test Preset", custom, f);

            got = data.factorPreset("My Test Preset", f);
            testCase.verifyClass(got, "model.Factors");
            testCase.verifyEqual(got.FSU, 1.5);
            testCase.verifyEqual(got.FFU, 1.2);

            % Built-in names are protected — cannot be overwritten.
            testCase.verifyError( ...
                @() data.saveFactorPreset("NASA-STD-5020B", custom, f), ...
                "data:saveFactorPreset:protectedName");
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function ms = marginMS(r, name)
%MARGINMS  Look up one margin's MS by Name from Result.Margins.
mask = [r.Margins.Name] == name;
assert(nnz(mask) == 1, "margin ""%s"" not found exactly once", name);
ms = r.Margins(mask).MS;
end

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove a temp file if it exists.
if isfile(f)
    delete(f);
end
end
