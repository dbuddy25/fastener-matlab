classdef tBulkParsers < matlab.unittest.TestCase
    %TBULKPARSERS  Phase 3.5b acceptance: the bulk input parsers.
    %   data.loadJointLibrary (joint-definition table -> model.Joint per row,
    %   library keys resolved through data.Library) and data.loadElements
    %   (element + forces table -> struct array for engine.resolveForces).
    %   Both are exercised against the shipped template CSVs in
    %   templates/ — the joint template's first row IS the DABJ
    %   Section 9 class-problem joint expressed in the table schema, so the
    %   parse is checked against the same numbers validation.dabjSection9
    %   builds in code (structural check: field mapping, not new physics).
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
        function loadsJointLibrary(testCase)
            % The template's DABJ row must reproduce the §9 joint the same
            % way validation.dabjSection9 builds it in code.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulkParsers.templatePath("joint_library_template.csv"), lib);
            testCase.assertNotEmpty(jl);

            idx = find([jl.Name] == "DABJ Sec. 9 class problem", 1);
            testCase.assertNotEmpty(idx, "DABJ template row not found");
            j = jl(idx).Joint;
            testCase.verifyClass(j, "model.Joint");

            % Library-resolved pieces
            testCase.verifyEqual(j.Bolt.NominalDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.Series, model.ThreadSeries.UNF);
            testCase.verifyEqual(j.BoltMaterial.Name, "A-286");
            testCase.verifyEqual(j.BoltRatedUltimateLoad, 15200);   % from boltSpec
            testCase.verifyEqual(j.BoltRatedYieldLoad, 11400);

            % Direct-column pieces
            testCase.verifyEqual(j.BoltCount, 4);
            testCase.verifyEqual(j.FrictionCoefficient, 0.1, "AbsTol", 1e-12);
            testCase.verifyEqual(j.LoadingPlaneFactor, 0.5, "AbsTol", 1e-12);
            testCase.verifyEqual(j.ShearPlane, model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(j.SlipMode, model.SlipMode.Joint);
            testCase.verifyEqual(j.BoltAxis, model.BoltAxis.Z);

            % Preload spec
            testCase.verifyEqual(j.PreloadSpec.Method, model.PreloadMethod.TorqueControl);
            testCase.verifyEqual(j.PreloadSpec.NominalTorque, 470);
            testCase.verifyEqual(j.PreloadSpec.TorqueTolerance, 0.042553, "AbsTol", 1e-9);
            testCase.verifyEqual(j.PreloadSpec.NutFactor, 0.15, "AbsTol", 1e-12);
            testCase.verifyEqual(j.PreloadSpec.Uncertainty, 0.25, "AbsTol", 1e-12);
            testCase.verifyEqual(j.PreloadSpec.RelaxationFraction, 0.05, "AbsTol", 1e-12);
            % ThermalRate override (12.978 = 7.21 lbf/degF x 1.8), so the
            % template's thermal preload matches the dabjSection9 in-code
            % build without needing stiffness geometry
            testCase.verifyEqual(j.PreloadSpec.ThermalRate, 12.978, "AbsTol", 1e-9);
            testCase.verifyFalse(j.PreloadSpec.SeparationCritical);

            % Flange stack: FlangeCount = 2, both 0.375-in Al 7075-T7351
            testCase.verifyEqual(numel(j.FlangeStack), 2);
            testCase.verifyEqual(j.FlangeStack(1).Thickness, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.FlangeStack(2).Material.Name, "Al 7075-T7351");
            testCase.verifyEqual(j.GripLength, 0.75, "AbsTol", 1e-12);

            % Threaded member: nut with the spec Pult as its rating
            testCase.verifyEqual(j.ThreadedMember.Type, model.ThreadedMemberType.Nut);
            testCase.verifyEqual(j.ThreadedMember.RatedUltimateLoad, 15200);

            % Temperatures (degC): 20 -/+ 25 degF expressed in degC
            testCase.verifyEqual(j.ReferenceTemperature, 20, "AbsTol", 1e-12);
            testCase.verifyEqual(j.MaxTemperature, 33.8889, "AbsTol", 1e-4);
            testCase.verifyEqual(j.MinTemperature, 6.1111, "AbsTol", 1e-4);
        end

        function loadsElements(testCase)
            el = data.loadElements( ...
                tBulkParsers.templatePath("elements_template.csv"));
            testCase.assertEqual(numel(el), 3);

            testCase.verifyEqual(el(1).ElementId, "1001");
            testCase.verifyEqual(el(1).JointName, "DABJ Sec. 9 class problem");
            testCase.verifyEqual(el(1).LoadCaseName, "Liftoff");
            testCase.verifyEqual(el(1).PatternId, "PLATE-1");
            testCase.verifyEqual(el(1).Forces.FX, 300);
            testCase.verifyEqual(el(1).Forces.FY, 400);
            testCase.verifyEqual(el(1).Forces.FZ, 1200);
            testCase.verifyEqual(el(1).ScaleFactor, 1);
            testCase.verifyFalse(el(1).Reversible);

            % Signed forces + moments + reversible flag pass through
            testCase.verifyEqual(el(2).Forces.FZ, -800);
            testCase.verifyEqual(el(2).Forces.MX, 10);
            testCase.verifyTrue(el(2).Reversible);

            % Blank optional cells fall back: MX/MY/MZ -> 0; scale reads 1.5;
            % blank pattern_id -> "" (analyzeBulk falls back to JointName)
            testCase.verifyEqual(el(3).JointName, "Example insert joint");
            testCase.verifyEqual(el(3).PatternId, "");
            testCase.verifyEqual(el(3).Forces.MX, 0);
            testCase.verifyEqual(el(3).Forces.MZ, 0);
            testCase.verifyEqual(el(3).ScaleFactor, 1.5, "AbsTol", 1e-12);
        end

        function threadEngagementDiameterFormat(testCase)
            % "1.5D" on a 3/8 bolt -> Le = 1.5 * 0.375 = 0.5625 in
            % (the template's second, insert-config row).
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulkParsers.templatePath("joint_library_template.csv"), lib);
            idx = find([jl.Name] == "Example insert joint", 1);
            testCase.assertNotEmpty(idx, "insert template row not found");
            j = jl(idx).Joint;

            testCase.verifyEqual(j.ThreadedMember.Type, model.ThreadedMemberType.Insert);
            testCase.verifyEqual(j.ThreadedMember.EngagementLength, 0.5625, "AbsTol", 1e-9);
            testCase.verifyEqual(j.ThreadedMember.Material.Name, "Al 7075-T7351");
            testCase.verifyEqual(j.ThreadedMember.RatedUltimateLoad, 2000);

            % A few schema spot-checks on the same row
            testCase.verifyEqual(j.ShearPlane, model.ShearPlaneCondition.ThreadsInShear);
            testCase.verifyEqual(j.SlipMode, model.SlipMode.Disabled);
            testCase.verifyEqual(j.BoltAxis, model.BoltAxis.X);
            testCase.verifyTrue(j.PreloadSpec.SeparationCritical);
            testCase.verifyEqual(numel(j.FlangeStack), 1);
            testCase.verifyEqual(j.FlangeStack(1).HoleDiameter, 0.397, "AbsTol", 1e-12);
            testCase.verifyEqual(j.FlangeStack(1).EdgeDistance, 0.75, "AbsTol", 1e-12);
            testCase.verifyEqual(j.HeadWasher.Thickness, 0.063, "AbsTol", 1e-12);
            testCase.verifyEqual(j.HeadWasher.OuterDiameter, 0.687, "AbsTol", 1e-12);
            % No NutWasher columns set -> model default (zero thickness)
            testCase.verifyEqual(j.NutWasher.Thickness, 0);
        end
    end
end
