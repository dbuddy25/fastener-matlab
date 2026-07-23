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
            % Bolt came from the library
            testCase.verifyEqual(j.Bolt.NominalDiameter, 0.375, "AbsTol", 1e-12);
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
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginBoltYield(c.Joint, d);
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
        end

        function interactionMarginMatchesDABJ(testCase)
            % Phase 2.7: solve (a*Rt)^1.5 + (a*Rs)^2.5 = 1 with
            % Rt = 9,000/15,200 and Rs = 2,511.6/10,492.4 (body in shear):
            % a = 1.59, MS = a - 1 = +0.59 (Solutions-20..21).
            c = validation.dabjSection9();
            d = engine.designLoads(c.LoadCase, c.Factors);
            r = engine.marginInteraction(c.Joint, d);
            testCase.verifyEqual(r.MS, c.Expected.MS_Interaction, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifyEqual(r.a, c.Expected.InteractionA, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifySubstring(r.Method, "Eq. 20/21");
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
            testCase.verifyEqual(marginMS(r, "Interaction"), ...
                c.Expected.MS_Interaction, "AbsTol", tol);
            testCase.verifyEqual(marginMS(r, "Separation"), ...
                c.Expected.MS_Separation, "AbsTol", tol);
            testCase.verifyEqual(marginMS(r, "Slip"), ...
                c.Expected.MS_Slip, "AbsTol", tol);
            % Worst margin = the slip failure, and it is named as governing
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
