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

        function bearingSaysWhenTheYieldCriterionCouldNotRun(testCase)
            % THE ROW USED TO GO QUIET. Method promises "both criteria", but
            % with no Fbry the yield branch simply never appends a candidate
            % and the Detail read "Governing: layer 1 (...), ultimate" - which
            % is indistinguishable from a genuine both-criteria minimum where
            % ultimate happened to win.
            %
            % Not hypothetical: NO material in the shipped library carries
            % Fbry, so this was every bearing row ever produced. Caught by a
            % legacy-spreadsheet comparison whose bearing YIELD margin had no
            % counterpart here (TOOL_DIFFERENCES.md 8.6).
            fm = model.Material(Name="Al 6061-T6 (no Fbry)", ...
                Ftu=42000, Fty=35000, Fsu=27000, Fbru=67000, E=10.0e6);
            b = model.Bolt(Designation="1/4-28", NominalDiameter=0.25, ...
                ThreadsPerInch=28, TensileStressArea=0.0364, MinorDiameter=0.2036);
            j = model.Joint(Name="No-Fbry joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=fm, Thickness=0.25));
            lc = model.LoadCase(Name="shear", ...
                BoltTensileLimitLoad=0, BoltShearLimitLoad=603);
            fac = model.Factors();
            r = engine.marginBearing(j, lc, fac);

            % The margin itself is unchanged - ultimate still governs.
            testCase.verifyEqual(r.MS, 3.313, "AbsTol", 0.01, ...
                'Disclosure must not move the number.');

            % ...and now the row says what it could not assess, and when
            % that could have mattered.
            testCase.verifySubstring(r.Detail, "YIELD criterion not assessed");
            testCase.verifySubstring(r.Detail, "Fbry unset");
            testCase.verifySubstring(r.Detail, "OPTIMISTIC");

            % The threshold is DERIVED FROM THE FACTORS IN USE, not a
            % literal. Hardcoding one is what broke this test first time
            % round: FFY defaults to 1.0 while FFU defaults to 1.15, so the
            % ratio is 0.776 at model defaults and 0.893 on a joint that
            % sets FFY = FFU = 1.15. A number pinned here would also rot
            % silently the next time a default moves.
            thr = (fac.FFY * fac.FSY) / (fac.FFU * fac.FSU);
            testCase.verifySubstring(r.Detail, sprintf('%.3f', thr));
            testCase.verifyEqual(thr, 0.776, "AbsTol", 0.001, ...
                'Guards the default factor pair itself, in one place.');
        end

        function bearingStaysSilentWhenBothCriteriaRan(testCase)
            % COMPANION TO THE ABOVE, and the reason it is here: an assertion
            % that a warning APPEARS proves nothing unless something proves it
            % can also be ABSENT. Give the same layer an Fbry and the note
            % must go away entirely - otherwise every row would carry a
            % caveat and the caveat would stop meaning anything.
            fm = model.Material(Name="Al 6061-T6 (with Fbry)", ...
                Ftu=42000, Fty=35000, Fsu=27000, ...
                Fbru=67000, Fbry=65300, E=10.0e6);
            b = model.Bolt(Designation="1/4-28", NominalDiameter=0.25, ...
                ThreadsPerInch=28, TensileStressArea=0.0364, MinorDiameter=0.2036);
            j = model.Joint(Name="With-Fbry joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=fm, Thickness=0.25));
            lc = model.LoadCase(Name="shear", ...
                BoltTensileLimitLoad=0, BoltShearLimitLoad=603);
            r = engine.marginBearing(j, lc, model.Factors());

            testCase.verifyFalse(contains(r.Detail, "not assessed"), ...
                'With both allowables present the row carries no caveat.');
            % Fbry/Fbru = 0.975 > 0.893, so ultimate still governs - which is
            % the case that made this bug invisible in the field.
            testCase.verifySubstring(r.Detail, "ultimate");
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

        function tearoutYieldCriterionCanGovern(testCase)
            % NASA-STD-5020B §4.4.2 p29 [TFSR 9] requires the yield
            % assessment to address "all elements of the threaded fastening
            % system ... AND THE CLAMPED PARTS". TM-106943 works tear-out
            % at ultimate only (Eq. 69 is Pult = Fsu*As throughout, and
            % unlike the bearing section it never mentions yield), so this
            % row had no yield criterion and nothing else covered it:
            % engine.systemTensileYieldAllowable discharges the yield
            % obligation for the TENSILE member modes, and tear-out is
            % shear-driven.
            %
            % HAND-DERIVED, same geometry as shearTearoutHandDerived:
            %   As   = 2*0.320*(0.75 - 0.1875) = 0.36 in^2   (TM Eq. 70)
            %   ultimate: Pult = 41,000*0.36 = 14,760 lbf
            %             MS = 14760/(1.15*1.4*2000) = 14760/3220 - 1 = +3.584
            %   yield:    Pyld = 20,000*0.36 =  7,200 lbf
            %             MS = 7200/(1.0*1.25*2000) = 7200/2500 - 1 = +1.880
            % Yield is the lower of the two, so it governs.
            fm = model.Material(Name="Tear-out member", Fsu=41000, Fsy=20000);
            b  = model.Bolt(Designation="3/8", NominalDiameter=0.375, ...
                ThreadsPerInch=24, TensileStressArea=0.0878);
            j  = model.Joint(Name="tear-out yield joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=fm, Thickness=0.320, ...
                                              EdgeDistance=0.75));
            lc  = model.LoadCase(Name="tear-out shear", ...
                BoltTensileLimitLoad=0, BoltShearLimitLoad=2000);
            fac = model.Factors();   % FFU 1.15, FSU 1.4, FFY 1.0, FSY 1.25

            r = engine.marginShearTearout(j, lc, fac);
            testCase.verifyEqual(r.MS, 1.880, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "yield");
            testCase.verifySubstring(r.Method, "§4.4.2 p29");

            % A SUPPLIED Fsy carries no estimate note -- only a derived one
            % does, so a real number is never dressed up as an estimate.
            testCase.verifyFalse(contains(r.Detail, "Eq. 63"));
        end

        function tearoutYieldUsesDerivedFsyAndSaysSo(testCase)
            % No Fsy, but an Fty: NASA-STD-5020B Eq. 63 (p66, A.8)
            % Fsy = Fty/sqrt(3). The repo convention is that an ESTIMATED
            % Fsy must never pass as test data, so the governing line has
            % to name the estimate.
            %   Fsy  = 30,000/sqrt(3) = 17,320.5 psi
            %   Pyld = 17,320.5*0.36  =  6,235.4 lbf
            %   MS   = 6235.4/2500 - 1 = +1.494   (governs over +3.584)
            fm = model.Material(Name="Tear-out member", Fsu=41000, Fty=30000);
            b  = model.Bolt(Designation="3/8", NominalDiameter=0.375, ...
                ThreadsPerInch=24, TensileStressArea=0.0878);
            j  = model.Joint(Name="tear-out derived-Fsy joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=fm, Thickness=0.320, ...
                                              EdgeDistance=0.75));
            lc  = model.LoadCase(Name="tear-out shear", ...
                BoltTensileLimitLoad=0, BoltShearLimitLoad=2000);

            r = engine.marginShearTearout(j, lc, model.Factors());
            testCase.verifyEqual(r.MS, 1.494, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "Eq. 63");
        end

        function tearoutSkipsYieldWithNoYieldData(testCase)
            % A member with neither Fsy nor Fty is UNASSESSED for yield,
            % not failed. shearTearoutHandDerived above depends on this --
            % its fixture carries only Fsu, and its +3.584 pin would move
            % if a yield criterion were invented from nothing.
            %
            % The companion assertion is what makes that non-vacuous: the
            % SAME fixture with an Fsy added DOES produce a different
            % margin, so "unchanged" here means the criterion was skipped,
            % not that the machinery is dead.
            b  = model.Bolt(Designation="3/8", NominalDiameter=0.375, ...
                ThreadsPerInch=24, TensileStressArea=0.0878);
            lc = model.LoadCase(Name="tear-out shear", ...
                BoltTensileLimitLoad=0, BoltShearLimitLoad=2000);
            fac = model.Factors();
            build = @(mat) model.Joint(Name="tear-out skip joint", Bolt=b, ...
                FlangeStack=model.FlangeLayer(Material=mat, Thickness=0.320, ...
                                              EdgeDistance=0.75));

            noYield = model.Material(Name="Fsu only", Fsu=41000);
            rNo = engine.marginShearTearout(build(noYield), lc, fac);
            testCase.verifyEqual(rNo.MS, 3.584, "AbsTol", 0.01, ...
                'With no yield data the ultimate criterion alone governs.');
            testCase.verifyFalse(contains(rNo.Detail, "yield"));

            withYield = model.Material(Name="Fsu and Fsy", Fsu=41000, Fsy=20000);
            rYes = engine.marginShearTearout(build(withYield), lc, fac);
            testCase.verifyNotEqual(rYes.MS, rNo.MS, ...
                'The yield criterion must be live -- otherwise the skip proves nothing.');
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
            % Example 8-b geometry. Configure: hole dia 0.397 in on flange
            % 1, flange bearing allowables Fbru = 121,000 / Fbry = 94,000
            % psi, direct preload 2,000 lbf with Gamma = 0.25 and no
            % thermal excursion -> PpMax = 2,500 lbf; PtL = 3,000 lbf;
            % n = 0.5 (fixture).
            %
            % NASA-STD-5020B Fig. 8 GATE, checked first (this is now the
            % gate-ASSURED test — see bearingUnderHeadGateNotAssuredClampedLoad
            % for the NOT-assured/clamped branch):
            %   Ptu_allow (system, bolt-tension mode, no rating set) =
            %     At*Ftu = 0.0878*160000 = 14,048 lbf
            %   1. Ec(10e6) > Eb/3(29e6/3 = 9,666,667)          -> true
            %   2. PpMax(2500) <= 0.75*Ptu_allow(0.75*14048 = 10,536) -> true
            %   3. n(0.5) <= 0.9                                 -> true
            %   4. e/D >= 1.5 ASSUMED (no FlangeLayer.EdgeDistance set on
            %      this fixture -- see tStiffness.m for the VERIFIED cases)
            % All four hold -> ASSURED. Per NASA-STD-5020B §4.4.5, once
            % separation before rupture is assured the clamped members
            % carry no load, so the bolt sees the applied load only:
            %   Pb = PtL = 3,000 lbf   (no preload term, no n·phi discount)
            % Head side (head washer OD 0.687 governs over d_wf):
            %   Abr = (pi/4)*(0.687^2 - 0.397^2) = 0.2468977666... in^2 (Eq. 75)
            %   MS_u = 121000*0.2468977666/(1.15*1.4*3000) - 1
            %        = 29874.629/4830 - 1 = +5.1852              (governs)
            %   MS_y = 94000*0.2468977666/(1.0*1.25*3000) - 1
            %        = 23208.390/3750 - 1 = +5.1889
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
            testCase.verifyEqual(r.MS, 5.1852, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "head side");
            testCase.verifySubstring(r.Detail, "SEPARATED branch");
            testCase.verifySubstring(r.Detail, "gate assured");
            testCase.verifySubstring(r.Method, "Eq. 75");
        end

        function bearingUnderHeadGateNotAssuredClampedLoad(testCase)
            % Covers the CLAMPED branch (Fig. 8 gate NOT assured) that
            % bearingUnderHeadHandDerived no longer exercises now that its
            % own numbers turn out to satisfy the gate. Same Example 8-b
            % geometry, but the preload is raised so the gate's preload
            % condition fails while everything else about the fixture is
            % unchanged:
            %   NominalPreload = 15,000, Uncertainty = 0 -> PpMax = 15,000
            %   Ptu_allow = 14,048 lbf (same derived bolt-tension mode as
            %     above -- unaffected by preload)
            %   Gate: PpMax(15000) > 0.75*Ptu_allow(10,536)      -> FAILS
            %   (Ec > Eb/3 and n <= 0.9 still hold, but one failing
            %   condition is enough) -> NOT ASSURED, rupture assumed.
            % CLAMPED branch. NASA-STD-5020B §4.4.5: "...a factor of safety
            % is not applied to preload" -> the MS denominator factors only
            % the EXTERNAL n*phi*PtL term (matches engine.boltDesignLoad):
            %   MS denom = PpMax + FF*FS*n*phi*PtL
            % (Pb = PpMax + n*phi*PtL = 15000 + 0.5*0.3354*3000 = 15,503.1
            % lbf remains the informational bolt axial design load only —
            % it is NOT the MS denominator on this branch.)
            % Head side (same Abr = 0.2468977666 in^2 as above):
            %   denom_u = 15000 + 1.15*1.4*0.5*0.3354*3000
            %           = 15000 + 809.991 = 15,809.991
            %   denom_y = 15000 + 1.0*1.25*0.5*0.3354*3000
            %           = 15000 + 628.875 = 15,628.875
            %   MS_u = 121000*0.2468977666/15809.991 - 1
            %        = 29874.629/15809.991 - 1 = +0.8896
            %   MS_y = 94000*0.2468977666/15628.875 - 1
            %        = 23208.390/15628.875 - 1 = +0.4850          (governs)
            % Yield now governs (it did not before Part 1): the factored
            % term is small next to PpMax, so the two denominators are
            % close, and the ultimate/yield ALLOWABLE ratio (121000/94000)
            % dominates over the small denominator ratio.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.FlangeStack(1).HoleDiameter  = 0.397;
            j.FlangeStack(1).Material.Fbru = 121000;
            j.FlangeStack(1).Material.Fbry = 94000;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 15000, ...
                Uncertainty    = 0);
            lc  = model.LoadCase(Name="under-head pin, gate not assured", ...
                BoltTensileLimitLoad=3000, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 15000, "AbsTol", 1e-9);
            r = engine.marginBearingUnderHead(j, lc, fac, p);
            testCase.verifyEqual(r.MS, 0.4850, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "head side");
            testCase.verifySubstring(r.Detail, "yield");
            testCase.verifySubstring(r.Detail, "CLAMPED branch");
            testCase.verifySubstring(r.Detail, "not assured");
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
