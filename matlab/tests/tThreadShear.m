classdef tThreadShear < matlab.unittest.TestCase
    %TTHREADSHEAR  Phase 3.3 acceptance: the four thread-strength checks —
    %   engine.marginBoltThreadShear (TM-106943 Eq. 63/64/65 basis),
    %   engine.marginNutStrength (Eq. 76/77 + Eq. 65, ultimate/yield pair,
    %   spec rating as an ultimate ceiling per 5020B §4.4.1),
    %   engine.marginTappedParentThread (Eq. 79 + Eq. 65, ultimate-only by
    %   deliberate decision), and engine.marginInsert (area x parent shear
    %   strength ult/yld with the rated pull-out as an ultimate ceiling,
    %   5020B §4.4.1) — all using the pitch-diameter thread-shear area
    %   As = 0.75·pi·E·Le (E = pitch diameter, Le = engagement length) and
    %   the design bolt loads Pb = PpMax + FFU·FSU·n·phi·PtL /
    %   PbYield = PpMax + FFY·FSY·n·phi·PtL (NASA-STD-5020B Eq. 8 form,
    %   engine.boltDesignLoad; phi = 1 assumed for threaded-in configs).
    %
    %   Validation strategy (VALIDATION.md rows 7-9, 14): the tapped-parent
    %   AREA and ALLOWABLE are cross-checked against DABJ Example 6-a (the
    %   only public thread pull-out example); every MS is pinned with
    %   HAND-DERIVED arithmetic documented inline. The DABJ §9 answer key
    %   is re-run through analyze() to prove Phase 3.3 does not disturb it.
    %   tappedParentGateAssuredSeparatedLoad / ...NotAssuredClampedLoad pin
    %   the NASA-STD-5020B Fig. 8 separation-before-rupture branch in
    %   engine.boltDesignLoad: the design load must switch to the
    %   SEPARATED form Pb = FF·FS·PtL (no preload/n·phi) once the gate is
    %   assured, and stay at the clamped Pb = PpMax + FF·FS·n·phi·PtL form
    %   otherwise — the same gate engine.marginTensionUlt reports, so the
    %   two can never disagree (see separationBeforeRuptureGate).
    %
    %   The Fig. 8 gate ALSO fires on the boltThreadShearHandDerived /
    %   nutJoint()-based tests below: that fixture (DABJ Example 8-b) has a
    %   FlangeStack, and once engine.boltTensileAllowable made a derived
    %   bolt allowable (At*Ftu) assessable even without
    %   Joint.BoltRatedUltimateLoad, the gate's Ptu_allow, PpMax(2,500), and
    %   n(0.5) all genuinely satisfy Fig. 8's conditions for THIS joint —
    %   this is not a fixture artifact, so the SEPARATED design load is the
    %   correct one and every MS below is re-derived accordingly (each
    %   test's comment shows the arithmetic); see
    %   boltThreadShearHandDerived for the full condition-by-condition
    %   check, referenced by the sibling nut tests rather than repeated.
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
        function tappedParentMatchesDABJ6a(testCase)
            % DABJ Example 6-a (pp. 6-6..6-8): #10-32 A-286 screw fully
            % engaged in 0.250-in-thick 6061-T651 aluminum plate. The book's
            % tolerance-extreme internal-thread shear area (Eq. 6.8) is
            % Asi-min = 0.0986 in^2 and the un-knocked allowable is
            % 27,000 * 0.0986 = 2,660 lb. This tool's pitch-diameter form:
            %   As   = 0.75*pi*E*Le = 0.75*pi*0.1697*0.250 = 0.09996 in^2
            %   Pult = 27000*0.09996 = 2,699 lb
            % both within 1.5% of the book (RelTol 0.03 asserted).
            % NOTE: DABJ then applies a 0.70 judgment knockdown -> 1,860 lb;
            % this tool does NOT knock down, so the cross-check is
            % against the UN-KNOCKED area/allowable only.
            %
            % The MS is HAND-DERIVED (depends on the chosen Pb): direct
            % preload 1,000 lb, Gamma = 0.25, no thermal -> PpMax = 1,250 lb;
            % PtL = 400 lb; n = 1 (default); phi = 1 (threaded-in
            % assumption); DABJ default factors FFU = 1.15, FSU = 1.4:
            %   Pb = 1250 + 1.15*1.4*1*1*400 = 1,894 lb   (5020B Eq. 8 form)
            %   MS = 2698.96/1894 - 1 = +0.425
            b = model.Bolt(Designation="#10-32 UNF (Ex 6-a)", ...
                NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
                ThreadsPerInch=32, TensileStressArea=0.0200, ...
                MinorDiameter=0.156, PitchDiameter=0.1697);
            bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
                Fsu=95000, E=29.1e6);
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, E=9.9e6);
            j = model.Joint(Name="DABJ Ex 6-a tapped joint", ...
                Bolt=b, BoltMaterial=bm, ...
                ThreadedMember=model.ThreadedMember( ...
                    Type=model.ThreadedMemberType.TappedHole, ...
                    Material=parent, EngagementLength=0.250), ...
                PreloadSpec=model.PreloadSpec( ...
                    Method=model.PreloadMethod.DirectPreload, ...
                    NominalPreload=1000, Uncertainty=0.25));
            lc  = model.LoadCase(Name="Ex 6-a pull-out", ...
                BoltTensileLimitLoad=400, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults: FFU 1.15, FSU 1.4
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 1250, "AbsTol", 1e-9);
            r = engine.marginTappedParentThread(j, lc, fac, p);
            % Cross-check vs the DABJ Ex 6-a area/allowable (un-knocked)
            testCase.verifyEqual(r.As,   0.0986, "RelTol", 0.03);
            testCase.verifyEqual(r.Pult, 2660,   "RelTol", 0.03);
            % Exact-arithmetic pins of the pitch-diameter form itself
            testCase.verifyEqual(r.As, 0.75*pi*0.1697*0.250, "AbsTol", 1e-12);
            testCase.verifyEqual(r.Pb, 1894, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, 0.425, "AbsTol", 0.01);
            testCase.verifySubstring(r.Method, "Eq. 79");
            testCase.verifySubstring(r.Method, "0.75");
            % Wrong configuration -> NotEvaluated, not a crash
            j2 = j;
            j2.ThreadedMember.Type = model.ThreadedMemberType.Nut;
            r2 = engine.marginTappedParentThread(j2, lc, fac, engine.preload(j2));
            testCase.verifyTrue(isnan(r2.MS));
        end

        function boltThreadShearHandDerived(testCase)
            % HAND-DERIVED pin on the DABJ Example 8-b geometry (a Nut
            % joint, so phi comes from the REAL stiffness path:
            % phi = 0.3354, tStiffness -- not used by this branch's
            % SEPARATED Pb form below, but resolved). Add the Phase 3.3
            % thread inputs:
            % E = 0.3479 in (3/8-24 UNF basic pitch dia), Le = 0.375 in.
            % Direct preload 2,000 lb, Gamma = 0.25, no thermal
            % -> PpMax = 2,500 lb; PtL = 3,000 lb; n = 0.5 (fixture);
            % DABJ default factors FFU = 1.15, FSU = 1.4:
            %   As   = 0.75*pi*0.3479*0.375 = 0.30740 in^2
            %   Pult = 95000*0.30740 = 29,202.5 lb          (bolt Fsu)
            %
            % Fig. 8 GATE (NASA-STD-5020B, engine.boltDesignLoad via
            % separationBeforeRuptureGate): this Example 8-b fixture has a
            % FlangeStack (Ec = 10e6, the fitting material) AND, since the
            % engine now derives a bolt allowable when
            % Joint.BoltRatedUltimateLoad is unset (boltTensileAllowable,
            % At*Ftu = 0.0878*160000 = 14,048 lbf), the system
            % Ptu_allow = min(bolt 14,048, nut 95000*0.30740 = 29,202.5) =
            % 14,048 lbf is now assessable (previously it was not, so the
            % gate silently fell to CLAMPED). Checking Fig. 8:
            %   Ec(10e6) > Eb/3(29e6/3 = 9.667e6): holds (Eb from this
            %     fixture's own Example 8-b bolt material, 29e6 psi).
            %   PpMax(2,500) < 0.75*Ptu_allow(10,536): holds.
            %   n(0.5) <= 0.9: holds.
            %   -> gate ASSURED, so Pb takes the SEPARATED form (no
            %      preload, no n*phi):
            %   Pb = FFU*FSU*PtL = 1.15*1.4*3000 = 4,830 lb
            %   MS = 29202.5/4830 - 1 = +5.046
            c = validation.dabjExample8b();
            j = c.Joint;
            j.Bolt.PitchDiameter = 0.3479;
            j.ThreadedMember.EngagementLength = 0.375;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0.25);
            lc  = model.LoadCase(Name="thread-shear pin", ...
                BoltTensileLimitLoad=3000, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 2500, "AbsTol", 1e-9);
            r = engine.marginBoltThreadShear(j, lc, fac, p);
            testCase.verifyEqual(r.As,   0.30740,  "AbsTol", 1e-4);
            testCase.verifyEqual(r.Pult, 29202.5,  "RelTol", 0.001);
            testCase.verifyEqual(r.Pb,   4830,     "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS,   5.046,    "AbsTol", 0.01);
            testCase.verifySubstring(r.Method, "Eq. 63");
            testCase.verifySubstring(r.Method, "0.75");
            % Missing engagement length -> NotEvaluated, not a crash
            j2 = j;
            j2.ThreadedMember.EngagementLength = NaN;
            r2 = engine.marginBoltThreadShear(j2, lc, fac, p);
            testCase.verifyTrue(isnan(r2.MS));
        end

        function nutStrengthHandDerived(testCase)
            % HAND-DERIVED pin, same Ex 8-b Nut fixture as above but with a
            % deliberately SOFTER nut material (Fsu = 60,000 psi) so the
            % internal side would govern over the bolt-external side.
            %   As      = 0.75*pi*0.3479*0.375 = 0.307395 in^2  (same area)
            %   Pult    = 60000*0.307395 = 18,443.7 lb          (NUT Fsu)
            %   AllowYld= 58000*0.307395 = 17,828.9 lb          (NUT Fsy)
            %
            % Fig. 8 GATE (see boltThreadShearHandDerived for the full
            % condition-by-condition derivation, same joint/loads): system
            % Ptu_allow = min(bolt-derived 14,048, nut 18,443.7) = 14,048
            % lbf is now assessable (boltTensileAllowable), and
            % Ec(10e6) > Eb/3(9.667e6), PpMax(2,500) < 0.75*14,048(10,536),
            % n(0.5) <= 0.9 all hold -> gate ASSURED -> SEPARATED Pb form:
            %   Pb      = FFU*FSU*PtL = 1.15*1.4*3000 = 4,830 lb
            %   PbYield = FFY*FSY*PtL = 1.0*1.25*3000 = 3,750 lb
            %   ult: 18443.7/4830 - 1 = +2.819   <- governs (worst)
            %   yld: 17828.9/3750 - 1 = +3.754
            [j, lc, fac] = nutJoint(model.Material( ...
                Name="Soft nut (pin fixture)", Fsu=60000, Fsy=58000), 0, NaN);
            p = engine.preload(j);
            r = engine.marginNutStrength(j, lc, fac, p);
            testCase.verifyEqual(r.As, 0.75*pi*0.3479*0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(r.Pult,     18443.7, "RelTol", 0.001);
            testCase.verifyEqual(r.AllowYld, 17828.9, "RelTol", 0.001);
            testCase.verifyEqual(r.Pb,      4830.0, "RelTol", 0.001);
            testCase.verifyEqual(r.PbYield, 3750.0, "RelTol", 0.001);
            testCase.verifyEqual(r.MS,   2.819,   "AbsTol", 0.01);
            testCase.verifySubstring(r.Method, "Eq. 76");
            testCase.verifySubstring(r.Detail, "ultimate");
            % Supplied Fsy must be flagged as supplied, not estimated
            testCase.verifySubstring(r.Detail, "supplied");
            % Not a nut -> NotEvaluated, not a crash
            j2 = j;
            j2.ThreadedMember.Type = model.ThreadedMemberType.TappedHole;
            r2 = engine.marginNutStrength(j2, lc, fac, engine.preload(j2));
            testCase.verifyTrue(isnan(r2.MS));
        end

        % ================================================================
        % Nut ultimate/yield pair + spec rating as an ultimate ceiling
        % (mirrors the insert area-path tests; NASA-STD-5020B §4.4.1)
        % ================================================================

        function nutYieldGovernsHandDerived(testCase)
            % HAND-DERIVED pin, yield governing, Fsy SUPPLIED. Same Ex 8-b
            % fixture and loads as nutStrengthHandDerived (PpMax = 2,500 lb,
            % PtL = 3,000 lb, n = 0.5, phi = 0.3354 from the real stiffness
            % path — tStiffness / dabjExample8b), each criterion vs the
            % design load with ITS OWN factor pair (DABJ default factors
            % FFU 1.15, FSU 1.4, FFY 1.0, FSY 1.25).
            %
            % Fig. 8 GATE ASSURED (see boltThreadShearHandDerived for the
            % full derivation — same joint/loads, same Ptu_allow = 14,048
            % lbf bolt-derived governing since nut 18,443.7 lbf is higher):
            % SEPARATED Pb form applies:
            %   Pb      = FFU*FSU*PtL = 1.15*1.4*3000 = 4,830 lb
            %   PbYield = FFY*FSY*PtL = 1.0*1.25*3000 = 3,750 lb
            %   As      = 0.75*pi*0.3479*0.375 = 0.307395 in^2
            %   ult: 60000*0.307395/4830 - 1 = 18443.7/4830 - 1 = +2.819
            %   yld: 40000*0.307395/3750 - 1 = 12295.8/3750 - 1 = +2.279
            %        <- governs (worst)
            [j, lc, fac] = nutJoint(model.Material( ...
                Name="Soft nut (yield pin)", Fsu=60000, Fsy=40000), 0, NaN);
            r = engine.marginNutStrength(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.Pult,     18443.7, "RelTol", 0.001);
            testCase.verifyEqual(r.AllowYld, 12295.8, "RelTol", 0.001);
            testCase.verifyEqual(r.MS, 2.279, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "yield");
            testCase.verifySubstring(r.Detail, "supplied");
        end

        function nutSuppliedAreaIsIgnored(testCase)
            % A nut's area is ALWAYS the computed 0.75·pi·E·Le. A supplied
            % ThreadedMember.ShearEngagementArea must be IGNORED outright,
            % not preferred: NASA-STD-5020B §4.4.1 gives a nut a rated LOAD
            % ("Nuts should be limited to the load rating of the nut") and
            % contemplates no shear engagement area for one at all, so a
            % per-joint area carries neither the standard's authority nor
            % this tool's method. (An insert is the opposite case and DOES
            % honour a specified area — §4.4.1 defines its allowable that
            % way — see insertSuppliedAreaWinsOverCatalogueGeometry.)
            %
            % This fixture supplies 0.2000 in^2 precisely so that ignoring
            % it is observable: honouring it would give As = 0.2000 and
            % MS = +1.133, which is the behaviour this test used to pin.
            %
            % Computed instead: As = 0.75·pi·E·Le = 0.307395 in^2, the same
            % area as nutYieldGovernsHandDerived.
            % Fig. 8 GATE ASSURED: the computed area feeds the system's
            % nut-mode allowable (60000*0.307395 = 18,443.7 lbf), so
            % Ptu_allow = min(bolt-derived 14,048, nut 18,443.7) = 14,048
            % lbf — the gate is at least as assured as with the smaller
            % supplied area -> SEPARATED Pb form, Pb = FFU*FSU*PtL = 4,830
            % lb, PbYield = FFY*FSY*PtL = 3,750 lb:
            %   ult: 60000*0.307395/4830 - 1 = 18443.7/4830 - 1 = +2.819
            %   yld: 40000*0.307395/3750 - 1 = 12295.8/3750 - 1 = +2.279
            %        <- governs (worst)
            [j, lc, fac] = nutJoint(model.Material( ...
                Name="Soft nut (yield pin)", Fsu=60000, Fsy=40000), 0, 0.2000);
            r = engine.marginNutStrength(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.As, 0.307395, "AbsTol", 1e-5);
            testCase.verifyEqual(r.Pult,    18443.7, "AbsTol", 0.1);
            testCase.verifyEqual(r.AllowYld, 12295.8, "AbsTol", 0.1);
            testCase.verifyEqual(r.MS, 2.279, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "yield");
            % Detail must name the computed form, and must NOT claim a
            % supplied area was used or overrode anything.
            testCase.verifySubstring(r.Detail, "0.75·pi·E·Le");
            testCase.verifyFalse(contains(r.Detail, "overrides"));
            testCase.verifyFalse(contains(r.Detail, "ShearEngagementArea"));
        end

        function nutRatingCeilingGoverns(testCase)
            % CEILING (NASA-STD-5020B §4.4.1, "limited to the load rating
            % of the nut"): a spec rating BELOW the computed ultimate
            % allowable caps it — lower-of, ultimate criterion only:
            %   ult allowable = min(18443.7, 10000) = 10,000 lb (rating)
            %
            % Fig. 8 GATE ASSURED: the rating-capped nut mode (10,000 lbf)
            % is itself the system Ptu_allow here (min(bolt-derived 14,048,
            % nut-capped 10,000) = 10,000), still comfortably above
            % 0.75^-1*PpMax, so the remaining Fig. 8 conditions (see
            % boltThreadShearHandDerived) hold -> SEPARATED Pb form,
            % Pb = FFU*FSU*PtL = 4,830 lb, PbYield = FFY*FSY*PtL = 3,750 lb:
            %   ult: 10000/4830 - 1 = +1.070   <- governs (worst)
            %   yld: 12295.8/3750 - 1 = +2.279 (NOT capped — the rating
            %        is an ultimate quantity, see marginNutStrength header)
            [j, lc, fac] = nutJoint(model.Material( ...
                Name="Soft nut (yield pin)", Fsu=60000, Fsy=40000), 10000, NaN);
            r = engine.marginNutStrength(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.Pult, 10000, "AbsTol", 1e-9);   % effective ult allowable = rating
            testCase.verifyEqual(r.AllowYld, 12295.8, "RelTol", 0.001);  % yield NOT capped
            testCase.verifyEqual(r.MS, 1.070, "AbsTol", 0.01);
            testCase.verifyEqual(r.Rating, 10000);
            testCase.verifySubstring(r.Detail, "ultimate");
            testCase.verifySubstring(r.Detail, "GOVERNS");
        end

        function nutRatingNotLimiting(testCase)
            % Same fixture with a rating ABOVE the computed allowable
            % (20,000 > 18,443.7): the computed area form stands, and the
            % Detail records that the rating is not limiting.
            %
            % Fig. 8 GATE ASSURED (system Ptu_allow = min(bolt-derived
            % 14,048, nut 18,443.7) = 14,048; rating 20,000 is not limiting
            % on the nut mode either — see boltThreadShearHandDerived for
            % the full condition derivation) -> SEPARATED Pb form,
            % Pb = 4,830 lb, PbYield = 3,750 lb: the MS is identical to
            % nutYieldGovernsHandDerived (+2.279, yield governs).
            [j, lc, fac] = nutJoint(model.Material( ...
                Name="Soft nut (yield pin)", Fsu=60000, Fsy=40000), 20000, NaN);
            r = engine.marginNutStrength(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.Pult, 18443.7, "RelTol", 0.001);
            testCase.verifyEqual(r.MS, 2.279, "AbsTol", 0.01);
            testCase.verifyEqual(r.Rating, 20000);
            testCase.verifySubstring(r.Detail, "not limiting");
        end

        function nutRatingOnlyFallback(testCase)
            % FLAT-RATING fallback: with NO area available (EngagementLength
            % NaN, no supplied area — but Ex 8-b's explicit
            % BodyLengthInGrip = 0.70 keeps the stiffness path alive), a
            % spec rating alone still evaluates, ULTIMATE-ONLY.
            %
            % Fig. 8 GATE ASSURED: with no area, the nut mode is rated-only
            % (EffUlt = 10,000 lbf); system Ptu_allow = min(bolt-derived
            % 14,048, nut 10,000) = 10,000 lbf, still well above
            % 0.75^-1*PpMax, and the other Fig. 8 conditions hold (see
            % boltThreadShearHandDerived) -> SEPARATED Pb form,
            % Pb = FFU*FSU*PtL = 1.15*1.4*3000 = 4,830 lb:
            %   MS = 10000/4830 - 1 = +1.070
            [j, lc, fac] = nutJoint(model.Material( ...
                Name="Rated nut (no geometry)"), 10000, NaN);
            j.ThreadedMember.EngagementLength = NaN;
            r = engine.marginNutStrength(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.MS, 1.070, "AbsTol", 0.01);
            testCase.verifyEqual(r.Rating, 10000);
            testCase.verifyTrue(isnan(r.As));
            testCase.verifyTrue(isnan(r.AllowYld));   % no yield criterion on this path
            testCase.verifySubstring(r.Method, "4.4.1");
            testCase.verifySubstring(r.Detail, "ultimate-only");
            % No area AND no rating -> NotEvaluated, not a crash
            j2 = j;
            j2.ThreadedMember.RatedUltimateLoad = 0;
            r2 = engine.marginNutStrength(j2, lc, fac, engine.preload(j2));
            testCase.verifyTrue(isnan(r2.MS));
            testCase.verifySubstring(r2.Detail, "Not evaluated");
        end

        function nutDerivedFsyFlagged(testCase)
            % Fsy NaN -> derived Fsy = Fty/sqrt(3) = 70000/sqrt(3)
            % = 40,414.5 psi (von Mises), and the Detail MUST say the value
            % is an estimate.
            %
            % Fig. 8 GATE ASSURED (system Ptu_allow = min(bolt-derived
            % 14,048, nut 18,443.7) = 14,048; see boltThreadShearHandDerived
            % for the full condition derivation) -> SEPARATED Pb form,
            % Pb = 4,830 lb, PbYield = 3,750 lb:
            %   yld: 40414.5*0.307395/3750 - 1
            %        = 12423.2/3750 - 1 = +2.313   <- governs
            %   (ult unchanged in form: 18443.7/4830 - 1 = +2.819)
            [j, lc, fac] = nutJoint(model.Material( ...
                Name="Nut (derived Fsy)", Fsu=60000, Fty=70000), 0, NaN);
            r = engine.marginNutStrength(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.AllowYld, (70000/sqrt(3))*0.75*pi*0.3479*0.375, ...
                "RelTol", 1e-9);
            testCase.verifyEqual(r.MS, 2.313, "AbsTol", 0.01);
            testCase.verifySubstring(r.Detail, "yield");
            testCase.verifySubstring(r.Detail, "von Mises");
            testCase.verifySubstring(r.Detail, "estimated");
            % Fsu present but Fty/Fsy both NaN -> NotEvaluated with the
            % reason (no silent ultimate-only, no silent rating fallback)
            [j2, lc2, fac2] = nutJoint(model.Material( ...
                Name="Fsu only", Fsu=60000), 10000, NaN);
            r2 = engine.marginNutStrength(j2, lc2, fac2, engine.preload(j2));
            testCase.verifyTrue(isnan(r2.MS));
            testCase.verifySubstring(r2.Detail, "Fsy");
        end

        function dabjNutRatingFallbackStaysNotEvaluated(testCase)
            % REGRESSION GUARD (the safety constraint): the DABJ §9 fixture
            % is a Nut with RatedUltimateLoad = 15,200 lb but NO
            % EngagementLength AND no stiffness geometry (no
            % BodyLengthInGrip / Bolt.Length; the level-3 L1 fallback needs
            % the missing EngagementLength), so engine.stiffness cannot
            % produce phi and boltDesignLoad returns Pb = NaN. The new
            % flat-rating fallback therefore CANNOT evaluate — the
            % nut-strength row must stay NotEvaluated and the answer key's
            % WorstMargin must stay -0.65, governed by Slip (Solutions-23,
            % Eq. 84).
            c = validation.dabjSection9();
            p = engine.preload(c.Joint);
            r = engine.marginNutStrength(c.Joint, c.LoadCase, c.Factors, p);
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifySubstring(r.Detail, "Not evaluated");
            testCase.verifyEqual(r.Rating, 15200);   % the rating was seen, not ignored
            % And through analyze(): row + answer key unchanged
            res = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            testCase.verifyEqual(row(res, "Nut strength").Status, "NotEvaluated");
            testCase.verifyEqual(res.WorstMargin, c.Expected.MS_Slip, ...
                "AbsTol", c.Tol.MarginAbsTol);       % -0.65
            testCase.verifyEqual(res.GoverningCheck, "Slip");
        end

        function insertUsesHelicoilRating(testCase)
            % Insert margin = MANUFACTURER rated pull-out / Pb - 1 (the
            % rating-only path: one spec value, no thread-shear calc).
            % The 12,949 lb rating is an ILLUSTRATIVE INPUT, not a
            % Heli-Coil value. What this test pins is the flat-rating
            % arithmetic (rating/Pb - 1) and the NotEvaluated path when no
            % rating is set; the rating itself is arbitrary to that.
            %
            % No published Heli-Coil pull-out load exists to anchor it to.
            % The Stanley Heli-Coil catalogue (HC2000 Rev 12, p. 11)
            % defers to Technical Bulletin 68-2, and 68-2 presents its
            % data only as charts of assembly tensile strength vs parent
            % shear strength — no tabulated loads, no shear engagement
            % area. NASM33537 Rev 4 gives dimensions and no strengths.
            %
            % A previous version of this comment derived 12,949 lb from
            % the insert WIRE strength (Nitronic 60, Ftu = 200,000 psi)
            % times a parent-side area. That is wrong on its own terms:
            % NASA-STD-5020B §4.4.1 puts an insert's pull-out capacity in
            % the PARENT material, so a parent-side area belongs with the
            % parent's shear strength, never the wire's. The parent-based
            % form is exercised properly by insertAreaUltimateGoverns,
            % insertAreaYieldGovernsSuppliedFsy and
            % insertRatingCeilingGoverns below; this test does not.
            % HAND-DERIVED MS: direct preload 1,000 lb, Gamma = 0.25, no
            % thermal -> PpMax = 1,250 lb; PtL = 1,000 lb; n = 1; phi = 1
            % (threaded-in assumption); FFU = 1.15, FSU = 1.4:
            %   Pb = 1250 + 1.15*1.4*1*1*1000 = 2,860 lb
            %   MS = 12949/2860 - 1 = +3.528
            b = model.Bolt(Designation="#10-32 UNF", ...
                NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
                ThreadsPerInch=32, TensileStressArea=0.0200, ...
                MinorDiameter=0.156, PitchDiameter=0.1697);
            bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
                Fsu=95000, E=29.1e6);
            j = model.Joint(Name="Heli-Coil insert joint", ...
                Bolt=b, BoltMaterial=bm, ...
                ThreadedMember=model.ThreadedMember( ...
                    Type=model.ThreadedMemberType.Insert, ...
                    Material=model.Material(Name="Nitronic 60"), ...
                    RatedUltimateLoad=12949, EngagementLength=0.3006), ...
                PreloadSpec=model.PreloadSpec( ...
                    Method=model.PreloadMethod.DirectPreload, ...
                    NominalPreload=1000, Uncertainty=0.25));
            lc  = model.LoadCase(Name="insert pull-out", ...
                BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults
            p = engine.preload(j);
            r = engine.marginInsert(j, lc, fac, p);
            testCase.verifyEqual(r.Pb, 2860, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, 3.528, "AbsTol", 0.01);
            testCase.verifySubstring(r.Method, "rated pull-out");
            % No rating set (default 0) -> NotEvaluated, not a crash
            j2 = j;
            j2.ThreadedMember.RatedUltimateLoad = 0;
            r2 = engine.marginInsert(j2, lc, fac, engine.preload(j2));
            testCase.verifyTrue(isnan(r2.MS));
        end

        function dabjSection9RegressionUnchanged(testCase)
            % Phase 3.3 must not disturb the DABJ §9 answer key. The §9
            % fixture is a Nut joint with NO EngagementLength (and no
            % frustum geometry), so all five thread rows resolve
            % NotEvaluated; the six published margins, the +5.775 bearing,
            % and WorstMargin/GoverningCheck (the deliberate slip failure,
            % -0.65) are unchanged.
            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            tol = c.Tol.MarginAbsTol;
            testCase.verifyEqual(row(r, "Tension-Ultimate").MS, ...
                c.Expected.MS_TensionUlt, "AbsTol", tol);
            testCase.verifyEqual(row(r, "Tension-Yield").MS, ...
                c.Expected.MS_BoltYield, "AbsTol", tol);
            testCase.verifyEqual(row(r, "Shear-Ultimate").MS, ...
                c.Expected.MS_ShearUlt, "AbsTol", tol);
            % Interaction is NOT a margin (see engine.analyze's INTERACTION
            % IS NOT A MARGIN note) -- MS = NaN by design, Status carries
            % the real Pass/Fail (R = 0.483642 on this fixture, Pass; see
            % tDabjCase.m's interactionMarginMatchesDABJ for the derivation).
            testCase.verifyTrue(isnan(row(r, "Interaction").MS));
            testCase.verifyEqual(row(r, "Interaction").Status, "Pass");
            testCase.verifyEqual(row(r, "Separation").MS, ...
                c.Expected.MS_Separation, "AbsTol", tol);
            testCase.verifyEqual(row(r, "Slip").MS, ...
                c.Expected.MS_Slip, "AbsTol", tol);
            testCase.verifyEqual(row(r, "Bearing").MS, 5.775, "AbsTol", 0.01);
            testCase.verifyEqual(r.WorstMargin, c.Expected.MS_Slip, ...
                "AbsTol", tol);
            testCase.verifyEqual(r.GoverningCheck, "Slip");
            % The five Phase 3.3 thread rows all NotEvaluated on §9
            for name = ["Bolt-thread shear", "Nut strength", ...
                        "Insert internal-thread", "Insert external-thread", ...
                        "Tapped-hole parent-thread"]
                testCase.verifyEqual(row(r, name).Status, "NotEvaluated", ...
                    "row """ + name + """ must be NotEvaluated on the §9 fixture");
            end
        end

        % ================================================================
        % Insert shear-engagement-area path (NASA-STD-5020B §4.4.1) + Fsy
        % ================================================================

        function shearYieldSuppliedAndDerived(testCase)
            % engine.shearYieldStrength: supplied Fsy wins; NaN Fsy derives
            % the von Mises estimate Fsy = Fty/sqrt(3).
            % Expected numbers (the von Mises estimate agrees with the
            % commonly tabulated Fsy for these alloys to stored precision):
            %   A286:          Fty 85,000 -> 85000/sqrt(3) = 49,074.8 psi
            %                  (tabulated as 49.1 ksi)
            %   300-ser CRES:  Fty 30,000 -> 30000/sqrt(3) = 17,320.5 psi
            %                  (tabulated as 17.3 ksi)
            % Supplied case: Fsy = 49,100 psi must be returned AS GIVEN
            % (not re-derived), with Derived = false.
            s = engine.shearYieldStrength( ...
                model.Material(Name="A286", Fty=85000, Fsy=49100));
            testCase.verifyEqual(s.Fsy, 49100, "AbsTol", 1e-12);
            testCase.verifyFalse(s.Derived);
            testCase.verifySubstring(s.Basis, "supplied");
            % Derived case: Fsy NaN -> Fty/sqrt(3) = 49,074.8 psi
            s = engine.shearYieldStrength(model.Material(Name="A286", Fty=85000));
            testCase.verifyEqual(s.Fsy, 85000/sqrt(3), "AbsTol", 1e-9);
            testCase.verifyEqual(s.Fsy, 49074.8, "AbsTol", 0.1);
            testCase.verifyTrue(s.Derived);
            testCase.verifySubstring(s.Basis, "von Mises");
            % 300-series CRES cross-check: 30000/sqrt(3) = 17,320.5 psi
            s = engine.shearYieldStrength(model.Material(Name="CRES", Fty=30000));
            testCase.verifyEqual(s.Fsy, 17320.5, "AbsTol", 0.1);
            % Neither Fsy nor Fty -> NaN (caller reports NotEvaluated)
            s = engine.shearYieldStrength(model.Material(Name="unset"));
            testCase.verifyTrue(isnan(s.Fsy));
            testCase.verifyFalse(s.Derived);
        end

        function insertAreaYieldGovernsSuppliedFsy(testCase)
            % HAND-DERIVED area-path pin, yield governing, Fsy SUPPLIED.
            % Fixture (insertJoint below, same loads as
            % insertUsesHelicoilRating): PpMax = 1,250 lb, PtL = 1,000 lb,
            % n = 1, phi = 1 (threaded-in). Design loads per 5020B Eq. 8
            % form, each criterion with ITS OWN factor pair (thread-family
            % convention — factors inside Pb, external term only):
            %   Pb      = 1250 + 1.15*1.4*1000  = 2,860 lb   (ultimate)
            %   PbYield = 1250 + 1.0*1.25*1000  = 2,500 lb   (yield)
            % Area provenance: 0.1121 in^2 is the #10-32 x 1.5D parent-side
            % shear engagement area ((5/8)*pi*Le*D = 0.11214 in^2, see
            % insertUsesHelicoilRating). Parent Al 6061-T651: Fsu = 27,000,
            % Fty = 36,000 psi (same handbook values as
            % tappedParentMatchesDABJ6a); Fsy = 20,000 psi is a synthetic
            % supplied pin. DABJ default factors FFU 1.15, FSU 1.4,
            % FFY 1.0, FSY 1.25:
            %   ult: 0.1121*27000/2860 - 1 = 3026.7/2860.0 - 1 = +0.0583
            %   yld: 0.1121*20000/2500 - 1 = 2242.0/2500.0 - 1 = -0.1032
            %        <- governs (worst)
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            [j, lc, fac] = insertJoint(parent, 0.1121, 0);
            p = engine.preload(j);
            r = engine.marginInsert(j, lc, fac, p);
            testCase.verifyEqual(r.Pb, 2860, "AbsTol", 1e-9);
            testCase.verifyEqual(r.PbYield, 2500, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Pult, 3026.7, "AbsTol", 1e-9);
            testCase.verifyEqual(r.AllowYld, 2242.0, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, -0.1032, "AbsTol", 1e-3);
            testCase.verifySubstring(r.Method, "4.4.1");
            testCase.verifySubstring(r.Method, "shear engagement area");
            testCase.verifySubstring(r.Detail, "yield");
            % Supplied Fsy must be flagged as supplied, not estimated
            testCase.verifySubstring(r.Detail, "supplied");
        end

        function insertAreaDerivedFsyFlagged(testCase)
            % Same fixture, Fsy NaN -> derived Fsy = Fty/sqrt(3)
            % = 36000/sqrt(3) = 20,784.6 psi (von Mises), and the Detail
            % MUST say the value is an estimate:
            %   yld: 0.1121*20784.6/2500 - 1
            %        = 2330.0/2500.0 - 1 = -0.0680   <- governs
            %   (ult unchanged at 3026.7/2860 - 1 = +0.0583)
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000);   % Fsy NaN -> von Mises estimate
            [j, lc, fac] = insertJoint(parent, 0.1121, 0);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.AllowYld, 0.1121*36000/sqrt(3), "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, -0.068018, "AbsTol", 1e-3);
            testCase.verifySubstring(r.Detail, "yield");
            testCase.verifySubstring(r.Detail, "von Mises");
            testCase.verifySubstring(r.Detail, "estimated");
        end

        function insertAreaUltimateGoverns(testCase)
            % Worst-of-two the other way: a HIGH supplied Fsy = 30,000 psi
            % makes yield pass ultimate, so ULTIMATE governs:
            %   yld: 0.1121*30000/2500 - 1
            %        = 3363.0/2500.0 - 1 = +0.3452
            %   ult: 0.1121*27000/2860 - 1
            %        = 3026.7/2860.0 - 1 = +0.0583   <- governs (worst)
            parent = model.Material(Name="Al 6061-T651 (high Fsy pin)", ...
                Ftu=42000, Fty=36000, Fsu=27000, Fsy=30000);
            [j, lc, fac] = insertJoint(parent, 0.1121, 0);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.MS, 0.058287, "AbsTol", 1e-3);
            testCase.verifySubstring(r.Detail, "ultimate");
        end

        function insertRatingNotLimiting(testCase)
            % CEILING, not-limiting side: with BOTH a shear engagement area
            % and a rated pull-out set, the ultimate allowable is the
            % LOWER of the two (5020B: "the lower value should be used for
            % strength analysis"). Here the computed allowable
            % 0.1121*27000 = 3,026.7 lb is far below the 12,949 lb rating
            % (insertUsesHelicoilRating fixture value), so the area form
            % stands and the numbers match insertAreaYieldGovernsSuppliedFsy
            % (MS = 2242/2500 - 1 = -0.1032, yield governing); the rating
            % must NOT drive the margin (it would give
            % 12949/2860 - 1 = +3.53) and Detail says it is not limiting.
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            [j, lc, fac] = insertJoint(parent, 0.1121, 12949);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.MS, -0.1032, "AbsTol", 1e-3);
            testCase.verifyEqual(r.Pult, 3026.7, "AbsTol", 1e-9);
            testCase.verifySubstring(r.Method, "shear engagement area");
            testCase.verifySubstring(r.Detail, "not limiting");
            testCase.verifyEqual(r.Rating, 12949);   % rating seen (as ceiling), not the basis
        end

        function insertRatingCeilingGoverns(testCase)
            % CEILING, governing side: a rating BELOW the computed ultimate
            % allowable caps it (lower-of), ultimate criterion only:
            %   ult allowable = min(0.1121*27000, 2500)
            %                 = min(3026.7, 2500) = 2,500 lb (rating)
            %   ult: 2500/2860 - 1 = -0.1259   <- governs (worst)
            %   yld: 0.1121*20000/2500 - 1 = 2242.0/2500.0 - 1 = -0.1032
            %        (NOT capped — the rating is an ultimate quantity,
            %         see marginInsert header)
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            [j, lc, fac] = insertJoint(parent, 0.1121, 2500);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.Pult, 2500, "AbsTol", 1e-9);  % effective ult allowable = rating
            testCase.verifyEqual(r.AllowYld, 2242.0, "AbsTol", 1e-9);  % yield NOT capped
            testCase.verifyEqual(r.MS, 2500/2860 - 1, "AbsTol", 1e-12);  % -0.125874
            testCase.verifyEqual(r.Rating, 2500);
            testCase.verifySubstring(r.Detail, "ultimate");
            testCase.verifySubstring(r.Detail, "GOVERNS");
        end

        function insertFlatRatingFallbackRegression(testCase)
            % REGRESSION GUARD: with ShearEngagementArea NaN (and parent
            % Fsy NaN), the flat-rating path must be BIT-IDENTICAL to the
            % pre-Fsy implementation — the exact insertUsesHelicoilRating
            % fixture: rating 12,949 lb, Pb = 2,860 lb,
            %   MS = 12949/2860 - 1 = +3.527622  (same expression, same
            % floating-point operation order as the engine's rating/Pb - 1).
            parent = model.Material(Name="Nitronic 60");   % strengths all NaN, as today
            [j, lc, fac] = insertJoint(parent, NaN, 12949);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.Pb, 2860, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, 12949/2860 - 1, "AbsTol", 1e-12);
            testCase.verifyEqual(r.Rating, 12949);
            testCase.verifySubstring(r.Method, "rated pull-out");
            % The two bases must be distinguishable from Method
            testCase.verifyFalse(contains(r.Method, "shear engagement area"));
        end

        function insertAreaNaNParentNotEvaluated(testCase)
            % Area set but parent strengths missing -> NotEvaluated with
            % the reason, never a throw, and NO silent fallback to the
            % flat rating (even when one is set).
            % (a) parent has NO strengths at all (Fsu, Fty, Fsy all NaN)
            [j, lc, fac] = insertJoint(model.Material(Name="unset"), 0.1121, 12949);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifySubstring(r.Detail, "Not evaluated");
            testCase.verifySubstring(r.Detail, "Fsu");
            % (b) Fsu present but Fty/Fsy both NaN -> yield criterion
            % impossible -> still NotEvaluated (no silent ultimate-only)
            [j, lc, fac] = insertJoint( ...
                model.Material(Name="Fsu only", Fsu=27000), 0.1121, 0);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifySubstring(r.Detail, "Fsy");
        end

        % ================================================================
        % Insert COMPUTED area from STI catalogue geometry (labelled
        % fallback beneath the specified area, above the flat rated-load
        % basis) — As = 0.75*pi*D2*(Le-1.125*p), the NASM33537/TM-106943
        % form, see engine.marginInsert / memberTensileUltAllowable headers.
        % ================================================================

        function insertComputedAreaGovernsWhenUnspecified(testCase)
            % No ShearEngagementArea supplied, but StiPitchDiameter and the
            % engagement length both resolve -> the COMPUTED area governs
            % (labelled fallback beneath "specified", above the flat rating).
            % Fixture: same #10-32 Heli-Coil loads as insertJoint (PpMax =
            % 1,250 lb, PtL = 1,000 lb, n = 1, phi = 1), D2 = 0.2000 in
            % (illustrative -- NOT a real NASM33537 value; the real seeded
            % catalogue values are exercised by
            % insertStiPitchDiameterResolvesPerRow in tests/tBoltSizing.m),
            % Le = 0.3000 in, TPI = 32 -> p = 1/32 = 0.031250 in:
            %   1.125*p  = 1.125*0.031250       = 0.035156 in
            %   netLe    = 0.3000 - 0.035156     = 0.264844 in
            %   As       = 0.75*pi*0.2000*0.264844 = 0.124805 in^2
            % Parent Al 6061-T651: Fsu = 27,000, Fsy = 20,000 psi (same
            % values as insertAreaYieldGovernsSuppliedFsy, so only the area
            % SOURCE differs from that test, not the parent strengths).
            % Design loads (5020B Eq. 8 form, ultimate/yield factor pairs):
            %   Pb      = 1250 + 1.15*1.4*1000  = 2,860 lb
            %   PbYield = 1250 + 1.0*1.25*1000  = 2,500 lb
            %   ult: 0.124805*27000/2860 - 1 = 3369.73/2860.0 - 1 = +0.17823
            %   yld: 0.124805*20000/2500 - 1 = 2496.09/2500.0 - 1 = -0.00156
            %        <- governs (worst)
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            [j, lc, fac] = insertJointSti(parent, 0.2000, 0.3000, 0, NaN);
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 1250, "AbsTol", 1e-9);
            r = engine.marginInsert(j, lc, fac, p);
            expectedAs = 0.75 * pi * 0.2000 * (0.3000 - 1.125 * (1/32));
            testCase.verifyEqual(r.As, expectedAs, "AbsTol", 1e-9);
            testCase.verifyEqual(r.As, 0.124805, "AbsTol", 1e-5);
            testCase.verifyEqual(r.Pb, 2860, "AbsTol", 1e-9);
            testCase.verifyEqual(r.PbYield, 2500, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Pult, expectedAs * 27000, "AbsTol", 1e-6);
            testCase.verifyEqual(r.AllowYld, expectedAs * 20000, "AbsTol", 1e-6);
            testCase.verifyEqual(r.MS, expectedAs * 20000 / 2500 - 1, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, -0.00156, "AbsTol", 1e-4);
            testCase.verifySubstring(r.Detail, "yield");
            % The area SOURCE must be visible and flagged as derived, not
            % silently indistinguishable from a specified area.
            testCase.verifySubstring(r.Detail, "computed (DERIVED)");
            testCase.verifySubstring(r.Detail, "NASM33537");
            testCase.verifyFalse(contains(r.Detail, "specified"));
            % Method is the check's STATIC description and deliberately
            % names BOTH area sources ("...SPECIFIED... else COMPUTED...");
            % which one actually ran is Detail's job, asserted above. So
            % what Method owes is the CITATION, per CLAUDE.md's
            % traceability rule — assert that, not a per-run marker.
            testCase.verifySubstring(r.Method, "NASM33537 Rev 4 Table IV");
            testCase.verifySubstring(r.Method, "TM-106943 Eq. 78/79");
        end

        function insertSuppliedAreaWinsOverCatalogueGeometry(testCase)
            % Both a ShearEngagementArea AND a StiPitchDiameter are set --
            % the SPECIFIED area must still win outright (precedence (a)
            % over (b)), reproducing insertAreaYieldGovernsSuppliedFsy's
            % exact numbers (As = 0.1121 in^2, MS = -0.1032) even though the
            % catalogue geometry (D2 = 0.2000, Le = 0.3000) would otherwise
            % compute a different area (0.124805 in^2, see
            % insertComputedAreaGovernsWhenUnspecified).
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            [j, lc, fac] = insertJointSti(parent, 0.2000, 0.3000, 0, 0.1121);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyEqual(r.As, 0.1121, "AbsTol", 1e-12);
            testCase.verifyEqual(r.Pult, 3026.7, "AbsTol", 1e-9);
            testCase.verifyEqual(r.AllowYld, 2242.0, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, -0.1032, "AbsTol", 1e-3);
            testCase.verifySubstring(r.Detail, "specified");
            testCase.verifyFalse(contains(r.Detail, "computed (DERIVED)"));
        end

        function insertComputedAreaRatingStillCaps(testCase)
            % The rating-as-ceiling rule applies to the COMPUTED area
            % exactly as it does to a specified one. Same geometry as
            % insertComputedAreaGovernsWhenUnspecified (As = 0.124805 in^2,
            % uncapped ultimate allowable 3,369.73 lb), now with a rating
            % of 2,500 lb BELOW that:
            %   ult allowable = min(3369.73, 2500) = 2,500 lb (rating GOVERNS)
            %   ult: 2500/2860 - 1 = -0.12587   <- governs (worst)
            %   yld: 0.124805*20000/2500 - 1 = -0.00156 (NOT capped -- the
            %        rating is an ultimate quantity, unaffected by area source)
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            [j, lc, fac] = insertJointSti(parent, 0.2000, 0.3000, 2500, NaN);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            expectedAs = 0.75 * pi * 0.2000 * (0.3000 - 1.125 * (1/32));
            testCase.verifyEqual(r.As, expectedAs, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Pult, 2500, "AbsTol", 1e-9);   % capped ultimate
            testCase.verifyEqual(r.AllowYld, expectedAs * 20000, "AbsTol", 1e-6);   % NOT capped
            testCase.verifyEqual(r.MS, 2500/2860 - 1, "AbsTol", 1e-9);
            testCase.verifyEqual(r.Rating, 2500);
            testCase.verifySubstring(r.Detail, "ultimate");
            testCase.verifySubstring(r.Detail, "GOVERNS");
            testCase.verifySubstring(r.Detail, "computed (DERIVED)");
        end

        function insertUncataloguedSizeVsIncompleteConfigRefusal(testCase)
            % Two DIFFERENT NotEvaluated reasons must never be conflated --
            % an analyst reading (a) must not conclude they simply forgot
            % to enter an area (there is nothing to enter for that size),
            % and an analyst reading (b) must not conclude the size has no
            % insert available (it does; the engagement length is just
            % unconfigured).
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            % (a) StiPitchDiameter NaN (default) -- e.g. #0-80/#5-44, for
            % which no helical insert is catalogued at all. No specified
            % area, no rating either.
            [j, lc, fac] = insertJointSti(parent, NaN, 0.3000, 0, NaN);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifySubstring(r.Detail, "no insert is catalogued for this thread size");
            testCase.verifyFalse(contains(r.Detail, "engagement length could not be resolved"));
            % (b) StiPitchDiameter SET (the size IS catalogued) but the
            % engagement length is unconfigured (EngagementLength AND
            % EngagementRatio both NaN). Distinct reason, no area, no rating.
            [j2, lc2, fac2] = insertJointSti(parent, 0.2000, NaN, 0, NaN);
            r2 = engine.marginInsert(j2, lc2, fac2, engine.preload(j2));
            testCase.verifyTrue(isnan(r2.MS));
            testCase.verifySubstring(r2.Detail, "engagement length");
            testCase.verifySubstring(r2.Detail, "could not be resolved");
            testCase.verifyFalse(contains(r2.Detail, "no insert is catalogued"));
        end

        function insertComputedAreaGuardRefusesNonPositiveArea(testCase)
            % Le - 1.125*p <= 0 must refuse, never emit a negative/zero
            % area. D2 = 0.2000, Le = 0.0200, TPI = 32 -> p = 0.031250:
            %   1.125*p = 0.035156 > Le(0.0200) -> netLe = -0.015156 <= 0
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, Fsy=20000);
            % (a) No rating either -> NotEvaluated with the guard reason,
            % never a crash and never a negative/zero As.
            [j, lc, fac] = insertJointSti(parent, 0.2000, 0.0200, 0, NaN);
            r = engine.marginInsert(j, lc, fac, engine.preload(j));
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifyTrue(isnan(r.As));
            testCase.verifySubstring(r.Detail, "does not exceed");
            % (b) A rating IS set -> the guard silently defers to the flat
            % rated basis (precedence (c)), exactly as any other
            % unresolved-area case does. Pb = 2,860 lb (same loads):
            %   MS = 5000/2860 - 1 = +0.74825
            [j2, lc2, fac2] = insertJointSti(parent, 0.2000, 0.0200, 5000, NaN);
            r2 = engine.marginInsert(j2, lc2, fac2, engine.preload(j2));
            testCase.verifyEqual(r2.MS, 5000/2860 - 1, "AbsTol", 1e-9);
            testCase.verifyEqual(r2.Rating, 5000);
            testCase.verifySubstring(r2.Method, "rated pull-out");
            testCase.verifyFalse(contains(r2.Method, "shear engagement area"));
        end

        % ================================================================
        % Fig. 8 separation-before-rupture gate — the four thread rows'
        % design load must branch on the SAME gate engine.marginTensionUlt
        % reports (engine.boltDesignLoad, via the shared private helper
        % separationBeforeRuptureGate).
        % ================================================================

        function tappedParentGateAssuredSeparatedLoad(testCase)
            % Gate ASSURED (all of Fig. 8 holds) -> the design load must be
            % the SEPARATED form Pb = FFU*FSU*PtL (no preload, no n*phi),
            % NOT the clamped Pb = PpMax + FFU*FSU*n*phi*PtL. Same #10-32
            % tapped-hole geometry as tappedParentMatchesDABJ6a (As/Pult
            % unaffected by the branch), plus a FlangeStack and
            % BoltRatedUltimateLoad so the gate can be assessed, and
            % LoadingPlaneFactor = 0.5 (<= 0.9, satisfies condition 3):
            %   Eb = 29.1e6 (bolt A-286), Ec = 9.9e6 (Al 6061-T651 parent
            %     doubling as the flange) -> Ec(9.9e6) > Eb/3(9.7e6):
            %     condition 1 holds.
            %   Tapped-hole allowable (memberTensileUltAllowable, TM-106943
            %   Eq. 79): As = 0.75*pi*0.1697*0.250 = 0.099962 in^2,
            %     AllowUlt = 27000*As = 2,698.96 lbf. System
            %     Ptu_allow = min(BoltRatedUltimateLoad 15,200, 2,698.96)
            %     = 2,698.96 lbf (the tapped hole governs).
            %   PpMax = 400*1.25 = 500 lbf < 0.75*2,698.96 = 2,024.2:
            %     condition 2 holds. n = 0.5 <= 0.9: condition 3 holds.
            %     -> gate ASSURED.
            %   PtL = 5,000 lbf, FFU = 1.15, FSU = 1.4 (DABJ defaults):
            %     Pb = FFU*FSU*PtL = 1.61*5,000 = 8,050 lbf  (SEPARATED)
            %     MS = 2,698.96/8,050 - 1 = -0.6647
            %   (contrast tappedParentGateNotAssuredClampedLoad below, same
            %   As/Pult but the OLD clamped form, Pb = 6,525 lbf, MS =
            %   -0.5864 — a materially different, LESS conservative number
            %   for the same failure mode).
            b = model.Bolt(Designation="#10-32 UNF (gate pin)", ...
                NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
                ThreadsPerInch=32, TensileStressArea=0.0200, ...
                MinorDiameter=0.156, PitchDiameter=0.1697);
            bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
                Fsu=95000, E=29.1e6);
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, E=9.9e6);
            j = model.Joint(Name="Gate-assured tapped joint", ...
                Bolt=b, BoltMaterial=bm, ...
                FlangeStack=[model.FlangeLayer(Material=parent, Thickness=0.5)], ...
                BoltRatedUltimateLoad=15200, ...
                LoadingPlaneFactor=0.5, ...
                ThreadedMember=model.ThreadedMember( ...
                    Type=model.ThreadedMemberType.TappedHole, ...
                    Material=parent, EngagementLength=0.250), ...
                PreloadSpec=model.PreloadSpec( ...
                    Method=model.PreloadMethod.DirectPreload, ...
                    NominalPreload=400, Uncertainty=0.25));
            lc  = model.LoadCase(Name="gate-assured pull-out", ...
                BoltTensileLimitLoad=5000, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults: FFU 1.15, FSU 1.4
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 500, "AbsTol", 1e-9);
            r = engine.marginTappedParentThread(j, lc, fac, p);
            expectedAs   = 0.75*pi*0.1697*0.250;
            expectedPult = 27000*expectedAs;
            testCase.verifyEqual(r.As,   expectedAs,   "AbsTol", 1e-9);
            testCase.verifyEqual(r.Pult, expectedPult, "AbsTol", 1e-6);
            % SEPARATED branch: Pb = FFU*FSU*PtL exactly, no preload/n*phi
            testCase.verifyEqual(r.Pb, 8050, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, expectedPult/8050 - 1, "AbsTol", 1e-9);
            testCase.verifySubstring(r.Detail, "SEPARATED");
            testCase.verifySubstring(r.Detail, "assured");
        end

        function tappedParentGateNotAssuredClampedLoad(testCase)
            % Same fixture, but the preload is raised enough to fail the
            % Fig. 8 preload condition (PpMax <= 0.75*Ptu_allow) while the
            % stiffness and loading-plane conditions still hold -> gate
            % ASSESSED but NOT assured (rupture assumed) -> the row must
            % still use the UNCHANGED clamped form, Pb = PpMax +
            % FFU*FSU*n*phi*PtL, with phi = 1 (threaded-in assumption):
            %   PpMax = 2,000*1.25 = 2,500 lbf >= 0.75*2,698.96 = 2,024.2:
            %     the preload condition fails -> gate NOT assured.
            %   Pb = 2,500 + 1.15*1.4*0.5*1*5,000 = 2,500 + 4,025
            %      = 6,525 lbf                          (CLAMPED, unchanged)
            %   MS = 2,698.96/6,525 - 1 = -0.5864
            b = model.Bolt(Designation="#10-32 UNF (gate pin)", ...
                NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
                ThreadsPerInch=32, TensileStressArea=0.0200, ...
                MinorDiameter=0.156, PitchDiameter=0.1697);
            bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
                Fsu=95000, E=29.1e6);
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, E=9.9e6);
            j = model.Joint(Name="Gate-not-assured tapped joint", ...
                Bolt=b, BoltMaterial=bm, ...
                FlangeStack=[model.FlangeLayer(Material=parent, Thickness=0.5)], ...
                BoltRatedUltimateLoad=15200, ...
                LoadingPlaneFactor=0.5, ...
                ThreadedMember=model.ThreadedMember( ...
                    Type=model.ThreadedMemberType.TappedHole, ...
                    Material=parent, EngagementLength=0.250), ...
                PreloadSpec=model.PreloadSpec( ...
                    Method=model.PreloadMethod.DirectPreload, ...
                    NominalPreload=2000, Uncertainty=0.25));
            lc  = model.LoadCase(Name="gate-not-assured pull-out", ...
                BoltTensileLimitLoad=5000, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults: FFU 1.15, FSU 1.4
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 2500, "AbsTol", 1e-9);
            r = engine.marginTappedParentThread(j, lc, fac, p);
            expectedAs   = 0.75*pi*0.1697*0.250;
            expectedPult = 27000*expectedAs;
            testCase.verifyEqual(r.As,   expectedAs,   "AbsTol", 1e-9);
            testCase.verifyEqual(r.Pult, expectedPult, "AbsTol", 1e-6);
            % CLAMPED branch (unchanged): Pb = PpMax + FFU*FSU*n*phi*PtL
            testCase.verifyEqual(r.Pb, 6525, "AbsTol", 1e-9);
            testCase.verifyEqual(r.MS, expectedPult/6525 - 1, "AbsTol", 1e-9);
            testCase.verifySubstring(r.Detail, "CLAMPED");
            testCase.verifySubstring(r.Detail, "not assured");
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

function [j, lc, fac] = nutJoint(nutMat, rating, area)
%NUTJOINT  The Ex 8-b Nut fixture used by the nut-strength tests
%   (nutStrengthHandDerived geometry and loads), parameterised on the NUT
%   material, the spec-rated ultimate load (0 -> unset), and a supplied
%   ShearEngagementArea (NaN -> computed 0.75·pi·E·Le). PpMax = 2,500 lb,
%   PtL = 3,000 lb, n = 0.5. This fixture's FlangeStack + the derived bolt
%   allowable (boltTensileAllowable, At*Ftu = 14,048 lbf) make the
%   NASA-STD-5020B Fig. 8 gate assessable, and it genuinely comes back
%   ASSURED for every caller of this helper (see
%   boltThreadShearHandDerived for the full condition derivation), so the
%   design loads used by every test built on this fixture are the
%   SEPARATED form (no preload, no n*phi -- the real stiffness phi = 0.3354
%   from tStiffness/dabjExample8b is resolved but not used by this branch):
%     Pb      = FFU*FSU*PtL = 1.15*1.4*3000 = 4,830 lb
%     PbYield = FFY*FSY*PtL = 1.0*1.25*3000 = 3,750 lb
c = validation.dabjExample8b();
j = c.Joint;
j.Bolt.PitchDiameter = 0.3479;            % 3/8-24 UNF basic pitch dia, in
j.ThreadedMember.EngagementLength = 0.375;
j.ThreadedMember.Material = nutMat;
j.ThreadedMember.RatedUltimateLoad = rating;
j.ThreadedMember.ShearEngagementArea = area;
j.PreloadSpec = model.PreloadSpec( ...
    Method         = model.PreloadMethod.DirectPreload, ...
    NominalPreload = 2000, ...
    Uncertainty    = 0.25);               % PpMax = 1.25*2000 = 2,500 lb
lc  = model.LoadCase(Name="nut-strength pin", ...
    BoltTensileLimitLoad=3000, BoltShearLimitLoad=0);
fac = model.Factors();   % DABJ defaults: FFU 1.15, FSU 1.4, FFY 1.0, FSY 1.25
end

function [j, lc, fac] = insertJoint(parent, area, rating)
%INSERTJOINT  The #10-32 Heli-Coil insert fixture (insertUsesHelicoilRating
%   geometry and loads), parameterised on the PARENT material, the shear
%   engagement area (NaN -> flat-rating path), and the flat rated pull-out.
%   Loads give Pb = 1250 + 1.15*1.4*1*1*1000 = 2,860 lb and
%   PbYield = 1250 + 1.0*1.25*1*1*1000 = 2,500 lb (5020B Eq. 8 form with
%   the ultimate / yield factor pairs; phi = 1 threaded-in assumption;
%   DABJ default factors).
b = model.Bolt(Designation="#10-32 UNF", ...
    NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
    ThreadsPerInch=32, TensileStressArea=0.0200, ...
    MinorDiameter=0.156, PitchDiameter=0.1697);
bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
    Fsu=95000, E=29.1e6);
j = model.Joint(Name="Heli-Coil insert joint", ...
    Bolt=b, BoltMaterial=bm, ...
    ThreadedMember=model.ThreadedMember( ...
        Type=model.ThreadedMemberType.Insert, ...
        Material=parent, RatedUltimateLoad=rating, ...
        ShearEngagementArea=area, EngagementLength=0.3006), ...
    PreloadSpec=model.PreloadSpec( ...
        Method=model.PreloadMethod.DirectPreload, ...
        NominalPreload=1000, Uncertainty=0.25));
lc  = model.LoadCase(Name="insert pull-out", ...
    BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
fac = model.Factors();   % DABJ defaults: FFU 1.15, FSU 1.4, FFY 1.0, FSY 1.25
end

function [j, lc, fac] = insertJointSti(parent, D2, Le, rating, area)
%INSERTJOINTSTI  The #10-32 Heli-Coil insert fixture (SAME geometry/loads
%   as insertJoint: Pb = 2,860 lb, PbYield = 2,500 lb), parameterised on the
%   PARENT material, StiPitchDiameter (NaN -> uncatalogued-size refusal),
%   the engagement length (NaN -> unresolved-geometry refusal), the flat
%   rated pull-out, and -- unlike insertJoint -- an EXPLICIT
%   ShearEngagementArea (NaN in every COMPUTED-area test below; a caller
%   passes a real value only to prove the specified area still overrides
%   the catalogue geometry, insertSuppliedAreaWinsOverCatalogueGeometry).
b = model.Bolt(Designation="#10-32 UNF", ...
    NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
    ThreadsPerInch=32, TensileStressArea=0.0200, ...
    MinorDiameter=0.156, PitchDiameter=0.1697);
bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
    Fsu=95000, E=29.1e6);
j = model.Joint(Name="Heli-Coil insert joint (computed area)", ...
    Bolt=b, BoltMaterial=bm, ...
    ThreadedMember=model.ThreadedMember( ...
        Type=model.ThreadedMemberType.Insert, ...
        Material=parent, RatedUltimateLoad=rating, ...
        ShearEngagementArea=area, StiPitchDiameter=D2, ...
        EngagementLength=Le), ...
    PreloadSpec=model.PreloadSpec( ...
        Method=model.PreloadMethod.DirectPreload, ...
        NominalPreload=1000, Uncertainty=0.25));
lc  = model.LoadCase(Name="insert pull-out (computed area)", ...
    BoltTensileLimitLoad=1000, BoltShearLimitLoad=0);
fac = model.Factors();   % DABJ defaults: FFU 1.15, FSU 1.4, FFY 1.0, FSY 1.25
end
