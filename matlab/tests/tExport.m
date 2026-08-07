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
    %   See tests/tBulk.m's class header for the full story: the shipped
    %   template's demo joint ("Sample four-bolt SHCS/nut joint" -- it used
    %   to be misleadingly named "DABJ Sec. 9 class problem") has no
    %   BoltSpec, but library.json now ships one for its NAS1351 3/8-24 +
    %   A286 pairing, so the auto-lookup fills BoltRatedUltimateLoad /
    %   BoltRatedYieldLoad with the FF-S-86F Table VII rated pair,
    %   14,050 / 10,500 lbf, and boltTensileAllowable takes its "rated"
    %   basis rather than the derived At*Ftu / Eq. 18 fallback.
    %   Tension-Ultimate ALSO resolves
    %   to a real number: the row carries BodyLengthInGrip/NutHeight (see
    %   data.makeTemplate's sampleNutJointRow), so engine.stiffness
    %   computes phi instead of erroring, and the Fig. 8 rupture branch
    %   (NASA-STD-5020B Eq. 10) evaluates to a real margin — see
    %   runBulkEndToEnd's hand-derivation below. The SAME Fig. 8 gate (NOT
    %   assured) governs Tension-Yield too (engine.marginTensionYield shares
    %   separationBeforeRuptureGate with Tension-Ultimate), so it takes
    %   Eq. 16/17 and resolves NEGATIVE (~-1.339): the derived yield
    %   allowable is itself below PpMax on this row -- a genuinely
    %   over-torqued joint, the same fact engine.preloadWatchdog already
    %   flags Critical on this row (see the Warnings check below).
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
            % out — one call, no crash, and the documented column set.
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
                "Separation", "Slip", "SepBeforeRupture", "InteractionR", ...
                "TappedParent", ...
                "WorstMargin", "GoverningCheck", "Error", "Note", "Warnings"];
            testCase.verifyEqual( ...
                string(T.Properties.VariableNames), expectedVars);

            % Row 1 is the template's first demo element: it resolves its
            % per-bolt loads (Axial/Shear happen before the margin solver)
            % and now analyzes cleanly (see the class header), including a
            % real Tension-Ultimate (stiffness geometry is available on
            % this row) -- not an error.
            testCase.verifyEqual(T.ElementId(1), "1001");
            testCase.verifyEqual(T.JointName(1), "Sample four-bolt SHCS/nut joint");
            testCase.verifyEqual(T.Axial(1), 5590, "AbsTol", 1e-9);
            testCase.verifyEqual(T.Shear(1), 1560, "AbsTol", 1e-9);
            testCase.verifyEqual(T.Error(1), "");

            % Same demo row (Axial 5590, Shear 1560, NAS1351 3/8-24 + A286)
            % pinned in tBulk.m's bulkRunsTemplateJointWithoutCrashing and
            % tWorkbook.m's workbookRunsFreshTemplateWithoutCrashing --
            % settings_template.csv carries FSU=1.4/FFU=1.15/FSY=1.25/FFY=1.
            % TensionYield does NOT take Eq. 15: engine.marginTensionYield
            % shares the Fig. 8 gate with Tension-Ultimate (below), and
            % that gate is NOT assured on this row (PpMax 11,006.78 >
            % 0.75*Ptu_allow 10,537.5), so Eq. 16/17 governs.
            % HAND-DERIVED, longhand (phi = 0.394005, PpMax = 11,006.78,
            % n = 0.5 -- the same stiffness/preload chain the
            % Tension-Ultimate derivation below works out in full):
            %   Ptu_allow = 14,050  (FF-S-86F Table VII rated tensile load,
            %   Pty_allow = 10,500   rated yield load -- both taken as-is;
            %                        Eq. 18 does not apply when the
            %                        fastener spec defines the value)
            %   P'ty = (Pty_allow - PpMax)/(n*phi)
            %        = (10,500 - 11,006.78)/(0.5*0.394005) = -2,572.45 (Eq. 17)
            %   Pty  = FSY*FFY*5590 = 1.25*1*5590 = 6,987.5 lbf
            %   MS   = P'ty/Pty - 1 = -2,572.45/6,987.5 - 1 = -1.3682    (Eq. 16)
            % Pty_allow is itself below PpMax -- a genuinely over-torqued
            % joint (matches engine.preloadWatchdog's Critical warning
            % below), not a defect; Eq. 15 never subtracts preload, so it
            % previously masked this.
            expectedPtuAllow = 14050;   % FF-S-86F Tbl VII, NAS1351 3/8-24 + A286
            expectedPtyAllow = 10500;   % FF-S-86F Tbl VII rated yield (no Eq. 18)
            phi = 0.394005;   n = 0.5;   PpMax = 11006.78;      % from the Tension-Ultimate derivation below
            Pty = 1.25 * 1.0 * 5590;                           % FSY*FFY*Axial
            Pprime = (expectedPtyAllow - PpMax) / (n * phi);     % Eq. 17
            expectedTensionYield = Pprime / Pty - 1;             % Eq. 16
            testCase.verifyEqual(T.TensionYield(1), expectedTensionYield, "AbsTol", 1e-3);
            testCase.verifyEqual(T.TensionYield(1), -1.3682, "AbsTol", 1e-3);
            testCase.verifyLessThan(T.TensionYield(1), 0);   % over-torqued: assert the sign plainly

            % Tension-Ultimate resolves now: the row carries BodyLengthInGrip
            % = 0.50 in and NutHeight = 0.328 in (data.makeTemplate's
            % sampleNutJointRow), so engine.stiffness computes phi instead
            % of erroring. Same hand-derivation as tests/tBulk.m's
            % bulkRunsTemplateJointWithoutCrashing (identical joint,
            % identical settings-template factors/temps, identical
            % Axial = 5590). ThermalRate is no longer an analyst-facing
            % column, so this row's thermal preload comes from
            % engine.stiffness + TM-106943 Eq. 10, the SAME geometry phi
            % needs:
            %   engine.stiffness (L1 = 0.50, L2 = 0.25, grip 0.75 in, no
            %   washers, 30 deg frustum): Kb = 2,787,504 lbf/in,
            %   Kc = pi*tan(30deg)*Ec*D/(2*ln(arg)) = 4,287,285 lbf/in
            %   (coefficient is the exact pi*tan(alpha), not a 30deg-only
            %   1.81 constant), phi = 0.394005 (full arithmetic in tBulk.m).
            %   Thermal preload (Eq. 10): kSeries = 1,689,213 lbf/in;
            %   alphaJ (Al 7075-T7351) = 2.32e-5, alphaB (A286) = 1.65e-5;
            %   grip 0.75 in; dThot = 13.8889 degC -> Pth = 117.89 lbf.
            %   PpMax = Ppi_max(10,888.89) + Pth(117.89) = 11,006.78 lbf
            %   -- Fig. 8 gate NOT assured (11,006.78 >= 0.75*14,050 =
            %   10,537.5).
            %   NASA-STD-5020B Eq. 10: P'tu = (14,050-11,006.78)/(0.5*0.394005)
            %   = 15,447.62 lbf; Ptu = 1.4*1.15*5590 = 8,999.9 lbf;
            %   MS = 15,447.62/8,999.9 - 1 = 0.716421.
            testCase.verifyEqual(T.TensionUlt(1), 0.716421, "AbsTol", 1e-3);

            % WorstMargin is the minimum across every assessed check on this
            % row; several (Separation, Bearing, NutStrength) depend on the
            % full preload/geometry chain and are not re-derived here (see
            % tBulk.m's bulkRunsTemplateJointWithoutCrashing for the same
            % caveat), so it is not independently pinned to an exact value.
            % What IS checkable: it can never exceed the smaller of the
            % TensionYield and TensionUlt margins reported on this row.
            % Compare against the REPORTED values, not the hand-derived
            % expectedTensionYield above -- that one is built from rounded
            % intermediates (phi = 0.394005, PpMax = 11,006.78), and Eq. 17
            % divides by n*phi, which carries the rounding out to ~2e-7.
            % That is well inside the 1e-3 tolerance the derivation is
            % checked at, but far outside the 1e-9 this identity needs:
            % WorstMargin IS one of these table values, so it holds exactly.
            testCase.verifyFalse(isnan(T.WorstMargin(1)));
            testCase.verifyLessThanOrEqual(T.WorstMargin(1), ...
                min(T.TensionYield(1), T.TensionUlt(1)) + 1e-9);

            % Trailing Warnings column (engine.preloadWatchdog via
            % engine.analyze): this row's PpMax (~11,006.78, derived above)
            % is compared against the bolt's YIELD allowable -- which on
            % THIS row is the FF-S-86F Table VII RATED value, 10,500. That
            % is a DIFFERENT number from the Fig. 8 gate threshold above
            % (0.75*14,050 = 10,537.5) even though both once evaluated to
            % 10,539.6: the old derived yield allowable was Eq. 18's
            % (Fty/Ftu)*Ptu_allow, and this bolt's Fty/Ftu = 120,000/160,000
            % happens to equal the gate's own 0.75 -- a coincidence the
            % catalogued pair now breaks, which is exactly why the two were
            % never the same check.
            % HAND-DERIVED:
            %   PpMax/YieldAllow = 11,006.78/10,500 = 1.048265 = 104.8%
            %   -- ABOVE 100% of yield -> PreloadExceedsYield, Critical
            %   (NOT merely near-yield: this demo joint's torqued preload
            %   genuinely exceeds its bolt's rated yield allowable).
            %   Bolt length is NOT flagged: this row's Bolt (NAS1351
            %   3/8-24, from the library, not this template row) carries
            %   no Length value (library bolts default Length to NaN --
            %   see tests/tBoltLength.m), so boltLengthCheck's Shortfall
            %   stays NaN ("not evaluated"), never > 0.
            testCase.verifySubstring(T.Warnings(1), "Critical:");
            testCase.verifySubstring(T.Warnings(1), ...
                "EXCEEDS the bolt yield tensile allowable");
            testCase.verifySubstring(T.Warnings(1), "derived basis");
            testCase.verifySubstring(T.Warnings(1), "Bolt may permanently deform");
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
            % must match too. Row 1's demo joint analyzes cleanly on every
            % one of these calls identically (see the class header), which
            % is itself the cross-check: three call forms, the same outcome.
            jf = tExport.templatePath("joint_library_template.csv");
            ef = tExport.templatePath("elements_template.csv");

            Tdef = engine.runBulk(jf, ef);                    % omitted
            Temp = engine.runBulk(jf, ef, "");                % empty
            Tfac = engine.runBulk(jf, ef, model.Factors());   % legacy slot

            testCase.verifyClass(Tdef, "table");
            testCase.assertEqual(height(Tdef), height(Temp));
            testCase.assertEqual(height(Tdef), height(Tfac));
            % Same (clean) outcome from all three calls -- the point of
            % this test is that default / empty / explicit model.Factors()
            % produce IDENTICAL results, so cross-check across all THREE
            % tables (not just two), on columns that actually demonstrate
            % agreement.
            testCase.verifyEqual(Tdef.Error(1), Temp.Error(1));
            testCase.verifyEqual(Tdef.Error(1), Tfac.Error(1));
            testCase.verifyEqual(Tdef.Error(1), "");

            % TensionUlt(1) now resolves to a REAL number on all three
            % calls (the row carries BodyLengthInGrip/NutHeight -- see the
            % class header) -- cross-check all three agree, then pin the
            % value by hand. NOTE this scenario differs from
            % tests/tBulk.m's bulkRunsTemplateJointWithoutCrashing /
            % runBulkEndToEnd above: no settings file is given here, so the
            % joint keeps the model.Joint DEFAULT temperatures (Reference =
            % Max = Min = 20 degC) instead of the settings template's Hot/
            % Cold excursion -- NO thermal excursion (dThot = dTcold = 0),
            % so engine.preload's thermal term is zero regardless of
            % ThermalRate (which no longer exists as an analyst override
            % anyway), and PpMax is just the torque-control PpiMax with no
            % thermal add-on. HAND-DERIVED, longhand:
            %   PpiNom = NominalTorque/(NutFactor*D) = 470/(0.15*0.375)
            %          = 8,355.556; cMax = 1.042553, Gamma = 0.25
            %   PpiMax = cMax*(1+Gamma)*PpiNom = 1.302319*8,355.556
            %          = 10,888.89 lbf = PpMax (no thermal term here)
            %   Ptu_allow = 14,050 (FF-S-86F Table VII, unchanged) -- Fig. 8
            %   gate still NOT assured: 10,888.89 >= 0.75*14,050 = 10,537.5.
            %   phi = 0.394005 (pure geometry -- Kc = pi*tan(30deg)*Ec*D/
            %   (2*ln(arg)), the exact pi*tan(alpha) coefficient, not a
            %   30deg-only 1.81 constant; same as every other use of this
            %   row -- see tBulk.m for the full Kb/Kc arithmetic).
            %   NASA-STD-5020B Eq. 10: P'tu = (14,050-10,888.89)/(0.5*0.394005)
            %   = 3,161.11/0.197003 = 16,046.04 lbf
            %   Ptu = FSU*FFU*5590 = 1.4*1.15*5590 = 8,999.9 lbf (same
            %   FSU/FFU as the settings template -- model.Factors()'s
            %   built-in defaults happen to equal it)
            %   MS = 16,046.04/8,999.9 - 1 = 0.782913
            testCase.verifyEqual(Tdef.TensionUlt(1), Temp.TensionUlt(1), "AbsTol", 1e-6);
            testCase.verifyEqual(Tdef.TensionUlt(1), Tfac.TensionUlt(1), "AbsTol", 1e-6);
            testCase.verifyEqual(Tdef.TensionUlt(1), 0.782913, "AbsTol", 1e-3);

            % WorstMargin is a real number on this row -- cross-check it
            % across all three tables to prove the three call forms
            % actually agree numerically, not just on NaN-ness.
            testCase.verifyEqual(Tdef.WorstMargin(1), Temp.WorstMargin(1), ...
                "AbsTol", 1e-9);
            testCase.verifyEqual(Tdef.WorstMargin(1), Tfac.WorstMargin(1), ...
                "AbsTol", 1e-9);
            testCase.verifyFalse(isnan(Tdef.WorstMargin(1)));

            testCase.verifyEqual(Tdef.GoverningCheck(1), Temp.GoverningCheck(1));
            testCase.verifyEqual(Tdef.GoverningCheck(1), Tfac.GoverningCheck(1));

            % Trailing Warnings column: cross-check all three call forms
            % agree, then pin by hand. PpMax here is the no-thermal PpiMax
            % = 10,888.89 (derived above) vs the SAME rated yield
            % allowable as runBulkEndToEnd (10,500 -- this row's
            % allowables don't depend on the settings/temperature path).
            % HAND-DERIVED: 10,888.89/10,500 = 1.037037 = 103.7% of
            % yield -- still ABOVE 100% -> PreloadExceedsYield, Critical
            % (a smaller overshoot than runBulkEndToEnd's 104.8% since
            % there is no thermal add-on here, but still an overshoot).
            testCase.verifyEqual(Tdef.Warnings(1), Temp.Warnings(1));
            testCase.verifyEqual(Tdef.Warnings(1), Tfac.Warnings(1));
            testCase.verifySubstring(Tdef.Warnings(1), "Critical:");
            testCase.verifySubstring(Tdef.Warnings(1), ...
                "EXCEEDS the bolt yield tensile allowable");
        end

        function runBulkRefusesJointFileAsOutput(testCase)
            % Passing jointFile back as outFile must error BEFORE any file
            % is touched (report.exportResults deletes an existing outFile
            % first, so this would otherwise destroy the joint library
            % input) -- mirrors tWorkbook.m's workbookRefusesInPlaceOutput
            % via the same shared engine.private.samePath guard.
            jf = tExport.templatePath("joint_library_template.csv");
            ef = tExport.templatePath("elements_template.csv");
            sf = tExport.templatePath("settings_template.csv");

            testCase.verifyError(@() engine.runBulk(jf, ef, sf, jf), ...
                "engine:runBulk:outFileIsInput");
            testCase.verifyTrue(isfile(jf));   % never touched
        end

        function runBulkRefusesElementsFileAsOutput(testCase)
            % Same guard, elementsFile slot.
            jf = tExport.templatePath("joint_library_template.csv");
            ef = tExport.templatePath("elements_template.csv");
            sf = tExport.templatePath("settings_template.csv");

            testCase.verifyError(@() engine.runBulk(jf, ef, sf, ef), ...
                "engine:runBulk:outFileIsInput");
            testCase.verifyTrue(isfile(ef));
        end

        function runBulkRefusesSettingsFileAsOutput(testCase)
            % Same guard, settingsFile slot -- the one runBulk uniquely
            % takes as a THIRD input path (runWorkbook has only one input
            % file), and the one this fix actually adds coverage for.
            jf = tExport.templatePath("joint_library_template.csv");
            ef = tExport.templatePath("elements_template.csv");
            sf = tExport.templatePath("settings_template.csv");

            testCase.verifyError(@() engine.runBulk(jf, ef, sf, sf), ...
                "engine:runBulk:outFileIsInput");
            testCase.verifyTrue(isfile(sf));
        end

        function runBulkDistinctOutFileStillWorks(testCase)
            % The guard must not block a normal, distinct output path.
            jf = tExport.templatePath("joint_library_template.csv");
            ef = tExport.templatePath("elements_template.csv");
            sf = tExport.templatePath("settings_template.csv");
            out = string(tempname) + ".xlsx";
            testCase.addTeardown(@() deleteIfPresent(out));

            T = engine.runBulk(jf, ef, sf, out);
            testCase.verifyTrue(isfile(out));
            testCase.assertGreaterThan(height(T), 0);
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
