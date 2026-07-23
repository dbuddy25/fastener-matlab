classdef tStiffness < matlab.unittest.TestCase
    %TSTIFFNESS  Phase 3.1 acceptance: engine.stiffness (30° conical
    %   frustum, through-bolt configuration) reproduces the DABJ Example
    %   8-b published stiffnesses (validation.dabjExample8b): Kb = 2.39e6,
    %   Kc = 4.73e6 lbf/in, Phi = 0.336. Insert/tapped-hole joints error
    %   (that frustum form is deferred within Phase 3.1). Phase 3.1b wiring
    %   is exercised here too: the stiffness-based thermal preload path
    %   (thermalFromStiffness) and the Eq. 10 tension rupture branch
    %   (tensionRuptureBranch) — both against HAND-DERIVED numbers, not
    %   book values.
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
            % (Eq. 8.1e-f), Phi via NASA-STD-5020B Eq. 9 — all against the
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

        function thermalFromStiffness(testCase)
            % Phase 3.1b: with no ThermalRate override, engine.preload
            % computes the thermal preload change from the joint stiffness
            % per NASA TM-106943 (Chambers) Eq. 10 —
            % Pth = (Kb·Kc/(Kb+Kc))·L·ΔT·(αj − αb).
            % HAND-DERIVED expected value (no book number): the Example 8-b
            % geometry gives Kb = 2.3892e6 and Kc = 4.7253e6 lbf/in, so
            % kSeries = 2.3892e6·4.7253e6/7.1145e6 = 1.5869e6 lbf/in. With
            % L (grip) = 0.80 in, a hot-only excursion ΔT = +50 °C, and the
            % fixture CTEs αj = 2.32e-5 (aluminum members) and
            % αb = 1.69e-5 (A-286) 1/°C:
            %   Pth = 1.5869e6 · 0.80 · 50 · (2.32e-5 − 1.69e-5) = 399.9 lbf
            % Hot-only with αj > αb means the excursion only ADDS preload:
            % the max side gains 399.9 lbf and the min side loses nothing.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.PreloadSpec = model.PreloadSpec( ...
                Method             = model.PreloadMethod.DirectPreload, ...
                NominalPreload     = 2000, ...
                Uncertainty        = 0.25, ...
                RelaxationFraction = 0.05);   % ThermalRate stays 0 -> stiffness path
            j.ReferenceTemperature = 20;
            j.MinTemperature       = 20;      % no cold excursion
            j.MaxTemperature       = 70;      % ΔT_hot = +50 °C
            p = engine.preload(j);
            testCase.verifyEqual(p.ThermalDelta, 399.9, "AbsTol", 1.0);
            % Max side: PpiMax = 1.25*2000 = 2500, plus the thermal gain
            testCase.verifyEqual(p.PpMax, 2500 + p.ThermalDelta, "AbsTol", 1e-9);
            % Min side: PpiMin = 0.75*2000 = 1500; NO thermal decrement
            % (hot-only, members grow more than the bolt), so
            % PpMin = 0.95*1500 = 1425 exactly.
            testCase.verifyEqual(p.PpMin, 1425, "AbsTol", 1e-9);
        end

        function tensionRuptureBranch(testCase)
            % Phase 3.1b: when the Fig. 8 gate fails, the ultimate-tension
            % margin switches to NASA-STD-5020B Eq. 10 —
            % P'tu = (Ptu_allow - Pp_max)/(n·phi), MS = P'tu/Ptu - 1 —
            % with phi from engine.stiffness.
            % HAND-DERIVED expected value (no book number): the Example 8-b
            % geometry gives phi = Kb/(Kb+Kc) = 2.3892e6/7.1145e6 = 0.3358
            % and the fixture n = 0.5. With Ptu_allow = 10,000 lbf and
            % PpMax = 8,000 lbf (direct preload, zero uncertainty, no
            % thermal excursion), the preload gate fails
            % (8,000 >= 0.75·10,000 = 7,500) -> rupture branch. PtL = 2,000
            % with the DABJ default factors (FSU 1.4, FFU 1.15) gives
            % Ptu = 3,220 lbf, so:
            %   P'tu = (10,000 - 8,000)/(0.5·0.3358) = 11,911 lbf
            %   MS   = 11,911/3,220 - 1 = +2.699
            c = validation.dabjExample8b();
            j = c.Joint;
            j.BoltRatedUltimateLoad = 10000;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 8000, ...
                Uncertainty    = 0);      % PpMax = 8,000 exactly
            lc  = model.LoadCase(Name = "rupture-branch check", ...
                BoltTensileLimitLoad = 2000, BoltShearLimitLoad = 0);
            fac = model.Factors();        % DABJ defaults: FSU 1.4, FFU 1.15
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            r = engine.marginTensionUlt(j, p, d);
            testCase.verifyFalse(r.SeparationBeforeRupture);
            testCase.verifySubstring(r.Method, "Eq. 10");
            testCase.verifyEqual(r.MS, 2.699, "AbsTol", 0.01);
        end
    end
end
