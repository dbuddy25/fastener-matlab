classdef tForces < matlab.unittest.TestCase
    %TFORCES  Phase 3.5a acceptance: engine.resolveForces (bolt-axis
    %   projection of a FEM element's 6-DOF force vector — single-fastener
    %   CBUSH projection, no bolt-pattern moment distribution) and
    %   engine.loadCaseFromForces (forces → model.LoadCase per-bolt
    %   PtL/PsL). All expected values are HAND-DERIVED (3-4-5 and 6-8-10
    %   triangles) — this is a geometric identity, no book example applies.
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
        function resolvesAlongZ(testCase)
            % Axis Z: Axial = FZ = 12; Shear = hypot(3,4) = 5 (3-4-5
            % triangle); no moment fields supplied -> Bending = 0.
            F = struct("FX", 3, "FY", 4, "FZ", 12);
            r = engine.resolveForces(F, model.BoltAxis.Z);
            testCase.verifyEqual(r.Axial,   12, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Shear,    5, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Bending,  0, "AbsTol", 1e-9);
        end

        function resolvesAlongX(testCase)
            % Axis X: Axial = FX = 10; Shear = hypot(6,8) = 10 (6-8-10
            % triangle).
            F = struct("FX", 10, "FY", 6, "FZ", 8);
            r = engine.resolveForces(F, model.BoltAxis.X);
            testCase.verifyEqual(r.Axial, 10, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Shear, 10, "AbsTol", 1e-9);
        end

        function momentsToBending(testCase)
            % Axis Z: Bending = hypot(MX,MY) = hypot(3,4) = 5; the torsion
            % MZ (moment ABOUT the bolt axis) is ignored — a huge MZ must
            % not change any output.
            F = struct("FX", 0, "FY", 0, "FZ", 0, ...
                       "MX", 3, "MY", 4, "MZ", 1e6);
            r = engine.resolveForces(F, model.BoltAxis.Z);
            testCase.verifyEqual(r.Axial,   0, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Shear,   0, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Bending, 5, "AbsTol", 1e-9);
        end

        function loadCaseTensionOnly(testCase)
            % Compressive axial (FZ = -500) with a 30-40-50 shear pair.
            % Non-reversible: compression doesn't load the bolt in tension
            % -> PtL = 0; shear passes through -> PsL = 50.
            F = struct("FX", 30, "FY", 40, "FZ", -500);
            lc = engine.loadCaseFromForces(F, model.BoltAxis.Z, ...
                Name = "compressive case");
            testCase.verifyEqual(lc.Name, "compressive case");
            testCase.verifyEqual(lc.BoltTensileLimitLoad,  0, "AbsTol", 1e-9);
            testCase.verifyEqual(lc.BoltShearLimitLoad,   50, "AbsTol", 1e-9);
            % Joint-level loads stay NaN (per-bolt only here)
            testCase.verifyTrue(isnan(lc.JointTensileLimitLoad));
            testCase.verifyTrue(isnan(lc.JointShearLimitLoad));

            % Reversible: the load may reverse -> PtL = |Axial| = 500.
            lcRev = engine.loadCaseFromForces(F, model.BoltAxis.Z, ...
                Reversible = true);
            testCase.verifyEqual(lcRev.BoltTensileLimitLoad, 500, "AbsTol", 1e-9);
            testCase.verifyEqual(lcRev.BoltShearLimitLoad,    50, "AbsTol", 1e-9);

            % ScaleFactor = 2 doubles both (applied BEFORE resolution).
            lc2 = engine.loadCaseFromForces(F, model.BoltAxis.Z, ...
                Reversible = true, ScaleFactor = 2);
            testCase.verifyEqual(lc2.BoltTensileLimitLoad, 1000, "AbsTol", 1e-9);
            testCase.verifyEqual(lc2.BoltShearLimitLoad,    100, "AbsTol", 1e-9);
        end

        function boltAxisDefaultsToZ(testCase)
            % Joint.BoltAxis defaults to Z, so existing fixtures are
            % unaffected.
            j = model.Joint();
            testCase.verifyEqual(j.BoltAxis, model.BoltAxis.Z);
        end
    end
end
