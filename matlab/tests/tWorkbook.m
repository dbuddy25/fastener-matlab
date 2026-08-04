classdef tWorkbook < matlab.unittest.TestCase
    %TWORKBOOK  Step 2c acceptance: engine.runWorkbook single-workbook bulk run.
    %   The streamlined flow — data.makeTemplate generates ONE .xlsx, the
    %   user fills the Joints/Elements/Settings sheets, engine.runWorkbook
    %   runs it — must run end to end on a FRESH template with no edits
    %   (parse, resolve, analyze-or-report) without throwing.
    %
    %   The shipped example content is a representative demo joint
    %   ("Sample four-bolt SHCS/nut joint") built from REAL catalog
    %   hardware (NAS1351 3/8-24, A286, Al 7075-T7351) in a
    %   DABJ-Section-9-like configuration (bolt count, torque, factors) --
    %   NOT the DABJ validation fixture itself, which library.json no
    %   longer ships (see validation.dabjSection9, which builds that
    %   fixture's geometry inline so the answer key no longer depends on
    %   library content). It is no longer NAMED after the DABJ case either
    %   -- it used to be "DABJ Sec. 9 class problem", which was actively
    %   misleading once the hardware and derived allowables diverged from
    %   the book.
    %
    %   The demo row's BoltSpec is blank and library.json ships ZERO
    %   boltSpecs, so BoltRatedUltimateLoad/BoltRatedYieldLoad stay NaN.
    %   engine.marginTensionYield / engine.marginInteraction now FALL BACK to
    %   a derived allowable (boltTensileAllowable: Ptu_allow = At*Ftu, a
    %   derived convention per NASA-STD-5020B §4.4.2, not a numbered
    %   equation; Pty_allow via Eq. 18 applied to that ultimate) when the
    %   rating is unset, so the row no longer errors there. Tension-
    %   Ultimate ALSO resolves to a real number on this row now: it carries
    %   BodyLengthInGrip = 0.50 in and NutHeight = 0.328 in (see
    %   data.makeTemplate's sampleNutJointRow), so engine.stiffness
    %   computes phi instead of erroring; the derived Ptu_allow
    %   (14,052.8 lbf) still puts the Fig. 8 preload gate at NOT-assured,
    %   so the rupture branch (NASA-STD-5020B Eq. 10) governs and evaluates
    %   to a real margin -- see the hand-derivation in
    %   workbookRunsFreshTemplateWithoutCrashing below. The SAME gate
    %   governs Tension-Yield (engine.marginTensionYield shares
    %   separationBeforeRuptureGate with Tension-Ultimate), so it takes
    %   Eq. 16/17 too, resolving to a NEGATIVE margin (~-1.339): the
    %   derived yield allowable (10,539.6 lbf) is itself below PpMax
    %   (11,006.78 lbf) -- a genuinely over-torqued joint, the same fact
    %   engine.preloadWatchdog already flags Critical on this row. The
    %   exact published
    %   DABJ §9 answer key (worst margin -0.65, governed by Slip) is pinned
    %   separately, in code, by tests/tDabjCase.m and the
    %   dabjSection9RegressionUnchanged guards in tThreadShear.m/tBearing.m
    %   -- those use validation.dabjSection9's inline fixture, which
    %   supplies rated loads explicitly (so the fallback never triggers
    %   there) AND its own complete frustum geometry.
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
            % See the class header: Tension-Yield/Interaction now fall back
            % to the derived allowable and resolve to real numbers, and
            % Tension-Ultimate now resolves to a real rupture-branch margin
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

            % No more per-row error: the row now analyzes.
            testCase.verifyEqual(T.Error(idx), "");

            % Same demo row (Axial 5590, Shear 1560, NAS1351 3/8-24 + A286)
            % as tBulk.m's bulkRunsTemplateJointWithoutCrashing and
            % tExport.m's runBulkEndToEnd -- makeTemplate's default
            % Settings sheet carries the same FSU/FFU/FSY/FFY (see
            % +data/makeTemplate.m), so the same hand-derivation applies.
            % TensionYield does NOT take Eq. 15 here: engine.marginTensionYield
            % shares the Fig. 8 gate with Tension-Ultimate (below), and that
            % gate is NOT assured on this row (PpMax 11,006.78 >
            % 0.75*Ptu_allow 10,539.6), so Eq. 16/17 governs instead.
            % HAND-DERIVED, longhand (phi = 0.394005, PpMax = 11,006.78,
            % n = 0.5 -- the same stiffness/preload chain the
            % Tension-Ultimate derivation below works out in full):
            %   Ptu_allow = At*Ftu = 0.08783*160,000 = 14,052.8
            %   Pty_allow = (Fty/Ftu)*Ptu_allow = 0.75*14,052.8 = 10,539.6 (Eq. 18)
            %   P'ty = (Pty_allow - PpMax)/(n*phi)
            %        = (10,539.6 - 11,006.78)/(0.5*0.394005) = -2,371.44 (Eq. 17)
            %   Pty  = FSY*FFY*5590 = 1.25*1*5590 = 6,987.5 lbf
            %   MS   = P'ty/Pty - 1 = -2,371.44/6,987.5 - 1 = -1.3394    (Eq. 16)
            % Pty_allow is itself below PpMax, so this is a genuinely
            % over-torqued joint (matches engine.preloadWatchdog's Critical
            % warning on this same row), not a defect -- Eq. 15 never
            % subtracts preload, so it previously masked this.
            expectedPtuAllow = 0.08783 * 160000;               % At*Ftu, NAS1351 3/8-24 + A286
            expectedPtyAllow = (120000/160000) * expectedPtuAllow;  % Eq. 18
            FSU = 1.4; FFU = 1.15; FSY = 1.25; FFY = 1.0;      % makeTemplate's default Settings sheet
            phi = 0.394005;   n = 0.5;   PpMax = 11006.78;      % from the Tension-Ultimate derivation below
            Pty = FSY * FFY * 5590;
            Pprime = (expectedPtyAllow - PpMax) / (n * phi);     % Eq. 17
            expectedTensionYield = Pprime / Pty - 1;             % Eq. 16
            testCase.verifyEqual(T.TensionYield(idx), expectedTensionYield, "AbsTol", 1e-3);
            testCase.verifyEqual(T.TensionYield(idx), -1.3394, "AbsTol", 1e-3);
            testCase.verifyLessThan(T.TensionYield(idx), 0);   % over-torqued: assert the sign plainly

            % Interaction (NASA-STD-5020B Eq. 20/21 criterion, body in
            % shear): T.InteractionR (renamed from "Interaction") now
            % carries the real ratio R directly, sourced from
            % Result.Margins("Interaction").R -- NOT .MS, which stays NaN
            % by design for this row (Interaction is a pass/fail CRITERION,
            % R <= 1, not a margin -- see engine.analyze's INTERACTION IS
            % NOT A MARGIN note; engine.analyzeBulk's header explains the
            % rename/resourcing). Verify it BOTH against the bulk table AND
            % directly against engine.marginInteraction on the equivalent
            % library joint, same raw catalog constants as above:
            %   Ptu = 1.4*1.15*5590 = 8,999.9      Psu = 1.4*1.15*1560 = 2,511.6
            %   PsuAllow = 93,400*pi/4*0.375^2     = 10,315.71
            %   Rt = 8,999.9/14,052.8 = 0.640435   Rs = 2,511.6/10,315.71 = 0.243473
            %   R  = 0.640435^1.5 + 0.243473^2.5 = 0.512614 + 0.029158 = 0.541772
            %   (direct evaluation, no root-find)
            Ptu      = FSU * FFU * 5590;
            Psu      = FSU * FFU * 1560;
            PsuAllow = 93400 * (pi/4 * 0.375^2);          % A286 Fsu * BodyArea
            Rt       = Ptu / expectedPtuAllow;
            Rs       = Psu / PsuAllow;
            expectedR = Rt^1.5 + Rs^2.5;   % = 0.541772
            testCase.verifyEqual(T.InteractionR(idx), expectedR, "AbsTol", 1e-6);
            testCase.verifyEqual(T.InteractionR(idx), 0.541772, "AbsTol", 1e-4);
            lib  = data.Library.load();
            jBody = model.Joint( ...
                Bolt = lib.bolt("NAS1351 3/8-24"), ...
                BoltMaterial = lib.material("A286"), ...
                ShearPlane = model.ShearPlaneCondition.BodyInShear);
            d  = struct("Ptu", Ptu, "Pty", NaN, "Psu", Psu, "Psep", NaN);
            ia = engine.marginInteraction(jBody, d);
            testCase.verifyEqual(ia.R, expectedR, "AbsTol", 1e-6);
            testCase.verifyEqual(ia.R, 0.541772, "AbsTol", 1e-4);
            testCase.verifyTrue(ia.Pass);       % R <= 1

            % WorstMargin is the minimum across every ASSESSED true margin
            % on this row (Separation/Bearing/NutStrength among them),
            % several of which depend on the full preload chain (Eq. 25/26)
            % and flange/nut geometry this comment does not re-derive -- not
            % independently pinnable here without risking a silent mismatch
            % against the engine's own computation. It is only known to be
            % a real number, not NaN; it is NOT bounded by the Interaction
            % ratio above (Interaction is excluded from this pick entirely
            % now, so no such inequality holds any more).
            testCase.verifyFalse(isnan(T.WorstMargin(idx)));

            % Tension-Ultimate now resolves (BodyLengthInGrip/NutHeight are
            % populated on this row -- see the class header). HAND-DERIVED,
            % same chain as tests/tBulk.m's bulkRunsTemplateJointWithoutCrashing
            % (identical joint, identical settings-template factors/temps,
            % identical Axial = 5590). ThermalRate is no longer an
            % analyst-facing column, so this row's thermal preload comes from
            % engine.stiffness + TM-106943 Eq. 10, the SAME geometry phi
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
            %   (DOWN from the old ThermalRate=12.978 override's 11,069.14)
            %   -- Fig. 8 gate NOT assured (11,006.78 >= 0.75*14,052.8 =
            %   10,539.6).
            %   NASA-STD-5020B Eq. 10: P'tu = (14,052.8-11,006.78)/(0.5*0.394005)
            %   = 15,461.83 lbf; Ptu = FSU*FFU*5590 = 8,999.9 lbf;
            %   MS = 15,461.83/8,999.9 - 1 = 0.718000.
            %   (NutHeight also makes the nut-thread-shear mode assessable,
            %   but its ~25,100 lbf computed ultimate is well above the
            %   14,052.8 lbf bolt-derived allowable, so it does not change
            %   Ptu_allow.)
            testCase.verifyEqual(T.TensionUlt(idx), 0.718000, "AbsTol", 1e-3);

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
