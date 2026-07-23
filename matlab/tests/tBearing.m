classdef tBearing < matlab.unittest.TestCase
    %TBEARING  Phase 3.2 acceptance: the three member-strength checks —
    %   engine.marginBearing (NASA TM-106943 Eq. 72-74), engine.marginShearTearout
    %   (Eq. 69-71), and engine.marginBearingUnderHead (Eq. 75 area + Eq. 74
    %   MS form) — all required by NASA-STD-5020B §4.4.2, which prints no
    %   member-strength equations of its own.
    %
    %   Validation strategy (VALIDATION.md rows 4-6): the bearing ALLOWABLE
    %   is validated against DABJ Example 5-b (the only public worked member
    %   example — it compares allowables, not margins); the tear-out and
    %   under-head checks have no public worked example and are pinned with
    %   HAND-DERIVED arithmetic, documented inline. The DABJ §9 answer key
    %   is re-run through analyze() to prove Phase 3.2 does not disturb it.
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
        function bearingAllowableMatchesDABJ5b(testCase)
            % DABJ Example 5-b (bearing): 3/8 bolt in a 0.320-in aluminum
            % fitting with Fbru = 123,000 psi. The book compares ALLOWABLES
            % (it works no margin), printing ~14,800 lbf; exact arithmetic
            % per NASA TM-106943 Eq. 72 is
            %   Pbr = Fbru*D*t = 123000*0.375*0.320 = 14,760 lbf
            % so the allowable is asserted at 0.5% and the MS at a
            % HAND-DERIVED value. FSY = 1.0 here so the ULTIMATE criterion
            % governs (with the default FSY = 1.25 the yield allowable
            % 94,000*0.12 = 11,280 lbf would govern the min-MS pick and
            % surface in BearingAllowable instead):
            %   MS_u = 14760/(1.15*1.4*2000) - 1 = 14760/3220 - 1 = +3.584
            %   MS_y = 11280/(1.0*1.0*2000) - 1  = +4.640  (not governing)
            fm = model.Material(Name="Aluminum (Example 5-b)", ...
                Ftu=68000, Fty=57000, Fsu=95000, Fbru=123000, Fbry=94000, ...
                E=10.3e6);
            b = model.Bolt(Designation="3/8 (Example 5-b)", ...
                NominalDiameter=0.375, ThreadsPerInch=24, ...
                TensileStressArea=0.0878, MinorDiameter=0.3209);
            j = model.Joint(Name="DABJ Ex 5-b bearing joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=fm, Thickness=0.320));
            lc  = model.LoadCase(Name="Ex 5-b shear", ...
                BoltTensileLimitLoad=0, BoltShearLimitLoad=2000);
            fac = model.Factors(FSY=1.0, FFY=1.0);   % ultimate governs (see above)
            r = engine.marginBearing(j, lc, fac);
            testCase.verifyEqual(r.BearingAllowable, 14760, "RelTol", 0.005);
            testCase.verifyEqual(r.MS, 3.584, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "ultimate");
            testCase.verifySubstring(r.Method, "Eq. 72-74");
        end

        function shearTearoutHandDerived(testCase)
            % HAND-DERIVED pin (no public worked example): NASA TM-106943
            % Eq. 69-71 on a single layer, t = 0.320 in, e = 0.75 in,
            % D = 0.375 in, Fsu = 41,000 psi:
            %   As   = 2*0.320*(0.75 - 0.1875) = 0.64*0.5625 = 0.36 in^2
            %   Pult = 41000*0.36 = 14,760 lbf
            % With V = 2,000 lbf and the DABJ default factors
            % (FFU = 1.15, FSU = 1.4):
            %   MS = 14760/(1.15*1.4*2000) - 1 = 14760/3220 - 1 = +3.584
            % e/D = 0.75/0.375 = 2.0 >= 1.5, so no validity caution.
            fm = model.Material(Name="Tear-out member", Fsu=41000);
            b  = model.Bolt(Designation="3/8", NominalDiameter=0.375, ...
                ThreadsPerInch=24, TensileStressArea=0.0878);
            j  = model.Joint(Name="tear-out pin joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=fm, Thickness=0.320, ...
                                              EdgeDistance=0.75));
            lc  = model.LoadCase(Name="tear-out shear", ...
                BoltTensileLimitLoad=0, BoltShearLimitLoad=2000);
            fac = model.Factors();   % DABJ defaults: FFU 1.15, FSU 1.4
            r = engine.marginShearTearout(j, lc, fac);
            testCase.verifyEqual(r.MS, 3.584, "AbsTol", 0.01);
            testCase.verifySubstring(r.Method, "Eq. 69-71");
            testCase.verifyFalse(contains(r.Detail, "CAUTION"));
            % No EdgeDistance anywhere -> NotEvaluated (NaN), not a crash
            j2 = j;
            j2.FlangeStack(1).EdgeDistance = NaN;
            r2 = engine.marginShearTearout(j2, lc, fac);
            testCase.verifyTrue(isnan(r2.MS));
        end

        function tearoutCautionBelowValidity(testCase)
            % e/D = 0.5/0.375 = 1.33 < 1.5: Eq. 69-71 is outside its
            % validity range there — the margin still computes (As =
            % 2*0.320*(0.5-0.1875) = 0.20 in^2) but Detail must carry the
            % Bruhn caution.
            fm = model.Material(Name="Tear-out member", Fsu=41000);
            b  = model.Bolt(Designation="3/8", NominalDiameter=0.375, ...
                ThreadsPerInch=24, TensileStressArea=0.0878);
            j  = model.Joint(Name="short-edge joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=fm, Thickness=0.320, ...
                                              EdgeDistance=0.50));
            lc  = model.LoadCase(BoltTensileLimitLoad=0, BoltShearLimitLoad=2000);
            r = engine.marginShearTearout(j, lc, model.Factors());
            testCase.verifySubstring(r.Detail, "CAUTION");
            testCase.verifySubstring(r.Detail, "e/D");
        end

        function bearingUnderHeadHandDerived(testCase)
            % HAND-DERIVED pin (no public worked example) on the DABJ
            % Example 8-b geometry, where engine.stiffness resolves to
            % phi = Kb/(Kb+Kc) = 2.3892e6/7.1145e6 = 0.3358 (tStiffness).
            % Configure: hole dia 0.397 in on flange 1, flange bearing
            % allowables Fbru = 121,000 / Fbry = 94,000 psi, direct preload
            % 2,000 lbf with Gamma = 0.25 and no thermal excursion
            % -> PpMax = 2,500 lbf; PtL = 3,000 lbf; n = 0.5 (fixture).
            % NASA-STD-5020B Eq. 8:
            %   Pb = 2500 + 0.5*0.3358*3000 = 3,003.7 lbf
            % Head side (head washer OD 0.687 governs over d_wf):
            %   Abr = (pi/4)*(0.687^2 - 0.397^2) = 0.2469 in^2   (Eq. 75)
            %   MS_u = 121000*0.2469/(1.15*1.4*3003.7) - 1
            %        = 29874.6/4836.0 - 1 = +5.177               (governs)
            %   MS_y = 94000*0.2469/(1.0*1.25*3003.7) - 1
            %        = 23208.4/3754.7 - 1 = +5.181
            % Nut side skipped: FlangeStack(end).HoleDiameter stays NaN.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.FlangeStack(1).HoleDiameter  = 0.397;
            j.FlangeStack(1).Material.Fbru = 121000;
            j.FlangeStack(1).Material.Fbry = 94000;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0.25);
            lc  = model.LoadCase(Name="under-head pin", ...
                BoltTensileLimitLoad=3000, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 2500, "AbsTol", 1e-9);
            r = engine.marginBearingUnderHead(j, lc, fac, p);
            testCase.verifyEqual(r.MS, 5.177, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "head side");
            testCase.verifySubstring(r.Method, "Eq. 75");
        end

        function dabjSection9RegressionUnchanged(testCase)
            % Phase 3.2 must not disturb the DABJ §9 answer key: WorstMargin
            % and GoverningCheck stay at the deliberate slip failure (-0.65).
            % Tear-out and under-head report NotEvaluated (the §9 fixture
            % has no EdgeDistance, no HoleDiameter, and no frustum
            % geometry). Bearing DOES evaluate — the library's Al 7075-T7351
            % carries handbook-fill Fbru = 121,000 / Fbry = 94,000 psi — to a
            % passing hand-derived margin (ultimate governs):
            %   Pbr  = 121000*0.375*0.375 = 17,015.6 lbf   (Eq. 72)
            %   MS_u = 17015.6/(1.15*1.4*1560) - 1 = 17015.6/2511.6 - 1 = +5.775
            %   MS_y = 94000*0.140625/(1.0*1.25*1560) - 1 = 13218.75/1950 - 1 = +5.779
            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            testCase.verifyEqual(r.WorstMargin, c.Expected.MS_Slip, ...
                "AbsTol", c.Tol.MarginAbsTol);
            testCase.verifyEqual(r.GoverningCheck, "Slip");
            testCase.verifyEqual(row(r, "Shear-tearout").Status, "NotEvaluated");
            testCase.verifyEqual(row(r, "Bearing-under-head").Status, "NotEvaluated");
            testCase.verifyEqual(row(r, "Bearing").Status, "Pass");
            testCase.verifyEqual(row(r, "Bearing").MS, 5.775, "AbsTol", 0.01);
        end
    end
end

% ---- Local helpers --------------------------------------------------------
function e = row(r, name)
%ROW  Look up one Margins row by Name from an engine.Result.
mask = [r.Margins.Name] == name;
assert(nnz(mask) == 1, "margin ""%s"" not found exactly once", name);
e = r.Margins(mask);
end
