classdef tLibrary < matlab.unittest.TestCase
    %TLIBRARY  Phase 2.2 acceptance: pull the DABJ case's bolt + materials
    %   out of the library by key.
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
        function loadsDefaultLibrary(testCase)
            lib = data.Library.load();
            testCase.verifyClass(lib, "data.Library");
            testCase.verifyEqual(lib.SchemaVersion, 1);
        end

        function pullsBoltByKey(testCase)
            lib = data.Library.load();
            b = lib.bolt("3/8-24 UNF");
            testCase.verifyClass(b, "model.Bolt");
            testCase.verifyEqual(b.NominalDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(b.TensileStressArea, 0.0878, "AbsTol", 1e-6);
            testCase.verifyEqual(b.Series, model.ThreadSeries.UNF);
            testCase.verifyEqual(b.ThreadsPerInch, 24);
        end

        function pullsMaterialByKey(testCase)
            lib = data.Library.load();
            m = lib.material("A-286");
            testCase.verifyClass(m, "model.Material");
            testCase.verifyEqual(m.Ftu, 160000);
            testCase.verifyEqual(m.Fty, 120000);
            testCase.verifyEqual(m.Fsu, 95000);
        end

        function pullsBoltSpec(testCase)
            lib = data.Library.load();
            s = lib.boltSpec("3/8 A-286 160ksi");
            testCase.verifyEqual(s.RatedUltimateLoad, 15200);
            testCase.verifyEqual(s.RatedYieldLoad, 11400);
            testCase.verifyEqual(s.Bolt, "3/8-24 UNF");
            testCase.verifyEqual(s.Material, "A-286");
        end

        function boltCarriesHeadBearingAndThreadLength(testCase)
            % XLSX-template prep: the library maps headBearingDiameter
            % (d_wf = 0.523 per DABJ Example 8-b) and threadLength (assumed
            % 0.625 in; see the entry's source note) onto the model.Bolt.
            lib = data.Library.load();
            b = lib.bolt("3/8-24 UNF");
            testCase.verifyEqual(b.HeadBearingDiameter, 0.523, "AbsTol", 1e-12);
            testCase.verifyEqual(b.ThreadLength, 0.625, "AbsTol", 1e-12);
        end

        function unknownKeyErrors(testCase)
            lib = data.Library.load();
            testCase.verifyError(@() lib.material("NoSuchThing"), ...
                "data:Library:keyNotFound");
        end
    end
end
