classdef tBoltAllowable < matlab.unittest.TestCase
    %TBOLTALLOWABLE  Bolt ultimate/yield allowable rated-or-derived fallback.
    %   Covers the private helper engine.private.boltTensileAllowable —
    %   exercised only through its public callers (MATLAB package-private
    %   visibility rules), matching how memberTensileUltAllowable and
    %   separationBeforeRuptureGate are already tested elsewhere in this
    %   suite:
    %       engine.systemTensileAllowable  (bolt-tension mode)
    %       engine.marginTensionUlt        (via the Fig. 8 gate)
    %       engine.marginTensionYield
    %       engine.marginInteraction       (bolt's OWN allowable, not the
    %                                      system minimum)
    %
    %   PRECEDENCE under test: the spec rating (joint.BoltRatedUltimateLoad
    %   / BoltRatedYieldLoad) wins when set; the DERIVED convention
    %   Ptu_allow = At*Ftu (NASA-STD-5020B §4.4.2, not a numbered equation)
    %   is used only when the rating is unset; yield always goes through
    %   NASA-STD-5020B Eq. 18 — Pty_allow = (Fty/Ftu)*Ptu_allow — applied to
    %   whichever ultimate allowable is ACTUALLY IN USE (rated or derived).
    %
    %   Every scenario uses the SAME bolt/material geometry (At = 0.0878,
    %   Ftu = 160,000, Fty = 120,000 — the DABJ Example 8-b 3/8-24 A-286
    %   fixture's own numbers) so the arithmetic is hand-checkable and
    %   consistent across tests:
    %       derived Ptu_allow = At*Ftu = 0.0878*160,000 = 14,048 lbf
    %       derived Pty_allow (Eq. 18 on the derived ultimate)
    %           = (120,000/160,000)*14,048 = 10,536 lbf (= At*Fty here,
    %             because the ultimate in use is itself At*Ftu — see
    %             mixedBasisYieldUsesRatedUltimateNotAtFty for the case
    %             where it must NOT coincide)
    %
    %   The joint carries a Nut ThreadedMember with no rating/engagement
    %   length, so the internal-thread member mode never assesses — every
    %   scenario below isolates the BOLT'S OWN allowable resolution.
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
        function ratedOnlyUsesSpecRatingEverywhere(testCase)
            % Both ratings set -> every site reports Basis "rated", the
            % rated numbers exactly, and Note/Detail names "spec-rated".
            j  = tBoltAllowable.baseJoint(15200, 11400);
            lc = model.LoadCase(Name="rated-only", ...
                BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
            fac = model.Factors();   % FSU 1.4, FFU 1.15, FSY 1.25, FFY 1.0
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            Ptu = fac.FSU * fac.FFU * 1000;   % 1610
            Pty = fac.FSY * fac.FFY * 1000;   % 1250

            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 15200, "AbsTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "bolt tension");
            boltRow = s.Modes([s.Modes.Name] == "bolt tension");
            testCase.verifySubstring(boltRow.Note, "spec-rated bolt Ptu-allow");

            tu = engine.marginTensionUlt(j, p, d);
            testCase.verifyEqual(tu.MS, 15200/Ptu - 1, "AbsTol", 1e-9);
            testCase.verifySubstring(tu.Decision, "spec-rated bolt Ptu-allow");

            ty = engine.marginTensionYield(j, p, d);
            testCase.verifyEqual(ty.MS, 11400/Pty - 1, "AbsTol", 1e-9);
            testCase.verifySubstring(ty.Detail, "spec-rated bolt Pty-allow");

            % PsL = 0 -> Rs = 0 -> R = Rt^1.5 (BodyInShear tension exponent;
            % 0^2.5 shear term drops out) = (1610/15200)^1.5 = 0.034473.
            % (The OLD solve-for-a reading gave a = Ptu_allow/Ptu exactly
            % when Rs = 0, for any et -- (a*Rt)^et = 1 => a*Rt = 1 -- but R
            % itself is Rt^et, a different number; see marginInteraction.m.)
            ia = engine.marginInteraction(j, d);
            testCase.verifyEqual(ia.R, (Ptu/15200)^1.5, "AbsTol", 1e-9);
            testCase.verifyEqual(ia.R, 0.034473, "AbsTol", 1e-5);
            testCase.verifyTrue(ia.Pass);
            testCase.verifyEqual(ia.a, 15200/Ptu, "AbsTol", 1e-9);   % secondary field unchanged
            testCase.verifySubstring(ia.Detail, "spec-rated bolt Ptu-allow");
        end

        function derivedOnlyUsesAtFtuAndEq18(testCase)
            % Neither rating set -> every site falls back to the derived
            % Ptu_allow = At*Ftu, and yield to Eq. 18 applied to it (which,
            % on this fixture, coincides with At*Fty because the ultimate
            % in use IS At*Ftu).
            j  = tBoltAllowable.baseJoint(NaN, NaN);
            lc = model.LoadCase(Name="derived-only", ...
                BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            Ptu = fac.FSU * fac.FFU * 1000;             % 1610
            Pty = fac.FSY * fac.FFY * 1000;              % 1250
            expectedPtuAllow = 0.0878 * 160000;          % 14,048
            expectedPtyAllow = (120000/160000) * expectedPtuAllow;  % 10,536

            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, expectedPtuAllow, "AbsTol", 1e-6);
            testCase.verifyEqual(s.GoverningMode, "bolt tension");
            boltRow = s.Modes([s.Modes.Name] == "bolt tension");
            testCase.verifySubstring(boltRow.Note, "derived Ptu_allow");

            tu = engine.marginTensionUlt(j, p, d);
            testCase.verifyEqual(tu.MS, expectedPtuAllow/Ptu - 1, "AbsTol", 1e-6);
            testCase.verifySubstring(tu.Decision, "derived Ptu_allow");

            ty = engine.marginTensionYield(j, p, d);
            testCase.verifyEqual(ty.MS, expectedPtyAllow/Pty - 1, "AbsTol", 1e-6);
            testCase.verifySubstring(ty.Detail, "NASA-STD-5020B Eq. 18");
            testCase.verifySubstring(ty.Detail, "derived Ptu_allow");

            % PsL = 0 -> Rs = 0 -> R = Rt^1.5 = (1610/14,048)^1.5 = 0.038799
            ia = engine.marginInteraction(j, d);
            testCase.verifyEqual(ia.R, (Ptu/expectedPtuAllow)^1.5, "AbsTol", 1e-9);
            testCase.verifyEqual(ia.R, 0.038799, "AbsTol", 1e-5);
            testCase.verifyTrue(ia.Pass);
            testCase.verifyEqual(ia.a, expectedPtuAllow/Ptu, "AbsTol", 1e-6);   % secondary field
            testCase.verifySubstring(ia.Detail, "derived Ptu_allow");
        end

        function mixedBasisYieldUsesRatedUltimateNotAtFty(testCase)
            % Rated ultimate + NO rated yield: Eq. 18 must divide by the
            % RATED ultimate (20,000, deliberately chosen far from
            % At*Ftu = 14,048) -- NOT At*Fty. If the implementation ever
            % regressed to At*Fty, this would silently give 10,536 instead
            % of the correct 15,000.
            j  = tBoltAllowable.baseJoint(20000, NaN);
            lc = model.LoadCase(Name="mixed-basis", ...
                BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            Ptu = fac.FSU * fac.FFU * 1000;   % 1610
            Pty = fac.FSY * fac.FFY * 1000;   % 1250

            expectedPtyAllow    = (120000/160000) * 20000;   % 15,000 -- CORRECT
            wrongAtFtyAllow     = 0.0878 * 120000;            % 10,536 -- must NOT appear

            tu = engine.marginTensionUlt(j, p, d);
            testCase.verifyEqual(tu.MS, 20000/Ptu - 1, "AbsTol", 1e-9);
            testCase.verifySubstring(tu.Decision, "spec-rated bolt Ptu-allow");

            ty = engine.marginTensionYield(j, p, d);
            testCase.verifyEqual(ty.MS, expectedPtyAllow/Pty - 1, "AbsTol", 1e-9);
            testCase.verifyNotEqual(round(ty.MS, 4), round(wrongAtFtyAllow/Pty - 1, 4));
            testCase.verifySubstring(ty.Detail, "NASA-STD-5020B Eq. 18");
            testCase.verifySubstring(ty.Detail, "using the rated Ptu_allow");

            % Uses the ultimate, not yield -- PsL = 0 -> Rs = 0 -> R = Rt^1.5
            % = (1610/20,000)^1.5 = 0.022840.
            ia = engine.marginInteraction(j, d);
            testCase.verifyEqual(ia.R, (Ptu/20000)^1.5, "AbsTol", 1e-9);
            testCase.verifyEqual(ia.R, 0.022840, "AbsTol", 1e-5);
            testCase.verifyTrue(ia.Pass);
            testCase.verifyEqual(ia.a, 20000/Ptu, "AbsTol", 1e-9);
        end

        function unavailableAtNaNIsNotEvaluatedNotThrown(testCase)
            % No rating AND no TensileStressArea (At) -> the derived
            % fallback can't be formed either -> NotEvaluated everywhere,
            % never a throw. The nut mode also can't be assessed on this
            % fixture, so systemTensileAllowable reports NO assessable mode
            % at all.
            j  = tBoltAllowable.baseJoint(NaN, NaN);
            j.Bolt.TensileStressArea = NaN;
            lc = model.LoadCase(Name="unavailable-At", ...
                BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);

            s = engine.systemTensileAllowable(j);
            testCase.verifyTrue(isnan(s.PtuAllow));
            testCase.verifyFalse(s.Complete);

            tu = engine.marginTensionUlt(j, p, d);
            testCase.verifyTrue(isnan(tu.MS));
            testCase.verifySubstring(tu.Decision, "not assessed");

            ty = engine.marginTensionYield(j, p, d);
            testCase.verifyTrue(isnan(ty.MS));
            testCase.verifySubstring(ty.Detail, "TensileStressArea");

            ia = engine.marginInteraction(j, d);
            testCase.verifyTrue(isnan(ia.R));
            testCase.verifyTrue(isnan(ia.a));
            testCase.verifyFalse(ia.Pass);   % NaN R -> Pass defaults false; isnan(R) is the real signal
            testCase.verifySubstring(ia.Detail, "TensileStressArea");
        end

        function unavailableFtuNaNIsNotEvaluatedNotThrown(testCase)
            % No rating AND no BoltMaterial.Ftu -> same graceful outcome,
            % naming Ftu specifically rather than At.
            j  = tBoltAllowable.baseJoint(NaN, NaN);
            j.BoltMaterial.Ftu = NaN;
            lc = model.LoadCase(Name="unavailable-Ftu", ...
                BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);

            ty = engine.marginTensionYield(j, p, d);
            testCase.verifyTrue(isnan(ty.MS));
            testCase.verifySubstring(ty.Detail, "BoltMaterial.Ftu");

            ia = engine.marginInteraction(j, d);
            testCase.verifyTrue(isnan(ia.R));
            testCase.verifySubstring(ia.Detail, "BoltMaterial.Ftu");
        end

        function unavailableFtyNaNLeavesYieldNotEvaluatedButUltimateFine(testCase)
            % Ultimate IS assessable (rated), but Fty is NaN so Eq. 18
            % cannot form the yield fallback -- ultimate margins succeed
            % normally while yield alone reports NotEvaluated, reason
            % naming Fty specifically.
            j  = tBoltAllowable.baseJoint(15200, NaN);
            j.BoltMaterial.Fty = NaN;
            lc = model.LoadCase(Name="unavailable-Fty", ...
                BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);

            tu = engine.marginTensionUlt(j, p, d);
            testCase.verifyFalse(isnan(tu.MS));

            ty = engine.marginTensionYield(j, p, d);
            testCase.verifyTrue(isnan(ty.MS));
            testCase.verifySubstring(ty.Detail, "BoltMaterial.Fty");
        end
    end

    methods (Static, Access = private)
        function j = baseJoint(boltRatedUlt, boltRatedYld)
            %BASEJOINT  A minimal joint isolating the bolt's own tensile
            %   allowable resolution. Bolt/material geometry matches DABJ
            %   Example 8-b's 3/8-24 A-286 bolt (At = 0.0878, Ftu = 160,000,
            %   Fty = 120,000, Fsu = 95,000) so numbers are hand-checkable
            %   against that fixture's own published values. FlangeStack
            %   material (Ec = 10e6) and LoadingPlaneFactor (0.5) keep the
            %   Fig. 8 gate ASSURED with a small direct preload (1,000 lbf,
            %   zero uncertainty -> PpMax = 1,000 exactly, well under
            %   0.75*Ptu_allow for every rating/derived value used in this
            %   file), so engine.marginTensionUlt never needs stiffness
            %   geometry. ShearPlane = BodyInShear so engine.marginInteraction
            %   does not hit the (unrelated, deliberately unvalidated)
            %   ThreadsInShear path. The Nut ThreadedMember carries no
            %   rating/engagement length, so the internal-thread mode never
            %   assesses -- every scenario isolates the bolt's own
            %   allowable.
            b = model.Bolt(Designation="3/8-24 UNF (bolt-allowable test)", ...
                NominalDiameter=0.375, Series=model.ThreadSeries.UNF, ...
                ThreadsPerInch=24, TensileStressArea=0.0878, ...
                MinorDiameter=0.3209, PitchDiameter=0.3479, BodyDiameter=0.375);
            bm = model.Material(Name="A-286 (bolt-allowable test)", ...
                Ftu=160000, Fty=120000, Fsu=95000, E=29e6);
            fm = model.Material(Name="Aluminum (bolt-allowable test)", ...
                Ftu=68000, Fty=57000, Fsu=39000, E=10e6);
            j = model.Joint(Name="bolt-allowable test joint", ...
                Bolt=b, BoltMaterial=bm, ...
                FlangeStack=[model.FlangeLayer(Material=fm, Thickness=0.5)], ...
                ThreadedMember=model.ThreadedMember( ...
                    Type=model.ThreadedMemberType.Nut, Material=bm), ...
                BoltRatedUltimateLoad=boltRatedUlt, ...
                BoltRatedYieldLoad=boltRatedYld, ...
                LoadingPlaneFactor=0.5, ...
                ShearPlane=model.ShearPlaneCondition.BodyInShear, ...
                PreloadSpec=model.PreloadSpec( ...
                    Method=model.PreloadMethod.DirectPreload, ...
                    NominalPreload=1000, Uncertainty=0));
        end
    end
end
