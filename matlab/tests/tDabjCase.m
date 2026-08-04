classdef tDabjCase < matlab.unittest.TestCase
    %TDABJCASE  Phase 2.3 acceptance: the DABJ Section 9 validation case
    %   (validation.dabjSection9) is well-formed and pins the book's
    %   expected numbers.
    %
    %   Engine-driven assertions are added here as each check is built;
    %   Phase 2.4 added preloadMatchesDABJ (engine.preload vs the book);
    %   Phase 2.5 added designLoadsMatchDABJ and tensionUltMarginMatchesDABJ;
    %   Phase 2.6 added separationMarginMatchesDABJ and boltYieldMarginMatchesDABJ;
    %   Phase 2.7 added shearUltMarginMatchesDABJ and interactionMarginMatchesDABJ;
    %   Phase 2.8 added slipMarginMatchesDABJ;
    %   Phase 2.9 added analyzeReproducesAllDABJMargins (the full solver);
    %   the slip-mode toggle added singleFastenerSlipMatches and
    %   ignoredSlipNotEvaluated (fixture pinned to SlipMode.Joint).
    %   The Expected values verified here are recorded constants from the
    %   course book, not computed results — the point is that the answer
    %   key is captured and cannot drift silently.
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
        function caseBuilds(testCase)
            c = validation.dabjSection9();
            testCase.verifyEqual(c.Name, "DABJ Section 9 class problem");
            testCase.verifyClass(c.Joint, "model.Joint");
            testCase.verifyClass(c.LoadCase, "model.LoadCase");
            testCase.verifyClass(c.Factors, "model.Factors");
            testCase.verifyClass(c.Expected, "struct");
            testCase.verifyClass(c.Tol, "struct");
        end

        function jointReflectsCase(testCase)
            c = validation.dabjSection9();
            j = c.Joint;
            testCase.verifyEqual(j.BoltCount, 4);
            testCase.verifyEqual(j.ShearPlane, model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(j.FrictionCoefficient, 0.1);
            testCase.verifyEqual(j.LoadingPlaneFactor, 0.5);
            testCase.verifyEqual(j.BoltRatedUltimateLoad, 15200);
            testCase.verifyEqual(j.BoltRatedYieldLoad, 11400);
            testCase.verifyEqual(j.PreloadSpec.Method, model.PreloadMethod.TorqueControl);
            testCase.verifyEqual(j.PreloadSpec.NutFactor, 0.15);
            testCase.verifyEqual(j.PreloadSpec.NominalTorque, 470);
            testCase.verifyEqual(j.PreloadSpec.TorqueTolerance, 20/470);
            testCase.verifyEqual(j.PreloadSpec.Uncertainty, 0.25);
            testCase.verifyFalse(j.PreloadSpec.SeparationCritical);
            % Thermal encoded as exact degF -> degC expressions
            testCase.verifyEqual(j.PreloadSpec.ThermalRate, 7.21*1.8, "AbsTol", 1e-12);
            testCase.verifyEqual(j.MaxTemperature - j.ReferenceTemperature, ...
                25/1.8, "AbsTol", 1e-12);
            testCase.verifyEqual(j.ReferenceTemperature - j.MinTemperature, ...
                25/1.8, "AbsTol", 1e-12);
            % Bolt/material geometry is built inline (not from the shared
            % library -- see validation.dabjSection9's header). Fsu/Fbru are
            % pinned directly here since they drive the shear/bearing
            % margins and no longer live in library.json to be guarded by
            % tests/tLibrary.m.
            testCase.verifyEqual(j.Bolt.NominalDiameter, 0.375, "AbsTol", 1e-12);
            % A-286 (DABJ) and Al 7075-T7351 (DABJ) book values, transcribed
            % from the now-deleted library.json "(DABJ)" material entries
            % (see tests/tLibrary.m's former dabjFixtureMaterialsKeepBookValues,
            % which pinned all six of these against the library; the fixture
            % moved inline here, so all six are guarded here instead). Ftu/Fty
            % are currently inert in the §9 computation (rated loads are
            % supplied as literals -- see the module header), but they are
            % book values and a future silent edit to them would otherwise go
            % undetected.
            testCase.verifyEqual(j.BoltMaterial.Ftu, 160000);
            testCase.verifyEqual(j.BoltMaterial.Fty, 120000);
            testCase.verifyEqual(j.BoltMaterial.Fsu, 95000);
            testCase.verifyEqual(j.FlangeStack(1).Material.Ftu, 68000);
            testCase.verifyEqual(j.FlangeStack(1).Material.Fty, 57000);
            testCase.verifyEqual(j.FlangeStack(1).Material.Fbru, 121000);
            % Full bolt geometry, transcribed exactly from the former
            % library.json fixture entry (now inline in dabjSection9.m) --
            % the answer key (worst MS -0.65) depends on these exact values.
            testCase.verifyEqual(j.Bolt.ThreadsPerInch, 24);
            testCase.verifyEqual(j.Bolt.TensileStressArea, 0.0878, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.MinorDiameter, 0.3209, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.PitchDiameter, 0.3479, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.BodyDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.HeadBearingDiameter, 0.523, "AbsTol", 1e-12);
            testCase.verifyEqual(j.Bolt.ThreadLength, 0.625, "AbsTol", 1e-12);
            % Per-bolt + joint-level limit loads (joint totals are NOT nf x per-bolt)
            testCase.verifyEqual(c.LoadCase.BoltTensileLimitLoad, 5590);
            testCase.verifyEqual(c.LoadCase.BoltShearLimitLoad, 1560);
            testCase.verifyEqual(c.LoadCase.JointTensileLimitLoad, 16090);
            testCase.verifyEqual(c.LoadCase.JointShearLimitLoad, 5690);
        end

        function expectedNumbersRecorded(testCase)
            c = validation.dabjSection9();
            e = c.Expected;
            % The six margins of the answer key (book values, recorded)
            testCase.verifyEqual(e.MS_TensionUlt,  0.69);
            testCase.verifyEqual(e.MS_Separation,  0.16);
            testCase.verifyEqual(e.MS_BoltYield,   0.63);
            testCase.verifyEqual(e.MS_ShearUlt,    3.18);
            testCase.verifyEqual(e.MS_Interaction, 0.59);
            testCase.verifyEqual(e.MS_Slip,        -0.65);
            % Published intermediates
            testCase.verifyEqual(e.PpiMax,       10890);
            testCase.verifyEqual(e.PpiMin,       7000);
            testCase.verifyEqual(e.PpMax,        11070);
            testCase.verifyEqual(e.PpMin,        6470);
            testCase.verifyEqual(e.ThermalDelta, 180);
            testCase.verifyEqual(e.Ptu,          9000);
            testCase.verifyEqual(e.Pty,          6990);
            testCase.verifyEqual(e.Psu,          2510);
            testCase.verifyEqual(e.Psep,         5590);
            testCase.verifyEqual(e.InteractionA, 1.59);
            % Tolerances for the Phase 2.4+ engine assertions
            testCase.verifyEqual(c.Tol.MarginAbsTol, 0.01);
            testCase.verifyEqual(c.Tol.LoadRelTol, 0.005);
        end

        function torqueBandDerivedFromNominal(testCase)
            % The book's "450 to 490 in-lb" band is now encoded as
            % NominalTorque = 470 + TorqueTolerance = 20/470; the dependent
            % TorqueMin/TorqueMax must reproduce the specified band.
            c = validation.dabjSection9();
            ps = c.Joint.PreloadSpec;
            testCase.verifyEqual(ps.TorqueMax, 490, "AbsTol", 1e-6);
            testCase.verifyEqual(ps.TorqueMin, 450, "AbsTol", 1e-6);
            % c-factors of NASA-STD-5020B Eq. 3/4/5: c_max = 490/470, c_min = 450/470
            testCase.verifyEqual(ps.CMax, 490/470, "AbsTol", 1e-12);
            testCase.verifyEqual(ps.CMin, 450/470, "AbsTol", 1e-12);
        end

        function preloadMatchesDABJ(testCase)
            % Phase 2.4: engine.preload reproduces the book's preloads
            % (Solutions-11..13; book values are lightly rounded, so the
            % 0.5% load tolerance absorbs e.g. 10,888.9 vs printed 10,890).
            c = validation.dabjSection9();
            p = engine.preload(c.Joint);
            testCase.verifyEqual(p.PpiMax, c.Expected.PpiMax, ...
                "RelTol", c.Tol.LoadRelTol);
            testCase.verifyEqual(p.PpiMin, c.Expected.PpiMin, ...
                "RelTol", c.Tol.LoadRelTol);
            testCase.verifyEqual(p.ThermalDelta, c.Expected.ThermalDelta, ...
                "RelTol", c.Tol.LoadRelTol);
            testCase.verifyEqual(p.PpMax, c.Expected.PpMax, ...
                "RelTol", c.Tol.LoadRelTol);
            testCase.verifyEqual(p.PpMin, c.Expected.PpMin, ...
                "RelTol", c.Tol.LoadRelTol);
        end

        function designLoadsMatchDABJ(testCase)
            % Phase 2.5: engine.designLoads reproduces the book's design
            % loads (p. 9-6; book values are rounded, e.g. 8,999.9 -> 9,000,
            % 6,987.5 -> 6,990, 2,511.6 -> 2,510 — the 0.5% tolerance covers it).
            c = validation.dabjSection9();
            d = engine.designLoads(c.LoadCase, c.Factors);
            testCase.verifyEqual(d.Ptu, c.Expected.Ptu, ...
                "RelTol", c.Tol.LoadRelTol);
            testCase.verifyEqual(d.Pty, c.Expected.Pty, ...
                "RelTol", c.Tol.LoadRelTol);
            testCase.verifyEqual(d.Psu, c.Expected.Psu, ...
                "RelTol", c.Tol.LoadRelTol);
            testCase.verifyEqual(d.Psep, c.Expected.Psep, ...
                "RelTol", c.Tol.LoadRelTol);
        end

        function tensionUltMarginMatchesDABJ(testCase)
            % Phase 2.5: the Fig. 9-9 separation-before-rupture gate passes
            % on all four conditions (Ec > Eb/3, PpMax < 0.75*Ptu-allow,
            % n <= 0.9, e/D assumed), so Eq. 6 applies:
            % MS = 15,200/9,000 - 1 = +0.69 (Solutions-16).
            c = validation.dabjSection9();
            r = engine.marginTensionUlt(c.Joint, engine.preload(c.Joint), ...
                engine.designLoads(c.LoadCase, c.Factors));
            testCase.verifyEqual(r.MS, c.Expected.MS_TensionUlt, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifyTrue(r.SeparationBeforeRupture);
            testCase.verifySubstring(r.Method, "Eq. 6");
        end

        function separationMarginMatchesDABJ(testCase)
            % Phase 2.6: min preload vs the design separation load
            % (NASA-STD-5020B Eq. 19): MS = 6,469.75/5,590 - 1 = +0.16
            % (Solutions-17; book prints 0.16, exact 0.157).
            c = validation.dabjSection9();
            p = engine.preload(c.Joint);
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginSeparation(p, d);
            testCase.verifyEqual(r.MS, c.Expected.MS_Separation, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifySubstring(r.Method, "Eq. 19");
        end

        function boltYieldMarginMatchesDABJ(testCase)
            % Phase 2.6: spec yield allowable vs the design yield load
            % (NASA-STD-5020B Eq. 15): MS = 11,400/6,987.5 - 1 = +0.63
            % (Solutions-18; book prints 0.63, exact 0.631).
            c = validation.dabjSection9();
            p = engine.preload(c.Joint);
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginTensionYield(c.Joint, p, d);
            testCase.verifyEqual(r.MS, c.Expected.MS_BoltYield, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifySubstring(r.Method, "Eq. 15");
        end

        function shearUltMarginMatchesDABJ(testCase)
            % Phase 2.7: threads NOT in the shear plane, so the allowable
            % uses the full-diameter area (NASA-STD-5020B Eq. 14):
            % MS = 95,000*(pi/4)*0.375^2 / 2,511.6 - 1
            %    = 10,492.4/2,511.6 - 1 = +3.18 (Solutions-19).
            c = validation.dabjSection9();
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginShearUlt(c.Joint, d);
            testCase.verifyEqual(r.MS, c.Expected.MS_ShearUlt, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifySubstring(r.Method, "Eq. 14");
            % B/C: Detail must now carry the governing arithmetic (used to
            % be hardcoded "" by engine.analyze) -- confirms the NaN guard
            % added alongside it does not disturb this passing margin.
            testCase.verifyNotEqual(r.Detail, "");
            testCase.verifySubstring(r.Detail, "Psu_allow");
        end

        function shearUltNaNGuardNamesMissingInput(testCase)
            % B/C: marginShearUlt had no NaN guard -- an unset Fsu, area,
            % or design shear load silently produced MS = NaN with no
            % explanation, and marginInteraction (which reuses
            % ShearAllowable) inherited that silence. Each of the three
            % inputs is knocked out in turn on the DABJ §9 fixture; each
            % must report NotEvaluated (MS NaN) with that specific input
            % named in Detail, never a crash, and must not disturb the
            % other two inputs' arithmetic.
            c = validation.dabjSection9();
            d = engine.designLoads(c.LoadCase, c.Factors);

            % Fsu unset (BoltMaterial.Fsu -> NaN)
            jNoFsu = c.Joint;
            jNoFsu.BoltMaterial.Fsu = NaN;
            rNoFsu = engine.marginShearUlt(jNoFsu, d);
            testCase.verifyTrue(isnan(rNoFsu.MS));
            testCase.verifyTrue(isnan(rNoFsu.ShearAllowable));
            testCase.verifySubstring(rNoFsu.Detail, "BoltMaterial.Fsu");

            % Shear-plane area unset (BodyInShear here -> Bolt.BodyArea
            % falls back to NominalDiameter unless BOTH NominalDiameter
            % and BodyDiameter are NaN)
            jNoArea = c.Joint;
            jNoArea.Bolt.NominalDiameter = NaN;
            jNoArea.Bolt.BodyDiameter    = NaN;
            rNoArea = engine.marginShearUlt(jNoArea, d);
            testCase.verifyTrue(isnan(rNoArea.MS));
            testCase.verifySubstring(rNoArea.Detail, "BodyArea");

            % Design shear load unset (designLoads.Psu -> NaN)
            dNoPsu = d;
            dNoPsu.Psu = NaN;
            rNoPsu = engine.marginShearUlt(c.Joint, dNoPsu);
            testCase.verifyTrue(isnan(rNoPsu.MS));
            testCase.verifySubstring(rNoPsu.Detail, "Psu");

            % None of the above disturbs the ordinary evaluation.
            rOk = engine.marginShearUlt(c.Joint, d);
            testCase.verifyEqual(rOk.MS, c.Expected.MS_ShearUlt, ...
                "AbsTol", c.Tol.MarginAbsTol);
        end

        function interactionMarginMatchesDABJ(testCase)
            % Phase 2.7 (contract updated -- see engine.marginInteraction's
            % header): NASA-STD-5020B Eq. 20/21 is a pass/fail CRITERION,
            % R <= 1, not a margin -- so this checks the ratio R, not an
            % MS. With Rt = 9,000/15,200 = 0.592099 and
            % Rs = 2,511.6/10,492.4 = 0.239373 (body in shear):
            %   R = Rt^1.5 + Rs^2.5 = 0.455535 + 0.028085 = 0.483642 (Pass)
            % The book's own solve-for-a reading (Solutions-20..21) still
            % gives a = 1.59 exactly as before -- kept as the secondary,
            % informational "a" field (NOT the reported result any more).
            c = validation.dabjSection9();
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginInteraction(c.Joint, d);
            testCase.verifyEqual(r.R, 0.483642, "AbsTol", 1e-4);
            testCase.verifyTrue(r.Pass);
            testCase.verifyEqual(r.a, c.Expected.InteractionA, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifySubstring(r.Method, "Eq. 20/21");
        end

        function shearTransferNotDeclaredReproducesTodayR(testCase)
            % NASA-STD-5020B §4.4.4 bolt-bending exemption guard.
            % NotDeclared is model.Joint's own default (unchanged fixture,
            % same as interactionMarginMatchesDABJ) -- this is the
            % REGRESSION pin: R, Pass and a must be byte-identical to that
            % test's numbers, with the exemption reported as ASSUMED, not
            % verified (mirrors tStiffness.m's
            % edgeDistanceUnknownIsAssumedNotVerified).
            c = validation.dabjSection9();
            testCase.verifyEqual(c.Joint.ShearTransferCondition, ...
                model.ShearTransferCondition.NotDeclared);
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginInteraction(c.Joint, d);
            testCase.verifyEqual(r.R, 0.483642, "AbsTol", 1e-4);
            testCase.verifyTrue(r.Pass);
            testCase.verifyEqual(r.a, c.Expected.InteractionA, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifySubstring(r.Method, "Eq. 20/21");
            testCase.verifySubstring(r.Detail, "ASSUMED");
            testCase.verifySubstring(r.Detail, "ShearTransferCondition");
            testCase.verifyFalse(contains(r.Detail, "VERIFIED"));
        end

        function shearTransferVerifiedGivesSameRWithVerifiedWording(testCase)
            % CloseToleranceOrInterference computes EXACTLY the same
            % R/Pass/a as NotDeclared (the numeric criterion never depends
            % on this property -- only the wording does) but reports the
            % §4.4.4 exemption as VERIFIED (mirrors
            % tStiffness.m's edgeDistanceVerifiedAssuresGate).
            c = validation.dabjSection9();
            c.Joint.ShearTransferCondition = ...
                model.ShearTransferCondition.CloseToleranceOrInterference;
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginInteraction(c.Joint, d);
            testCase.verifyEqual(r.R, 0.483642, "AbsTol", 1e-4);
            testCase.verifyTrue(r.Pass);
            testCase.verifyEqual(r.a, c.Expected.InteractionA, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifySubstring(r.Method, "Eq. 20/21");
            testCase.verifySubstring(r.Detail, "VERIFIED");
            testCase.verifyFalse(contains(r.Detail, "ASSUMED"));
        end

        function shearTransferClearanceOrGappedIsNotEvaluated(testCase)
            % ClearanceOrGapped -- §4.4.4's exemption does NOT apply,
            % and bolt bending is not implemented, so the criterion cannot
            % be evaluated conservatively: R = NaN, Pass = false, NO throw.
            c = validation.dabjSection9();
            c.Joint.ShearTransferCondition = ...
                model.ShearTransferCondition.ClearanceOrGapped;
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginInteraction(c.Joint, d);   % must not throw
            testCase.verifyTrue(isnan(r.R));
            testCase.verifyFalse(r.Pass);
            testCase.verifyTrue(isnan(r.a));
            testCase.verifySubstring(r.Detail, "4.4.4");
            testCase.verifySubstring(r.Detail, "ClearanceOrGapped");
            testCase.verifySubstring(r.Detail, "Not evaluated");
        end

        function shearTransferClearanceOrGappedAnalyzeCompletes(testCase)
            % A ClearanceOrGapped joint must complete a full
            % engine.analyze call -- NaN interaction R must not crash
            % analysis and must not be picked as the governing worst
            % margin (mirrors tBulk.bulkFailingInteractionVisibleButNeverGoverns
            % for the ordinary-fail case).
            c = validation.dabjSection9();
            c.Joint.ShearTransferCondition = ...
                model.ShearTransferCondition.ClearanceOrGapped;
            res = engine.analyze(c.Joint, c.LoadCase, c.Factors);   % must not throw
            resNames = [res.Margins.Name];
            m = res.Margins(find(resNames == "Interaction", 1));
            testCase.verifyTrue(isnan(m.R));
            testCase.verifyEqual(m.Status, "NotEvaluated");
            testCase.verifyNotEqual(res.GoverningCheck, "Interaction");
        end

        function threadsInShearInteractionHandDerived(testCase)
            % Threads-in-shear interaction (NASA-STD-5020B Eq. 22/23,
            % exp 2.0/1.2). DABJ §9 has no threads-in-shear worked
            % example (it is BodyInShear, Solutions-19), so this is a
            % synthetic HAND-DERIVED fixture, not a book case. The result
            % is the RATIO R (Eq. 22/23 is a pass/fail CRITERION, R <= 1,
            % not a margin -- see engine.marginInteraction's header).
            %
            % Fixture: MinorDiameter chosen so pi/4*D^2 = 0.1 in^2 exactly
            % (D = sqrt(0.4/pi) = 0.356825 in, rounded to 6 places -- the
            % rounding shows up only in the 6th significant figure of the
            % area, well inside the AbsTol below). Fsu = 90,000 psi ->
            %   Psu_allow = Fsu * MinorArea = 90,000 * pi/4*0.356825^2
            %             = 90,000 * 0.1000001 = 9,000.01 lbf
            % Ptu_allow supplied directly as a spec rating (rated path,
            % boltTensileAllowable) = 12,000 lbf, so Ftu/At are not needed.
            % Design loads (constructed directly, not via engine.designLoads
            % -- this fixture is about the interaction envelope, not the
            % FS*FF chain, which is exercised elsewhere): Ptu = 6,000 lbf,
            % Psu = 3,000 lbf.
            %   Rt = Ptu/Ptu_allow = 6,000/12,000     = 0.5
            %   Rs = Psu/Psu_allow = 3,000/9,000.01    = 0.333333 (~1/3)
            %   R  = Rt^2.0 + Rs^1.2 = 0.5^2 + 0.333333^1.2
            %      = 0.25 + 0.267580 = 0.517580 (Pass -- R <= 1)
            % (direct evaluation, no root-find, per the module header)
            %
            % Secondary "a" field for reference only (NOT the result): the
            % load-scale factor solving (a*Rt)^2.0 + (a*Rs)^1.2 = 1, i.e.
            %   g(a) = 0.25*a^2 + (a/3)^1.2 - 1 = 0
            % Newton from a0 = 1.5 (g' = 0.5*a + 0.4*(a/3)^0.2):
            %   a0 = 1.500000, g = -0.002225, g' = 1.098220 -> a1 = 1.502026
            %   a1 = 1.502026, g = +0.000001, g' = 1.099327 -> a2 = 1.502025
            % a = 1.502025 (a >= 1, consistent with R <= 1 -- see header)
            b  = model.Bolt(MinorDiameter=0.356825);
            bm = model.Material(Fsu=90000);
            j  = model.Joint(Bolt=b, BoltMaterial=bm, ...
                BoltRatedUltimateLoad=12000, ...
                ShearPlane=model.ShearPlaneCondition.ThreadsInShear);
            d = struct("Ptu", 6000, "Pty", NaN, "Psu", 3000, "Psep", NaN);
            r = engine.marginInteraction(j, d);
            testCase.verifyEqual(r.R, 0.517580, "AbsTol", 1e-4);
            testCase.verifyTrue(r.Pass);
            testCase.verifyEqual(r.a, 1.502025, "AbsTol", 1e-4);
            testCase.verifySubstring(r.Method, "Eq. 22/23");
            testCase.verifySubstring(r.Method, "threads in shear");
        end

        function interactionExponentsDifferFromBodyInShear(testCase)
            % Proves the ThreadsInShear exponents (2.0/1.2) are genuinely
            % DIFFERENT from BodyInShear's (1.5/2.5) by holding Rt AND Rs
            % FIXED across both shear-plane settings -- the same fixture as
            % threadsInShearInteractionHandDerived, but with
            % NominalDiameter ALSO set equal to MinorDiameter so that
            % BodyArea == MinorArea numerically. That isolates the
            % exponent effect: with the SAME Rt = 0.5, Rs = 0.333333 fed to
            % both exponent pairs (the area-selection difference, real for
            % an actual thread, is deliberately neutralized here and tested
            % separately in threadsInShearUsesMinorAreaForShearAllowable),
            % any difference in R can only come from (et, es).
            %
            % BodyInShear: R = Rt^1.5 + Rs^2.5 = 0.5^1.5 + 0.333333^2.5
            %                = 0.353553 + 0.064150 = 0.417703 (Pass)
            % (direct evaluation -- compare threadsInShearInteractionHandDerived's
            % R = 0.517580 for the SAME Rt, Rs)
            %
            % NASA-STD-5020B's own rationale for the swapped exponents:
            % "Tensile and shear stresses peak at the same cross section
            % when the threads are in the shear plane; when the full
            % diameter body is in the shear plane, the tensile and shear
            % stresses do not peak at the same cross section." The
            % threads-in-shear envelope is therefore the more severe one
            % for the SAME load ratios: R_thread (0.517580) > R_body
            % (0.417703) here -- MORE of the envelope is "used up" by the
            % same loads -- and the same ordering (R_thread > R_body) holds
            % for every other (Rt, Rs) pair checked by hand while deriving
            % this fixture (e.g. Rt=Rs=0.3 -> body 0.213612 vs thread
            % 0.325801; Rt=0.6/Rs=0.2 -> body 0.482647 vs thread 0.504956).
            %
            % Secondary "a" values for reference (NOT the result): body
            % a = 1.675607 vs thread a = 1.502025 (previous test) -- a >= 1
            % passes on BOTH, consistent with R <= 1 on both, and the
            % SMALLER a for threads (less headroom before the envelope)
            % agrees with the LARGER R there.
            b  = model.Bolt(NominalDiameter=0.356825, MinorDiameter=0.356825);
            bm = model.Material(Fsu=90000);
            jThread = model.Joint(Bolt=b, BoltMaterial=bm, ...
                BoltRatedUltimateLoad=12000, ...
                ShearPlane=model.ShearPlaneCondition.ThreadsInShear);
            jBody = jThread;
            jBody.ShearPlane = model.ShearPlaneCondition.BodyInShear;
            d = struct("Ptu", 6000, "Pty", NaN, "Psu", 3000, "Psep", NaN);

            rThread = engine.marginInteraction(jThread, d);
            rBody   = engine.marginInteraction(jBody, d);

            testCase.verifyEqual(rThread.R, 0.517580, "AbsTol", 1e-4);
            testCase.verifyEqual(rBody.R,   0.417703, "AbsTol", 1e-4);
            testCase.verifyGreaterThan(rThread.R, rBody.R);   % threads-in-shear is the more severe envelope
            testCase.verifyTrue(rThread.Pass);
            testCase.verifyTrue(rBody.Pass);
            testCase.verifySubstring(rBody.Method, "Eq. 20/21");
            testCase.verifySubstring(rThread.Method, "Eq. 22/23");
        end

        function threadsInShearUsesMinorAreaForShearAllowable(testCase)
            % Pins that Psu_allow inside marginInteraction (reused from
            % engine.marginShearUlt) genuinely switches area with
            % ShearPlane -- MinorArea for ThreadsInShear, BodyArea (the
            % shank) for BodyInShear -- using the REAL DABJ §9 bolt
            % geometry (NominalDiameter 0.375, MinorDiameter 0.3209,
            % BodyDiameter unset -> falls back to NominalDiameter) so the
            % two areas are genuinely different, unlike the two tests
            % above which deliberately equalized them.
            %
            % The book's own BodyInShear numbers are already validated
            % elsewhere (Solutions-19/20-21: Psu_allow = 10,492.4 lbf,
            % interactionMarginMatchesDABJ's R = 0.483642) -- this test's
            % job is the ThreadsInShear SIDE of the same joint, toggled:
            %   MinorArea  = pi/4*0.3209^2         = 0.0808778 in^2
            %   Psu_allow(threads) = 95,000*0.0808778 = 7,683.39 lbf
            %   (vs Psu_allow(body) = 95,000*pi/4*0.375^2 = 10,492.4 lbf --
            %    the minor-area allowable is smaller, as it must be: a
            %    thread root cuts less material than the full shank.)
            %   Psu (design, from designLoadsMatchDABJ) = 2,511.6 lbf
            %   MS_Shear(threads) = 7,683.39/2,511.6 - 1 = +2.059162
            %
            % Feeding the SAME toggled joint through marginInteraction
            % (Ptu_allow = 15,200 lbf rated, Ptu = 8,999.9 lbf, both
            % unchanged from the book):
            %   Rt = 8,999.9/15,200               = 0.592099
            %   Rs = 2,511.6/7,683.39              = 0.326887
            %   R  = Rt^2.0 + Rs^1.2 = 0.592099^2 + 0.326887^1.2
            %      = 0.350581 + 0.261383 = 0.611964 (Pass -- direct
            %      evaluation, no root-find)
            %
            % Secondary "a" field for reference only: solving
            % (a*Rt)^2.0 + (a*Rs)^1.2 = 1 by Newton from a0 = 1.3
            % (g' = 2*Rt*(a*Rt) + 1.2*Rs*(a*Rs)^0.2):
            %   a0 = 1.300000, g = -0.049414, g' = 1.242068 -> a1 = 1.339784
            %   a1 = 1.339784, g = +0.000595, g' = 1.271962 -> a2 = 1.339316
            % a = 1.339316
            c = validation.dabjSection9();
            jThread = c.Joint;
            jThread.ShearPlane = model.ShearPlaneCondition.ThreadsInShear;
            d = engine.designLoads(c.LoadCase, c.Factors);

            shearThread = engine.marginShearUlt(jThread, d);
            testCase.verifyEqual(shearThread.ShearAllowable, 7683.39, ...
                "AbsTol", 0.1);
            testCase.verifyEqual(shearThread.MS, 2.059162, "AbsTol", 1e-4);
            % Confirms the two areas actually differ for this real bolt
            % (unlike the equal-area fixture two tests above)
            testCase.verifyEqual(jThread.Bolt.MinorArea, 0.0808778, ...
                "AbsTol", 1e-6);
            testCase.verifyNotEqual(jThread.Bolt.MinorArea, jThread.Bolt.BodyArea);

            rThread = engine.marginInteraction(jThread, d);
            testCase.verifyEqual(rThread.R, 0.611964, "AbsTol", 1e-4);
            testCase.verifyTrue(rThread.Pass);
            testCase.verifyEqual(rThread.a, 1.339316, "AbsTol", 1e-4);
            testCase.verifySubstring(rThread.Method, "Eq. 22/23");
        end

        function slipMarginMatchesDABJ(testCase)
            % Phase 2.8: joint-level friction check (NASA-STD-5020B Eq. 84) with
            % joint totals, NOT nf x per-bolt — the fixture Joint is pinned to
            % SlipMode.Joint because the book works JOINT slip (Solutions-22..23):
            % MS = 4*0.1*6,469.75 / (1.0*(5,690 + 0.1*16,090)) - 1
            %    = 2,587.9/7,299 - 1 = -0.65 (Solutions-23) — a deliberate
            % FAILING margin; the book's joint slips at limit load.
            c = validation.dabjSection9();
            testCase.verifyEqual(c.Joint.SlipMode, model.SlipMode.Joint);
            r = engine.marginSlip(c.Joint, c.LoadCase, ...
                engine.preload(c.Joint), c.Factors);
            testCase.verifyEqual(r.MS, c.Expected.MS_Slip, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifyLessThan(r.MS, 0);
            testCase.verifySubstring(r.Method, "Eq. 84");
        end

        function singleFastenerSlipMatches(testCase)
            % Single-fastener slip (NASA-STD-5020B Eq. 86, the tool DEFAULT)
            % on the DABJ joint with PER-BOLT limit loads. HAND-DERIVED, not
            % a book value (the book only works joint slip):
            % MS = 0.1*6,469.75 / (1.0*1.0*(1,560 + 0.1*5,590)) - 1
            %    = 646.975/2,119 - 1 = -0.6947
            c = validation.dabjSection9();
            j = c.Joint;
            j.SlipMode = model.SlipMode.SingleFastener;
            r = engine.marginSlip(j, c.LoadCase, engine.preload(j), c.Factors);
            testCase.verifyEqual(r.MS, -0.6947, "AbsTol", 0.01);
            testCase.verifySubstring(r.Method, "single-fastener");
        end

        function ignoredSlipNotEvaluated(testCase)
            % SlipMode.Ignored -> MS = NaN (analyze renders NotEvaluated).
            c = validation.dabjSection9();
            j = c.Joint;
            j.SlipMode = model.SlipMode.Ignored;
            r = engine.marginSlip(j, c.LoadCase, engine.preload(j), c.Factors);
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifySubstring(r.Method, "ignored");
        end

        function analyzeReproducesAllDABJMargins(testCase)
            % Phase 2.9: ONE engine.analyze call reproduces every published
            % DABJ margin, names the governing check (the deliberate slip
            % failure), and advertises the full 15-check set (unbuilt
            % checks -> NotEvaluated).
            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            testCase.verifyClass(r, "engine.Result");
            tol = c.Tol.MarginAbsTol;
            % The six published margins, pulled from Result.Margins by name
            testCase.verifyEqual(marginMS(r, "Tension-Ultimate"), ...
                c.Expected.MS_TensionUlt, "AbsTol", tol);
            testCase.verifyEqual(marginMS(r, "Tension-Yield"), ...
                c.Expected.MS_BoltYield, "AbsTol", tol);
            testCase.verifyEqual(marginMS(r, "Shear-Ultimate"), ...
                c.Expected.MS_ShearUlt, "AbsTol", tol);
            testCase.verifyEqual(marginMS(r, "Separation"), ...
                c.Expected.MS_Separation, "AbsTol", tol);
            testCase.verifyEqual(marginMS(r, "Slip"), ...
                c.Expected.MS_Slip, "AbsTol", tol);
            % Interaction is NOT a margin (NASA-STD-5020B Eq. 20-23 is a
            % pass/fail CRITERION, R <= 1) -- its Margins row carries
            % MS = NaN by design (see engine.analyze's INTERACTION IS NOT A
            % MARGIN note) and is excluded from the WorstMargin pick below;
            % its real result (R = 0.483642, Pass) is checked directly
            % against engine.marginInteraction in interactionMarginMatchesDABJ.
            % Here, only confirm the Margins row itself reflects that: NaN
            % MS, but a real Pass Status (never hidden as "NotEvaluated").
            iaRow = r.Margins([r.Margins.Name] == "Interaction");
            testCase.verifyTrue(isnan(iaRow.MS));
            testCase.verifyEqual(iaRow.Status, "Pass");
            testCase.verifySubstring(iaRow.Detail, "0.483642");
            % Worst margin = the slip failure, and it is named as governing
            % (Interaction, excluded from this pick, could not have
            % governed here anyway -- it Passes on this fixture)
            testCase.verifyEqual(r.WorstMargin, c.Expected.MS_Slip, ...
                "AbsTol", tol);
            testCase.verifyEqual(r.GoverningCheck, "Slip");
            % Narrative carries the Fig. 8 decision (gate assured here)
            testCase.verifySubstring(r.Narrative, ...
                "Separation before rupture assured");
            % Full 15-check set, writetable-ready
            t = r.asTable();
            testCase.verifyClass(t, "table");
            testCase.verifySize(t, [15 4]);
        end
    end
end

% ---- Local helpers --------------------------------------------------------
function ms = marginMS(r, name)
%MARGINMS  Look up one margin's MS by Name from Result.Margins.
mask = [r.Margins.Name] == name;
assert(nnz(mask) == 1, "margin ""%s"" not found exactly once", name);
ms = r.Margins(mask).MS;
end
