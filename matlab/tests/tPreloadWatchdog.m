classdef tPreloadWatchdog < matlab.unittest.TestCase
    %TPRELOADWATCHDOG  engine.preloadWatchdog: preload-vs-allowable bands.
    %   Pure-query pins (worst-wins band ordering, NaN/never-throws
    %   tolerance) on a synthetic rated-load fixture, PLUS the DABJ Section
    %   9 fixture, which is EXPECTED to trip the PreloadNearYield band
    %   (see the class-level note below) -- that is arithmetically correct
    %   and must never be "fixed" to a clean result.
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
        function j = ratedJoint(yieldAllow, ultimateAllow)
            % Minimal joint carrying ONLY rated yield/ultimate bolt loads
            % (the "rated" path in boltTensileAllowable) -- no Bolt/Material
            % geometry needed, so the arithmetic in every test below is
            % nothing but the watchdog's own band comparisons.
            j = model.Joint( ...
                BoltRatedYieldLoad    = yieldAllow, ...
                BoltRatedUltimateLoad = ultimateAllow);
        end
    end

    methods (Test)
        function cleanBelow85Percent(testCase)
            % yield 10,000 / ultimate 15,000 (rated). PpMax = 8,000 ->
            % 8,000/10,000 = 80% of yield, BELOW the 85% band -> no warning.
            j = tPreloadWatchdog.ratedJoint(10000, 15000);
            r = engine.preloadWatchdog(j, struct("PpMax", 8000));
            testCase.verifyTrue(r.Evaluated);
            testCase.verifyEqual(r.Name, "");
            testCase.verifyEqual(r.Severity, "");
            testCase.verifyEqual(r.YieldAllowable.Basis, "rated");
            testCase.verifyEqual(r.UltimateAllowable.Basis, "rated");
        end

        function boundaryAt85PercentIsNotYetWarning(testCase)
            % Band test is STRICT (PpMax > 0.85*yield): PpMax = 8,500 is
            % EXACTLY 0.85*10,000 -- not strictly greater -- so this must
            % still read clean, proving the boundary is not off-by-one.
            j = tPreloadWatchdog.ratedJoint(10000, 15000);
            r = engine.preloadWatchdog(j, struct("PpMax", 8500));
            testCase.verifyEqual(r.Name, "");
        end

        function nearYieldWarning(testCase)
            % PpMax = 9,000 -> 90% of yield 10,000 (>85%, <100%) ->
            % PreloadNearYield, Warning severity, still well under the
            % 15,000 ultimate so Ultimate never enters it.
            j = tPreloadWatchdog.ratedJoint(10000, 15000);
            r = engine.preloadWatchdog(j, struct("PpMax", 9000));
            testCase.verifyEqual(r.Name, "PreloadNearYield");
            testCase.verifyEqual(r.Severity, "Warning");
            testCase.verifySubstring(r.Detail, "90.0%");
        end

        function exceedsYieldCritical(testCase)
            % PpMax = 10,500 -> exceeds yield (10,000) but not ultimate
            % (15,000) -> PreloadExceedsYield, Critical.
            j = tPreloadWatchdog.ratedJoint(10000, 15000);
            r = engine.preloadWatchdog(j, struct("PpMax", 10500));
            testCase.verifyEqual(r.Name, "PreloadExceedsYield");
            testCase.verifyEqual(r.Severity, "Critical");
        end

        function exceedsUltimateWinsOverYield(testCase)
            % PpMax = 16,000 exceeds BOTH yield (10,000) and ultimate
            % (15,000) -- worst wins: the Ultimate band must be reported,
            % never the Yield band, even though the yield condition is
            % also true.
            j = tPreloadWatchdog.ratedJoint(10000, 15000);
            r = engine.preloadWatchdog(j, struct("PpMax", 16000));
            testCase.verifyEqual(r.Name, "PreloadExceedsUltimate");
            testCase.verifyEqual(r.Severity, "Critical");
        end

        function notEvaluatedOnBareJoint(testCase)
            % A bare joint (no rated loads, no Bolt.TensileStressArea, no
            % BoltMaterial.Ftu/Fty) can form NEITHER the rated NOR the
            % derived allowable on either side -- boltTensileAllowable
            % reports Assessed = false for both -- so the watchdog must
            % report Evaluated = false and Name = "" (never a fabricated
            % "clean" pass).
            j = model.Joint();
            r = engine.preloadWatchdog(j, struct("PpMax", 5000));
            testCase.verifyFalse(r.UltimateAllowable.Assessed);
            testCase.verifyFalse(r.YieldAllowable.Assessed);
            testCase.verifyFalse(r.Evaluated);
            testCase.verifyEqual(r.Name, "");
            testCase.verifySubstring(r.Detail, "not evaluated");
        end

        function notEvaluatedOnNaNPpMax(testCase)
            % Real allowables assessed, but PpMax itself is NaN (e.g. an
            % upstream preload computation that could not resolve) -- both
            % bands are gated on ~isnan(PpMax), so this must degrade to
            % "not evaluated", never throw and never fabricate a pass.
            j = tPreloadWatchdog.ratedJoint(10000, 15000);
            r = engine.preloadWatchdog(j, struct("PpMax", NaN));
            testCase.verifyFalse(r.Evaluated);
            testCase.verifyEqual(r.Name, "");
            testCase.verifyTrue(isnan(r.PpMax));
        end

        function methodCitesEq1AndFlagsDerivedBands(testCase)
            % The Method string must carry PpMax's real citation (Eq. 1)
            % AND explicitly flag the 85%/100% thresholds as a derived
            % convention with no equation number -- never a bare "Eq. 1"
            % standing in for the whole check.
            j = tPreloadWatchdog.ratedJoint(10000, 15000);
            r = engine.preloadWatchdog(j, struct("PpMax", 9000));
            testCase.verifySubstring(r.Method, "Eq. 1");
            testCase.verifySubstring(r.Method, "DERIVED CONVENTION");
        end

        function dabjSection9TripsNearYieldByDesign(testCase)
            % CONSTRAINT: the DABJ Section 9 fixture is EXPECTED to trip
            % the amber PreloadNearYield band -- this is arithmetically
            % correct and must NOT be "fixed" to report clean.
            %
            % HAND-DERIVED (all inputs from validation.dabjSection9 /
            % engine.preload's own validated header numbers):
            %   PpiNom  = NominalTorque/(NutFactor*D) = 470/(0.15*0.375)
            %           = 470/0.05625 = 8,355.5556 lbf
            %   cMax    = TorqueMax/TorqueNominal = 490/470 = 1.0425532
            %   Gamma   = 0.25 -> (1+Gamma) = 1.25
            %   PpiMax  = cMax*(1+Gamma)*PpiNom
            %           = 1.0425532*1.25*8,355.5556 = 10,888.8889 lbf
            %   ThermalRate = 7.21*1.8 = 12.978 lbf/degC (exact)
            %   dT      = 25/1.8 = 13.888889 degC (Max-Ref = Ref-Min, exact)
            %   ThermalDelta = ThermalRate*dT = 12.978*(25/1.8)
            %                = 180.25 lbf (exact: 12.978*125/9 = 1622.25/9)
            %   PpMax   = PpiMax + ThermalDelta = 10,888.8889 + 180.25
            %           = 11,069.1389 lbf
            %   Rated yield (Solutions-18, BoltRatedYieldLoad) = 11,400 lbf
            %   Utilization = 11,069.1389/11,400 = 0.970977 = 97.1%
            %     -- ABOVE the 85% band (9,690 lbf) and BELOW the yield
            %        allowable itself (11,400 lbf) -> PreloadNearYield,
            %        Warning (not Critical: it has not yet EXCEEDED yield).
            %   Rated ultimate (BoltRatedUltimateLoad) = 15,200 lbf ->
            %     11,069.1389 lbf is nowhere near it (72.8%), so the
            %     Ultimate band never enters this fixture.
            c = validation.dabjSection9();
            p = engine.preload(c.Joint);
            testCase.verifyEqual(p.PpMax, 11069.1389, "AbsTol", 0.01);

            r = engine.preloadWatchdog(c.Joint, p);
            testCase.verifyTrue(r.Evaluated);
            testCase.verifyEqual(r.Name, "PreloadNearYield");
            testCase.verifyEqual(r.Severity, "Warning");
            testCase.verifyEqual(r.YieldAllowable.Value, 11400);
            testCase.verifyEqual(r.YieldAllowable.Basis, "rated");
            testCase.verifyEqual(r.UltimateAllowable.Value, 15200);
            testCase.verifyEqual(r.UltimateAllowable.Basis, "rated");
            pct = 100 * p.PpMax / 11400;
            testCase.verifyEqual(pct, 97.0977, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "97.1%");
        end
    end
end
