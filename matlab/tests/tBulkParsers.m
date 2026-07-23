classdef tBulkParsers < matlab.unittest.TestCase
    %TBULKPARSERS  Phase 3.5b acceptance: the bulk input parsers.
    %   data.loadJointLibrary (joint-table -> model.Joint per row, library
    %   keys resolved through data.Library; NEW layout: boltSpec
    %   auto-lookup, AxialX/Y/Z bolt-direction marks, On-gated washers,
    %   Nut*/Helicoil* threaded-member columns, header-row auto-detect),
    %   data.loadElements (element + forces table -> struct array for
    %   engine.resolveForces; same header-row auto-detect as the joint
    %   reader), and data.loadSettings (global temperatures + factors). All are exercised against the shipped template CSVs in
    %   templates/ — the joint template's first row IS the DABJ Section 9
    %   class-problem joint expressed in the table schema, so the parse is
    %   checked against the same numbers validation.dabjSection9 builds in
    %   code (structural check: field mapping, not new physics).
    %
    %   Temperatures are GLOBAL: the joint table carries none, so parsed
    %   joints keep the model default 20 degC; NominalTempC/HotTempC/
    %   ColdTempC come from the settings file and are applied by
    %   engine.runBulk.
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

        function f = writeTempCsv(testCase, lines)
            %WRITETEMPCSV  Write a throwaway CSV; deleted on teardown.
            f = string(tempname) + ".csv";
            fid = fopen(f, "w");
            fprintf(fid, "%s\n", lines{:});
            fclose(fid);
            testCase.addTeardown(@() deleteIfPresent(f));
        end
    end

    methods (Test)
        function loadsJointLibrary(testCase)
            % The template's DABJ row must reproduce the §9 joint the same
            % way validation.dabjSection9 builds it in code (temperatures
            % excepted — those are global settings now).
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulkParsers.templatePath("joint_library_template.csv"), lib);
            testCase.assertNotEmpty(jl);

            idx = find([jl.Name] == "DABJ Sec. 9 class problem", 1);
            testCase.assertNotEmpty(idx, "DABJ template row not found");
            j = jl(idx).Joint;
            testCase.verifyClass(j, "model.Joint");

            % Library-resolved pieces; the rated loads come from the
            % boltSpec AUTO-LOOKUP (the BoltSpec cell is blank — the
            % library's "3/8 A-286 160ksi" entry matches Bolt+BoltMaterial)
            testCase.verifyEqual(j.Bolt.NominalDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.Series, model.ThreadSeries.UNF);
            testCase.verifyEqual(j.BoltMaterial.Name, "A-286");
            testCase.verifyEqual(j.BoltRatedUltimateLoad, 15200);   % auto-lookup
            testCase.verifyEqual(j.BoltRatedYieldLoad, 11400);

            % Direct-column pieces
            testCase.verifyEqual(j.BoltCount, 4);
            testCase.verifyEqual(j.FrictionCoefficient, 0.1, "AbsTol", 1e-12);
            testCase.verifyEqual(j.LoadingPlaneFactor, 0.5, "AbsTol", 1e-12);
            testCase.verifyEqual(j.ShearPlane, model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(j.SlipMode, model.SlipMode.Joint);
            testCase.verifyEqual(j.BoltAxis, model.BoltAxis.Z);   % AxialZ marked "X"
            testCase.verifyEqual(j.FrustumAngle, 30);             % blank -> default

            % Preload spec (NominalTorque/PreloadLoss column names)
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
            testCase.verifyEqual(j.FlangeStack(1).Name, "Upper flange");
            testCase.verifyEqual(j.FlangeStack(1).Thickness, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.FlangeStack(2).Material.Name, "Al 7075-T7351");
            testCase.verifyEqual(j.GripLength, 0.75, "AbsTol", 1e-12);

            % Threaded member: nut, material from the NutMaterial column
            testCase.verifyEqual(j.ThreadedMember.Type, model.ThreadedMemberType.Nut);
            testCase.verifyEqual(j.ThreadedMember.Material.Name, "A-286");

            % Washer gates FALSE -> model default (no washer)
            testCase.verifyEqual(j.HeadWasher.Thickness, 0);
            testCase.verifyEqual(j.NutWasher.Thickness, 0);

            % No temperature columns: joints keep the model default 20 degC
            % (engine.runBulk applies the settings temps before analysis)
            testCase.verifyEqual(j.ReferenceTemperature, 20);
            testCase.verifyEqual(j.MaxTemperature, 20);
            testCase.verifyEqual(j.MinTemperature, 20);
        end

        function loadsElements(testCase)
            el = data.loadElements( ...
                tBulkParsers.templatePath("elements_template.csv"));
            testCase.assertEqual(numel(el), 3);

            % Row 1001 carries the DABJ §9 per-bolt limit loads (FZ 5590 ->
            % PtL, FX 1560 -> PsL on the bolt-axis-Z joint) so the shipped
            % template is self-validating end-to-end (see tWorkbook)
            testCase.verifyEqual(el(1).ElementId, "1001");
            testCase.verifyEqual(el(1).JointName, "DABJ Sec. 9 class problem");
            testCase.verifyEqual(el(1).LoadCaseName, "Liftoff");
            testCase.verifyEqual(el(1).PatternId, "PLATE-1");
            testCase.verifyEqual(el(1).Forces.FX, 1560);
            testCase.verifyEqual(el(1).Forces.FY, 0);
            testCase.verifyEqual(el(1).Forces.FZ, 5590);
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

        function loadsSettings(testCase)
            % The settings template carries the §9 global temperatures and
            % the DABJ factors — the same Factors validation.dabjSection9
            % builds in code.
            s = data.loadSettings( ...
                tBulkParsers.templatePath("settings_template.csv"));
            c = validation.dabjSection9();

            testCase.verifyEqual(s.NominalTempC, 20, "AbsTol", 1e-12);
            testCase.verifyEqual(s.HotTempC, 33.8889, "AbsTol", 1e-4);
            testCase.verifyEqual(s.ColdTempC, 6.1111, "AbsTol", 1e-4);

            testCase.verifyClass(s.Factors, "model.Factors");
            for f = ["FSU", "FSY", "FSSep", "FSSlip", "FFU", "FFY", "FFSep", "FFSlip"]
                testCase.verifyEqual(s.Factors.(f), c.Factors.(f), ...
                    "AbsTol", 1e-12, "Factor " + f);
            end
        end

        function insertRowMapsHelicoilColumns(testCase)
            % The template's second row exercises the insert configuration:
            % HelicoilLengthRatio 1.5 on a 3/8 bolt -> Le = 0.5625 in,
            % HelicoilParent* -> HostName/Material, the explicit BoltSpec
            % override, the AxialX mark, and the On-gated head washer.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulkParsers.templatePath("joint_library_template.csv"), lib);
            idx = find([jl.Name] == "Example insert joint", 1);
            testCase.assertNotEmpty(idx, "insert template row not found");
            j = jl(idx).Joint;

            testCase.verifyEqual(j.ThreadedMember.Type, model.ThreadedMemberType.Insert);
            testCase.verifyEqual(j.ThreadedMember.EngagementLength, 0.5625, "AbsTol", 1e-9);
            testCase.verifyEqual(j.ThreadedMember.HostName, "Housing");
            testCase.verifyEqual(j.ThreadedMember.Material.Name, "Al 7075-T7351");

            % Explicit BoltSpec cell (matches what auto-lookup would find,
            % but exercises the override path)
            testCase.verifyEqual(j.BoltRatedUltimateLoad, 15200);
            testCase.verifyEqual(j.BoltRatedYieldLoad, 11400);

            % A few schema spot-checks on the same row
            testCase.verifyEqual(j.ShearPlane, model.ShearPlaneCondition.ThreadsInShear);
            testCase.verifyEqual(j.SlipMode, model.SlipMode.Ignored);
            testCase.verifyEqual(j.BoltAxis, model.BoltAxis.X);   % AxialX TRUE
            testCase.verifyEqual(j.FrustumAngle, 30);
            testCase.verifyEqual(numel(j.FlangeStack), 1);
            testCase.verifyEqual(j.FlangeStack(1).Name, "Bracket flange");
            testCase.verifyEqual(j.FlangeStack(1).HoleDiameter, 0.397, "AbsTol", 1e-12);
            testCase.verifyEqual(j.FlangeStack(1).EdgeDistance, 0.75, "AbsTol", 1e-12);
            testCase.verifyTrue(j.FlangeStack(1).CheckShearTearout);

            % HeadWasherOn TRUE -> washer built from the Material/OD/ID/
            % Thickness columns; NutWasherOn FALSE -> model default
            testCase.verifyEqual(j.HeadWasher.Thickness, 0.063, "AbsTol", 1e-12);
            testCase.verifyEqual(j.HeadWasher.OuterDiameter, 0.687, "AbsTol", 1e-12);
            testCase.verifyEqual(j.HeadWasher.InnerDiameter, 0.391, "AbsTol", 1e-12);
            testCase.verifyEqual(j.HeadWasher.Material.Name, "A-286");
            testCase.verifyEqual(j.NutWasher.Thickness, 0);
        end

        function headerRowAutoDetect(testCase)
            % A friendly banner row ABOVE the real header must be skipped:
            % the reader picks the row that best matches the known column
            % names. Also covers the no-Axial-mark default (BoltAxis Z) and
            % the boltSpec auto-lookup on a minimal row.
            lib = data.Library.load();
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'My Joint Table (friendly names go here),,,', ...
                'Name,Bolt,BoltMaterial,SlipMode', ...
                'HDR test,3/8-24 UNF,A-286,Ignored'});

            jl = data.loadJointLibrary(f, lib);
            testCase.assertEqual(numel(jl), 1);
            testCase.verifyEqual(jl(1).Name, "HDR test");
            testCase.verifyEqual(jl(1).Joint.SlipMode, model.SlipMode.Ignored);
            testCase.verifyEqual(jl(1).Joint.BoltAxis, model.BoltAxis.Z);   % none marked
            testCase.verifyEqual(jl(1).Joint.BoltRatedUltimateLoad, 15200); % auto-lookup
        end

        function elementsHeaderRowAutoDetect(testCase)
            % Same tolerance for the ELEMENTS reader: a friendly banner row
            % ABOVE the element headers must be skipped by the header-row
            % auto-detect (mirrors headerRowAutoDetect for the joint
            % reader). Also covers absent optional columns -> defaults.
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'My Element Forces (friendly names go here),,,,,', ...
                'element_id,joint_name,load_case,FX,FY,FZ', ...
                '2001,HDR test,Liftoff,100,0,250'});

            el = data.loadElements(f);
            testCase.assertEqual(numel(el), 1);
            testCase.verifyEqual(el(1).ElementId, "2001");
            testCase.verifyEqual(el(1).JointName, "HDR test");
            testCase.verifyEqual(el(1).LoadCaseName, "Liftoff");
            testCase.verifyEqual(el(1).PatternId, "");    % absent -> ""
            testCase.verifyEqual(el(1).Forces.FX, 100);
            testCase.verifyEqual(el(1).Forces.FY, 0);
            testCase.verifyEqual(el(1).Forces.FZ, 250);
            testCase.verifyEqual(el(1).Forces.MX, 0);     % absent -> 0
            testCase.verifyEqual(el(1).ScaleFactor, 1);   % absent -> 1
            testCase.verifyFalse(el(1).Reversible);       % absent -> false
        end

        function multipleAxialMarksError(testCase)
            % Marking more than one of AxialX/AxialY/AxialZ is ambiguous
            % and must error with a clear message.
            lib = data.Library.load();
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'Name,Bolt,BoltMaterial,AxialX,AxialY,AxialZ', ...
                'Bad axes,3/8-24 UNF,A-286,X,,X'});

            testCase.verifyError( ...
                @() data.loadJointLibrary(f, lib), ...
                "data:loadJointLibrary:multipleAxes");
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove the temp CSV if it exists.
if isfile(f)
    delete(f);
end
end
