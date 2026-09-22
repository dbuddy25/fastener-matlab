classdef tWorkbook < matlab.unittest.TestCase
    %TWORKBOOK  engine.runWorkbook single-workbook bulk run.
    %   The streamlined flow — data.makeTemplate generates one .xlsx, the
    %   user fills the Joints/Elements/Settings sheets, engine.runWorkbook
    %   runs it — must run end to end on a fresh template with no edits
    %   (parse, resolve, analyze-or-report) without throwing.
    %
    %   The shipped example content is a representative demo joint
    %   ("Sample four-bolt SHCS/nut joint") built from real catalog
    %   hardware (NAS1351 3/8-24, A286, Al 7075-T7351) in a
    %   DABJ-Section-9-like configuration (bolt count, torque, factors) --
    %   not the DABJ validation fixture itself, which validation.dabjSection9
    %   builds inline so the answer key does not depend on library content.
    %
    %   The demo row's BoltSpec is blank, but library.json ships a
    %   boltSpec for its NAS1351 3/8-24 + A286 pairing, so the auto-lookup
    %   resolves it and BoltRatedUltimateLoad/BoltRatedYieldLoad arrive as
    %   the FF-S-86F Table VII rated pair, 14,050 / 10,500 lbf.
    %   boltTensileAllowable takes this rated basis rather than the
    %   derived At*Ftu convention (NASA-STD-5020B §4.4.2) or the Eq. 18
    %   yield estimate, which 5020B offers only when the fastener spec
    %   defines no value. Tension-Ultimate also resolves to a real number:
    %   the row carries BodyLengthInGrip = 0.50 in and NutHeight = 0.328 in
    %   (see data.makeTemplate's sampleNutJointRow), so engine.stiffness
    %   computes phi instead of erroring; the rated Ptu_allow
    %   (14,050 lbf) still puts the Fig. 8 preload gate at not-assured,
    %   so the rupture branch (NASA-STD-5020B Eq. 10) governs and evaluates
    %   to a real margin -- see the hand-derivation in
    %   workbookRunsFreshTemplateWithoutCrashing below. The same gate
    %   governs Tension-Yield (engine.marginTensionYield shares
    %   separationBeforeRuptureGate with Tension-Ultimate), so it takes
    %   Eq. 16/17 too, resolving to a negative margin (~-1.368): the
    %   rated yield allowable (10,500 lbf) is itself below PpMax
    %   (11,006.78 lbf) -- a genuinely over-torqued joint, the same fact
    %   engine.preloadWatchdog already flags Critical on this row. The
    %   published DABJ §9 answer key (worst margin -0.65, governed by Slip)
    %   is pinned separately, in code, by tests/tDabjCase.m and the
    %   dabjSection9RegressionUnchanged guards in tThreadShear.m/tBearing.m
    %   -- those use validation.dabjSection9's inline fixture, which
    %   supplies rated loads explicitly (so the fallback never triggers
    %   there) and its own complete frustum geometry.
    %
    %   Also pins the outFile safety contract: runWorkbook refuses to write
    %   results into the workbook it just read.
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
        function workbookRunsFreshTemplateWithoutCrashing(testCase)
            % Fresh template -> one runWorkbook call -> must not throw, and
            % the row for element 1001 must at least resolve its per-bolt
            % loads correctly (that happens before the margin solver runs).
            % See the class header: Tension-Yield/Interaction fall back
            % to the derived allowable and resolve to real numbers, and
            % Tension-Ultimate resolves to a real rupture-branch margin
            % too (stiffness geometry is available on this row) -- not an
            % error either way.
            f = testCase.generateWorkbook();

            T = engine.runWorkbook(f);
            testCase.verifyClass(T, "table");
            testCase.assertGreaterThan(height(T), 0);

            idx = find(T.ElementId == "1001" & ...
                       T.JointName == "Sample four-bolt SHCS/nut joint", 1);
            testCase.assertNotEmpty(idx, ...
                "template Elements row 1001 (demo joint) not found in results");

            % Force resolution happens before the margin solver runs.
            testCase.verifyEqual(T.Axial(idx), 5590, "AbsTol", 1e-9);
            testCase.verifyEqual(T.Shear(idx), 1560, "AbsTol", 1e-9);

            % The row analyzes without a per-row error.
            testCase.verifyEqual(T.Error(idx), "");

            % Same demo row (Axial 5590, Shear 1560, NAS1351 3/8-24 + A286)
            % as tBulk.m's bulkRunsTemplateJointWithoutCrashing and
            % tExport.m's runBulkEndToEnd -- makeTemplate's default
            % Settings sheet carries the same FSU/FFU/FSY/FFY (see
            % +data/makeTemplate.m), so the same hand-derivation applies.
            % TensionYield does not take Eq. 15 here: engine.marginTensionYield
            % shares the Fig. 8 gate with Tension-Ultimate (below), and that
            % gate is not assured on this row (PpMax 11,006.78 >
            % 0.75*Ptu_allow 10,537.5), so Eq. 16/17 governs instead.
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
            % Pty_allow is itself below PpMax, so this is a genuinely
            % over-torqued joint (matches engine.preloadWatchdog's Critical
            % warning on this same row), not a defect -- Eq. 15 never
            % subtracts preload, so it would mask an over-torqued joint
            % that Eq. 16/17 catches.
            expectedPtuAllow = 14050;   % FF-S-86F Tbl VII, NAS1351 3/8-24 + A286
            expectedPtyAllow = 10500;   % FF-S-86F Tbl VII rated yield (no Eq. 18)
            FSU = 1.4; FFU = 1.15; FSY = 1.25; FFY = 1.0;      % makeTemplate's default Settings sheet
            phi = 0.394005;   n = 0.5;   PpMax = 11006.78;      % from the Tension-Ultimate derivation below
            Pty = FSY * FFY * 5590;
            Pprime = (expectedPtyAllow - PpMax) / (n * phi);     % Eq. 17
            expectedTensionYield = Pprime / Pty - 1;             % Eq. 16
            testCase.verifyEqual(T.TensionYield(idx), expectedTensionYield, "AbsTol", 1e-3);
            testCase.verifyEqual(T.TensionYield(idx), -1.3682, "AbsTol", 1e-3);
            testCase.verifyLessThan(T.TensionYield(idx), 0);   % over-torqued: assert the sign plainly

            % Interaction (NASA-STD-5020B Eq. 20/21 criterion, body in
            % shear): T.InteractionR carries the real ratio R directly,
            % sourced from Result.Margins("Interaction").R -- not .MS,
            % which stays NaN by design for this row (Interaction is a
            % pass/fail criterion, R <= 1, not a margin -- see
            % engine.analyze's INTERACTION IS NOT A MARGIN note;
            % engine.analyzeBulk's header explains the resourcing).
            % Verify it both against the bulk table and directly against
            % engine.marginInteraction on the equivalent library joint,
            % same raw catalog constants as above:
            %   Ptu = 1.4*1.15*5590 = 8,999.9      Psu = 1.4*1.15*1560 = 2,511.6
            %   PsuAllow = 93,400*pi/4*0.375^2     = 10,315.71
            %   Rt = 8,999.9/14,050   = 0.640562   Rs = 2,511.6/10,315.71 = 0.243473
            %   R  = 0.640562^1.5 + 0.243473^2.5 = 0.512675 + 0.029250 = 0.541925
            %   (direct evaluation, no root-find)
            Ptu      = FSU * FFU * 5590;
            Psu      = FSU * FFU * 1560;
            PsuAllow = 93400 * (pi/4 * 0.375^2);          % A286 Fsu * BodyArea
            Rt       = Ptu / expectedPtuAllow;
            Rs       = Psu / PsuAllow;
            expectedR = Rt^1.5 + Rs^2.5;   % = 0.541925
            testCase.verifyEqual(T.InteractionR(idx), expectedR, "AbsTol", 1e-6);
            testCase.verifyEqual(T.InteractionR(idx), 0.541925, "AbsTol", 1e-4);
            % The independent cross-check must stand on the same allowable
            % the engine used, so it resolves the catalogued spec the way
            % the loader would rather than leaving the rating unset -- an
            % unrated joint here would silently derive At*Ftu and check
            % the run against a different Ptu_allow than it actually used.
            % Resolved through boltSpecFor, not hardcoded, so this stays an
            % independent check rather than a copy of the engine's output.
            lib  = data.Library.load();
            spec = lib.boltSpecFor("NAS1351 3/8-24", "A286");
            testCase.assertNotEmpty(spec, ...
                'The catalogued NAS1351 3/8-24 + A286 spec must resolve.');
            jBody = model.Joint( ...
                Bolt = lib.bolt("NAS1351 3/8-24"), ...
                BoltMaterial = lib.material("A286"), ...
                BoltRatedUltimateLoad = spec.RatedUltimateLoad, ...
                ShearPlane = model.ShearPlaneCondition.BodyInShear);
            d  = struct("Ptu", Ptu, "Pty", NaN, "Psu", Psu, "Psep", NaN);
            ia = engine.marginInteraction(jBody, d);
            testCase.verifyEqual(ia.R, expectedR, "AbsTol", 1e-6);
            testCase.verifyEqual(ia.R, 0.541925, "AbsTol", 1e-4);
            testCase.verifyTrue(ia.Pass);       % R <= 1

            % WorstMargin is the minimum across every assessed true margin
            % on this row (Separation/Bearing/NutStrength among them),
            % several of which depend on the full preload chain (Eq. 25/26)
            % and flange/nut geometry this comment does not re-derive -- not
            % independently pinnable here without risking a silent mismatch
            % against the engine's own computation. It is only known to be
            % a real number, not NaN; it is not bounded by the Interaction
            % ratio above, since Interaction is excluded from this pick
            % entirely.
            testCase.verifyFalse(isnan(T.WorstMargin(idx)));

            % Tension-Ultimate resolves (BodyLengthInGrip/NutHeight are
            % populated on this row -- see the class header). HAND-DERIVED,
            % same chain as tests/tBulk.m's bulkRunsTemplateJointWithoutCrashing
            % (identical joint, identical settings-template factors/temps,
            % identical Axial = 5590). This row's thermal preload comes from
            % engine.stiffness + TM-106943 Eq. 10, the same geometry phi
            % needs:
            %   engine.stiffness (L1 = 0.50, L2 = 0.25, grip 0.75 in, no
            %   washers, 30 deg frustum, NAS1351 3/8-24 + A286 + Al
            %   7075-T7351 catalog constants): Kb = 2,787,504 lbf/in,
            %   Kc = pi*tan(30deg)*Ec*D/(2*ln(arg)) = 4,287,285 lbf/in (the
            %   coefficient is the exact pi*tan(alpha), not a 30deg-only
            %   1.81 constant -- see engine.stiffness), phi = Kb/(Kb+Kc)
            %   = 0.394005 (full arithmetic in tBulk.m's
            %   bulkRunsTemplateJointWithoutCrashing).
            %   Thermal preload (Eq. 10): kSeries = Kb*Kc/(Kb+Kc) =
            %   1,689,213 lbf/in; alphaJ (Al 7075-T7351) = 2.32e-5, alphaB
            %   (A286) = 1.65e-5; grip 0.75 in; dThot = 13.8889 degC ->
            %   Pth = 1,689,213*0.75*13.8889*6.7e-6 = 117.89 lbf.
            %   PpMax = Ppi_max(10,888.89) + Pth(117.89) = 11,006.78 lbf
            %   -- Fig. 8 gate not assured (11,006.78 >= 0.75*14,050 =
            %   10,537.5).
            %   NASA-STD-5020B Eq. 10: P'tu = (14,050-11,006.78)/(0.5*0.394005)
            %   = 15,447.62 lbf; Ptu = FSU*FFU*5590 = 8,999.9 lbf;
            %   MS = 15,447.62/8,999.9 - 1 = 0.716421.
            %   (NutHeight also makes the nut-thread-shear mode assessable,
            %   but its ~25,100 lbf computed ultimate is well above the
            %   bolt's 14,050 lbf rated allowable, so it does not change
            %   Ptu_allow.)
            testCase.verifyEqual(T.TensionUlt(idx), 0.716421, "AbsTol", 1e-3);

            % Slip stays NotEvaluated (the nf check fails: pattern PLATE-1
            % has 2 elements against BoltCount = 4) -- not an error.
            testCase.verifyTrue(isnan(T.Slip(idx)));
            testCase.verifySubstring(T.Note(idx), "BoltCount");
        end

        function workbookWritesResults(testCase)
            % With outFile given, the results land on disk and read back
            % with the same row count (Results sheet is written first).
            f = testCase.generateWorkbook();
            out = string(tempname) + ".xlsx";
            testCase.addTeardown(@() deleteIfPresent(out));

            T = engine.runWorkbook(f, out);
            testCase.verifyTrue(isfile(out));
            T2 = readtable(out, "TextType", "string");
            testCase.verifyEqual(height(T2), height(T));
        end

        function workbookRefusesInPlaceOutput(testCase)
            % outFile == the input workbook must error (never clobber the
            % filled input sheets), leaving the workbook intact.
            f = testCase.generateWorkbook();
            testCase.verifyError(@() engine.runWorkbook(f, f), ...
                "engine:runWorkbook:outFileIsInput");
            testCase.verifyTrue(isfile(f));
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove the temp file if it exists.
if isfile(f)
    delete(f);
end
end
