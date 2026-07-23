classdef tDabjCase < matlab.unittest.TestCase
    %TDABJCASE  Phase 2.3 acceptance: the DABJ Section 9 validation case
    %   (validation.dabjSection9) is well-formed and pins the book's
    %   expected numbers.
    %
    %   Engine-driven assertions are added here as each check is built;
    %   Phase 2.4 added preloadMatchesDABJ (engine.preload vs the book).
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
            testCase.verifyEqual(j.PreloadSpec.TorqueMin, 450);
            testCase.verifyEqual(j.PreloadSpec.TorqueMax, 490);
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
    end
end
