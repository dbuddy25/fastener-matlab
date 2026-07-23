classdef tStiffness < matlab.unittest.TestCase
    %TSTIFFNESS  Phase 3.1a acceptance: engine.stiffness (30° conical
    %   frustum, through-bolt configuration) reproduces the DABJ Example
    %   8-b published stiffnesses (validation.dabjExample8b): Kb = 2.39e6,
    %   Kc = 4.73e6 lbf/in, Phi = 0.336. Insert/tapped-hole joints error
    %   (that frustum form is deferred within Phase 3.1).
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
        function stiffnessMatchesDABJ8b(testCase)
            % Kb via Shigley/DABJ Eq. 8.1c, Kc via the 30° frustum
            % (Eq. 8.1e-f), Phi via NASA-STD-5020A Eq. 9 — all against the
            % book's printed values (rounded to 3 sig figs; exact
            % recomputation gives 2.3892e6 / 4.7253e6 / 0.3358).
            c = validation.dabjExample8b();
            s = engine.stiffness(c.Joint);
            testCase.verifyEqual(s.Kb, c.Expected.Kb, ...
                "RelTol", c.Tol.RelTol);
            testCase.verifyEqual(s.Kc, c.Expected.Kc, ...
                "RelTol", c.Tol.RelTol);
            testCase.verifyEqual(s.Phi, c.Expected.Phi, ...
                "AbsTol", c.Tol.PhiAbsTol);
            % Traceability intermediates (p. 8-19..8-20)
            testCase.verifyEqual(s.L1, 0.70, "AbsTol", 1e-12);
            testCase.verifyEqual(s.L2, 0.24, "AbsTol", 1e-12);
            testCase.verifyEqual(s.Dc, 0.6038, "AbsTol", 5e-4);
            testCase.verifyEqual(s.Ec, 10e6, "AbsTol", 1e-6);
        end

        function threadedInDeferredErrors(testCase)
            % Insert/tapped-hole frustum form is deferred — Phase 3.1 later.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.ThreadedMember.Type = model.ThreadedMemberType.Insert;
            testCase.verifyError(@() engine.stiffness(j), ...
                "engine:stiffness:threadedInDeferred");
        end
    end
end
