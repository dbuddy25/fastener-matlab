classdef tBulkParsers < matlab.unittest.TestCase
    %TBULKPARSERS  Phase 3.5b acceptance: the bulk input parsers.
    %   data.loadJointLibrary (joint-table -> model.Joint per row, library
    %   keys resolved through data.Library; NEW layout: boltSpec
    %   auto-lookup, AxialX/Y/Z bolt-direction marks, On-gated washers,
    %   Nut*/Helicoil* threaded-member columns, header-row auto-detect),
    %   data.loadElements (element + forces table -> struct array for
    %   engine.resolveForces; same header-row auto-detect as the joint
    %   reader), and data.loadSettings (global temperatures + factors). All are exercised against the shipped template CSVs in
    %   templates/ — the joint template's first row is a sample four-bolt
    %   SHCS/nut joint built from real catalog hardware (NAS1351 3/8-24,
    %   A286, Al 7075-T7351), NOT the DABJ Section 9 class-problem joint
    %   (library.json no longer ships that fixture; see
    %   validation.dabjSection9, which builds it inline). This suite checks
    %   the PARSER's field mapping against the table schema, not answer-key
    %   physics.
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
            % The template's first row uses real catalog hardware (NAS1351
            % 3/8-24, A286, Al 7075-T7351) in a DABJ-Section-9-like
            % configuration -- NOT the DABJ validation fixture, which
            % library.json no longer ships (see validation.dabjSection9,
            % which now builds that fixture's geometry inline). This test
            % checks the PARSER's field mapping, not answer-key numbers.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulkParsers.templatePath("joint_library_template.csv"), lib);
            testCase.assertNotEmpty(jl);

            idx = find([jl.Name] == "Sample four-bolt SHCS/nut joint", 1);
            testCase.assertNotEmpty(idx, "template row not found");
            j = jl(idx).Joint;
            testCase.verifyClass(j, "model.Joint");

            % Library-resolved pieces. BoltSpec is blank, but the catalog
            % now ships a boltSpec for NAS1351 3/8-24 + A286, so the
            % AUTO-LOOKUP HITS and fills the rated loads from FF-S-86F
            % Table VII (heat and corrosion resistant steel = A286).
            % This is the path data.loadJointLibrary exists to exercise:
            % a row that names only a bolt and a material still arrives
            % carrying the spec's allowables, with no BoltSpec cell.
            testCase.verifyEqual(j.Bolt.NominalDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.Series, model.ThreadSeries.UNF);
            testCase.verifyEqual(j.BoltMaterial.Name, "A286");
            testCase.verifyEqual(j.BoltRatedUltimateLoad, 14050);   % auto-lookup hit
            testCase.verifyEqual(j.BoltRatedYieldLoad,    10500);

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
            % No ThermalRate column (removed -- not an analyst-facing
            % input, see model.PreloadSpec): stays the model default 0, so
            % this row's thermal preload comes from the CTE-mismatch/
            % joint-stiffness path (TM-106943 Eq. 10) -- see tests/tBulk.m.
            testCase.verifyEqual(j.PreloadSpec.ThermalRate, 0, "AbsTol", 1e-12);
            testCase.verifyFalse(j.PreloadSpec.SeparationCritical);

            % BodyLengthInGrip / NutHeight -- added so this row's stiffness
            % actually resolves (see data.makeTemplate's sampleNutJointRow
            % for the geometry reasoning and tests/tBulk.m for the
            % Tension-Ultimate consequence).
            testCase.verifyEqual(j.BodyLengthInGrip, 0.50, "AbsTol", 1e-12);
            testCase.verifyEqual(j.ThreadedMember.EngagementLength, 0.328, "AbsTol", 1e-12);

            % Flange stack: FlangeCount = 2, both 0.375-in Al 7075-T7351
            testCase.verifyEqual(numel(j.FlangeStack), 2);
            testCase.verifyEqual(j.FlangeStack(1).Name, "Upper flange");
            testCase.verifyEqual(j.FlangeStack(1).Thickness, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.FlangeStack(2).Material.Name, "Al 7075-T7351");
            testCase.verifyEqual(j.GripLength, 0.75, "AbsTol", 1e-12);

            % Threaded member: nut, material from the NutMaterial column
            testCase.verifyEqual(j.ThreadedMember.Type, model.ThreadedMemberType.Nut);
            testCase.verifyEqual(j.ThreadedMember.Material.Name, "A286");

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

            % Row 1001 carries representative per-bolt loads (FZ 5590 -> axial,
            % FX 1560 -> shear on the bolt-axis-Z joint) so the shipped
            % template analyzes cleanly end-to-end (see tWorkbook)
            testCase.verifyEqual(el(1).ElementId, "1001");
            testCase.verifyEqual(el(1).JointName, "Sample four-bolt SHCS/nut joint");
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
            % HelicoilLengthRatio 1.5 -> ThreadedMember.EngagementRatio 1.5
            % STORED AS THE RATIO ITSELF (not multiplied into an inch
            % value here) -- engine/private/resolveEngagementLength is the
            % one place Le = EngagementRatio x Bolt.NominalDiameter gets
            % computed, at analysis time against THAT row's own bolt (see
            % data/loadJointLibrary.m). HelicoilParent* -> HostName/
            % Material, the AxialX mark, and the On-gated head washer.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulkParsers.templatePath("joint_library_template.csv"), lib);
            idx = find([jl.Name] == "Example insert joint", 1);
            testCase.assertNotEmpty(idx, "insert template row not found");
            j = jl(idx).Joint;

            testCase.verifyEqual(j.ThreadedMember.Type, model.ThreadedMemberType.Insert);
            testCase.verifyEqual(j.ThreadedMember.EngagementRatio, 1.5, "AbsTol", 1e-9);
            testCase.verifyTrue(isnan(j.ThreadedMember.EngagementLength), ...
                "HelicoilLengthRatio must land on EngagementRatio, not a computed EngagementLength");
            testCase.verifyEqual(j.ThreadedMember.HostName, "Housing");
            testCase.verifyEqual(j.ThreadedMember.Material.Name, "Al 7075-T7351");

            % No HelicoilShearArea column exists -- ShearEngagementArea is
            % not analyst-facing (NASA-STD-5020B Section 4.4.1 wants a
            % SPECIFIED insert catalogue geometry, not a typed area), so a
            % bulk-loaded Insert row always leaves it at the model default
            % (NaN); engine.marginInsert derives the NASA-STD-5020B Section
            % 4.4.1 parent-material pull-out area itself from
            % StiPitchDiameter below. HelicoilRatedLoad -> RatedUltimateLoad
            % is a manufacturer rating and stays analyst-facing.
            testCase.verifyTrue(isnan(j.ThreadedMember.ShearEngagementArea));
            testCase.verifyEqual(j.ThreadedMember.RatedUltimateLoad, 2600, "AbsTol", 1e-12);

            % StiPitchDiameter is NOT a table column -- it is auto-resolved
            % from the insert catalogue (data.Library.insertFor) by this
            % row's OWN bolt thread size (NAS1351 3/8-24 -> 0.375 in,
            % 24 tpi), matching NASM33537-3750-24's seeded
            % stiPitchDiameterMin exactly, the same way BoltSpec's
            % auto-lookup resolves rated loads above.
            testCase.verifyEqual(j.ThreadedMember.StiPitchDiameter, 0.402, "AbsTol", 1e-9);

            % BodyLengthInGrip is populated on this row too (0.15 in, see
            % data.makeTemplate's insertExampleRow), but engine.stiffness
            % defers the threaded-in frustum form unconditionally for an
            % Insert configuration, so it does not change this row's
            % analysis -- see tests/tBulk.m's class header.
            testCase.verifyEqual(j.BodyLengthInGrip, 0.15, "AbsTol", 1e-12);

            % BoltSpec is blank here too, and this row carries the same
            % NAS1351 3/8-24 + A286 pairing, so the same catalog auto-lookup
            % hit fills the rated loads (FF-S-86F Table VII).
            testCase.verifyEqual(j.BoltRatedUltimateLoad, 14050);
            testCase.verifyEqual(j.BoltRatedYieldLoad,    10500);

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
            testCase.verifyEqual(j.HeadWasher.Material.Name, "A286");
            testCase.verifyEqual(j.NutWasher.Thickness, 0);
        end

        function insertRowBlankHelicoilAreaAndLoadDefault(testCase)
            % No HelicoilShearArea column exists to omit -- the row below
            % also omits HelicoilRatedLoad, and both must land on the
            % model.ThreadedMember defaults (NaN / 0), NOT be left unset
            % from a previous row or coerced to 0/NaN the wrong way round.
            % ShearEngagementArea NaN is what lets engine.marginInsert fall
            % back to its own catalogue-geometry area (StiPitchDiameter),
            % since no analyst column can ever set it.
            lib = data.Library.load();
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'Name,Bolt,BoltMaterial,ThreadedMember,HelicoilParentMaterial', ...
                'Blank helicoil area,NAS1351 3/8-24,A286,Insert,Al 7075-T7351'});

            jl = data.loadJointLibrary(f, lib);
            testCase.assertEqual(numel(jl), 1);
            tm = jl(1).Joint.ThreadedMember;
            testCase.verifyEqual(tm.Type, model.ThreadedMemberType.Insert);
            testCase.verifyTrue(isnan(tm.ShearEngagementArea));
            testCase.verifyEqual(tm.RatedUltimateLoad, 0);
            % No HelicoilLengthRatio column on this row either -- must
            % land on the model default (NaN), same "no leftover value"
            % guarantee as ShearEngagementArea/RatedUltimateLoad above.
            testCase.verifyTrue(isnan(tm.EngagementRatio));
            testCase.verifyTrue(isnan(tm.EngagementLength));
        end

        function insertRowWithNoCatalogueEntryLeavesStiPitchDiameterNaN(testCase)
            % NAS1351 #0-80 (0.06 in, 80 tpi) is one of the two bolt sizes
            % the insert catalogue carries NO NASM33537 entry for -- no
            % helical insert is manufactured that small. lib.insertFor
            % returns [] for this thread size, which must land on the
            % model's NaN "unknown" sentinel WITHOUT loadJointLibrary
            % throwing -- a catalogue miss is a legitimate state (see
            % data.Library.insertFor / gui.FastenerApp.buildJoint), not an
            % error, and must never silently fall back to the bolt's own
            % PitchDiameter.
            lib = data.Library.load();
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'Name,Bolt,BoltMaterial,ThreadedMember,HelicoilParentMaterial', ...
                'No insert catalogue entry,NAS1351 #0-80,A286,Insert,Al 7075-T7351'});

            jl = data.loadJointLibrary(f, lib);
            testCase.assertEqual(numel(jl), 1);
            tm = jl(1).Joint.ThreadedMember;
            testCase.verifyEqual(tm.Type, model.ThreadedMemberType.Insert);
            testCase.verifyTrue(isnan(tm.StiPitchDiameter));
        end

        function headerRowAutoDetect(testCase)
            % A friendly banner row ABOVE the real header must be skipped:
            % the reader picks the row that best matches the known column
            % names. Also covers the no-Axial-mark default (BoltAxis Z) and
            % the boltSpec auto-lookup on a minimal row -- a row naming only
            % a bolt and a material, with no BoltSpec column at all, must
            % still arrive carrying the catalogue's rated loads.
            lib = data.Library.load();
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'My Joint Table (friendly names go here),,,', ...
                'Name,Bolt,BoltMaterial,SlipMode', ...
                'HDR test,NAS1351 3/8-24,A286,Ignored'});

            jl = data.loadJointLibrary(f, lib);
            testCase.assertEqual(numel(jl), 1);
            testCase.verifyEqual(jl(1).Name, "HDR test");
            testCase.verifyEqual(jl(1).Joint.SlipMode, model.SlipMode.Ignored);
            testCase.verifyEqual(jl(1).Joint.BoltAxis, model.BoltAxis.Z);   % none marked
            testCase.verifyEqual(jl(1).Joint.BoltRatedUltimateLoad, 14050); % auto-lookup
            testCase.verifyEqual(jl(1).Joint.BoltRatedYieldLoad,    10500);
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

        function elementsWithJointNameUnchanged(testCase)
            % REGRESSION GUARD for the optional-joint_name change: a file
            % that DOES supply joint_name must parse exactly as before
            % (same row shape as elementsHeaderRowAutoDetect). Expected
            % values are the CSV literals written below. The two-output
            % form must report zero skipped rows for a clean file.
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'element_id,joint_name,load_case,FX,FY,FZ', ...
                '2001,HDR test,Liftoff,100,0,250'});

            [el, info] = data.loadElements(f);
            testCase.assertEqual(numel(el), 1);
            testCase.verifyEqual(el(1).ElementId, "2001");
            testCase.verifyEqual(el(1).JointName, "HDR test");   % supplied -> kept
            testCase.verifyEqual(el(1).LoadCaseName, "Liftoff");
            testCase.verifyEqual(el(1).Forces.FX, 100);
            testCase.verifyEqual(el(1).Forces.FZ, 250);
            testCase.verifyEqual(info.SkippedRowCount, 0);
            testCase.verifyEmpty(info.SkippedRows);
        end

        function elementsWithoutJointNameColumn(testCase)
            % A real FEM force export carries element ids + forces but NO
            % joint_name column (the GUI's Element Mapping tab supplies
            % the mapping). Every data row must still parse, with
            % JointName == "" — the "caller maps" sentinel. Expected
            % values are the CSV literals written below.
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'element_id,load_case,FX,FY,FZ', ...
                '3001,Liftoff,100,0,250', ...
                '3002,Liftoff,-50,75,600'});

            el = data.loadElements(f);   % single-output form still works
            testCase.assertEqual(numel(el), 2);
            testCase.verifyEqual(el(1).ElementId, "3001");
            testCase.verifyEqual(el(1).JointName, "");    % no column -> ""
            testCase.verifyEqual(el(1).Forces.FX, 100);
            testCase.verifyEqual(el(2).ElementId, "3002");
            testCase.verifyEqual(el(2).JointName, "");
            testCase.verifyEqual(el(2).Forces.FZ, 600);
        end

        function elementsBlankJointNameKept(testCase)
            % A joint_name COLUMN with a blank CELL keeps the row too —
            % blank means "map me later", not "skip me". Expected values
            % are the CSV literals written below.
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'element_id,joint_name,FX,FY,FZ', ...
                '4001,HDR test,100,0,250', ...
                '4002,,50,0,125'});

            el = data.loadElements(f);
            testCase.assertEqual(numel(el), 2);
            testCase.verifyEqual(el(1).JointName, "HDR test");
            testCase.verifyEqual(el(2).ElementId, "4002");
            testCase.verifyEqual(el(2).JointName, "");    % blank cell -> ""
            testCase.verifyEqual(el(2).Forces.FX, 50);
        end

        function elementsSkippedRowsReported(testCase)
            % A row WITH content but WITHOUT an element_id is still
            % skipped (rows are keyed by id) but must now be REPORTED via
            % the info output, not vanish silently. Grid row numbering:
            % the header is row 1 of this CSV, so the bad row is row 3.
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'element_id,joint_name,FX,FY,FZ', ...
                '5001,HDR test,100,0,250', ...
                ',HDR test,999,0,0', ...
                '5002,HDR test,50,0,125'});

            [el, info] = data.loadElements(f);
            testCase.assertEqual(numel(el), 2);          % rows 5001 + 5002
            testCase.verifyEqual(el(1).ElementId, "5001");
            testCase.verifyEqual(el(2).ElementId, "5002");
            testCase.verifyEqual(info.SkippedRowCount, 1);
            testCase.verifyEqual(info.SkippedRows, 3);   % header row 1 + 2
        end

        function analyzeBulkBlankJointNameMessage(testCase)
            % Headless run on UNMAPPED elements (no joint_name anywhere):
            % the per-row Error must name the real problem — no
            % joint_name / no mapping — not `Joint "" not found in the
            % joint library.` Same per-row error mechanism as before (no
            % throw, margins NaN, batch continues). Library row: the
            % minimal HDR-test joint from headerRowAutoDetect.
            lib = data.Library.load();
            fj = tBulkParsers.writeTempCsv(testCase, { ...
                'Name,Bolt,BoltMaterial,SlipMode', ...
                'HDR test,NAS1351 3/8-24,A286,Ignored'});
            jl = data.loadJointLibrary(fj, lib);

            fe = tBulkParsers.writeTempCsv(testCase, { ...
                'element_id,load_case,FX,FY,FZ', ...
                '6001,Liftoff,100,0,250'});
            el = data.loadElements(fe);

            T = engine.analyzeBulk(jl, el, model.Factors());
            testCase.assertEqual(height(T), 1);
            testCase.verifySubstring(T.Error(1), "no joint_name");
            testCase.verifySubstring(T.Error(1), "Element Mapping");
            testCase.verifySubstring(T.Error(1), """6001""");   % names the element
            testCase.verifyTrue(isnan(T.WorstMargin(1)));   % row errored, no margins
        end

        function multipleAxialMarksError(testCase)
            % Marking more than one of AxialX/AxialY/AxialZ is ambiguous
            % and must error with a clear message.
            lib = data.Library.load();
            f = tBulkParsers.writeTempCsv(testCase, { ...
                'Name,Bolt,BoltMaterial,AxialX,AxialY,AxialZ', ...
                'Bad axes,NAS1351 3/8-24,A286,X,,X'});

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
