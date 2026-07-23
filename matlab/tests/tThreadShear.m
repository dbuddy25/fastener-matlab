classdef tThreadShear < matlab.unittest.TestCase
    %TTHREADSHEAR  Phase 3.3 acceptance: the four thread-strength checks —
    %   engine.marginBoltThreadShear (TM-106943 Eq. 63/64/65 basis),
    %   engine.marginNutStrength (Eq. 76/77 + Eq. 65),
    %   engine.marginTappedParentThread (Eq. 79 + Eq. 65), and
    %   engine.marginInsert (Heli-Coil rated pull-out, 5020B §4.4.1) —
    %   all using the GROUP'S thread-shear area As = 0.75·pi·E·Le
    %   (E = pitch diameter, Le = engagement length) and the design bolt
    %   load Pb = PpMax + FFU·FSU·n·phi·PtL (NASA-STD-5020B Eq. 8 form,
    %   engine.boltDesignLoad; phi = 1 assumed for threaded-in configs).
    %
    %   Validation strategy (VALIDATION.md rows 7-9, 14): the tapped-parent
    %   AREA and ALLOWABLE are cross-checked against DABJ Example 6-a (the
    %   only public thread pull-out example); every MS is pinned with
    %   HAND-DERIVED arithmetic documented inline. The DABJ §9 answer key
    %   is re-run through analyze() to prove Phase 3.3 does not disturb it.
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
            % 27,000 * 0.0986 = 2,660 lb. The GROUP'S pitch-diameter form:
            %   As   = 0.75*pi*E*Le = 0.75*pi*0.1697*0.250 = 0.09996 in^2
            %   Pult = 27000*0.09996 = 2,699 lb
            % both within 1.5% of the book (RelTol 0.03 asserted).
            % NOTE: DABJ then applies a 0.70 judgment knockdown -> 1,860 lb;
            % the group's method does NOT knock down, so the cross-check is
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
            % Exact-arithmetic pins of the group form itself
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
            % phi = 0.3358, tStiffness). Add the Phase 3.3 thread inputs:
            % E = 0.3479 in (3/8-24 UNF basic pitch dia), Le = 0.375 in.
            % Direct preload 2,000 lb, Gamma = 0.25, no thermal
            % -> PpMax = 2,500 lb; PtL = 3,000 lb; n = 0.5 (fixture);
            % DABJ default factors FFU = 1.15, FSU = 1.4:
            %   As   = 0.75*pi*0.3479*0.375 = 0.30740 in^2
            %   Pult = 95000*0.30740 = 29,202.5 lb          (bolt Fsu)
            %   Pb   = 2500 + 1.15*1.4*0.5*0.3358*3000 = 3,311.0 lb
            %   MS   = 29202.5/3311.0 - 1 = +7.820
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
            testCase.verifyEqual(r.MS,   7.820,    "AbsTol", 0.01);
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
            % internal side would govern over the bolt-external side:
            %   As   = 0.75*pi*0.3479*0.375 = 0.30740 in^2   (same area)
            %   Pult = 60000*0.30740 = 18,443.7 lb           (NUT Fsu)
            %   Pb   = 2500 + 1.15*1.4*0.5*0.3358*3000 = 3,311.0 lb
            %   MS   = 18443.7/3311.0 - 1 = +4.570
            c = validation.dabjExample8b();
            j = c.Joint;
            j.Bolt.PitchDiameter = 0.3479;
            j.ThreadedMember.EngagementLength = 0.375;
            j.ThreadedMember.Material = model.Material( ...
                Name="Soft nut (pin fixture)", Fsu=60000);
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0.25);
            lc  = model.LoadCase(Name="nut-strength pin", ...
                BoltTensileLimitLoad=3000, BoltShearLimitLoad=0);
            fac = model.Factors();   % DABJ defaults
            p = engine.preload(j);
            r = engine.marginNutStrength(j, lc, fac, p);
            testCase.verifyEqual(r.Pult, 18443.7, "RelTol", 0.001);
            testCase.verifyEqual(r.MS,   4.570,   "AbsTol", 0.01);
            testCase.verifySubstring(r.Method, "Eq. 76");
            % Not a nut -> NotEvaluated, not a crash
            j2 = j;
            j2.ThreadedMember.Type = model.ThreadedMemberType.TappedHole;
            r2 = engine.marginNutStrength(j2, lc, fac, engine.preload(j2));
            testCase.verifyTrue(isnan(r2.MS));
        end

        function insertUsesHelicoilRating(testCase)
            % Insert margin = MANUFACTURER rated pull-out / Pb - 1 (the
            % group's method: one spec value, no thread-shear calc).
            % Fixture rating provenance: the Heli-Coil Catalogue (Emhart
            % Teknologies Bulletin 2003) tabulates NO numeric pull-out
            % loads (it defers to Heli-Coil Technical Bulletin 68-2); its
            % only strength figure is the insert wire tensile strength —
            % Nitronic 60, UNS S21800, Ftu = 200,000 psi (catalogue p. 7).
            % The fixture rating is the catalogue-anchored derived value
            % for a #10-32 x 1.5D free-running insert (matches the Python
            % tool's NASM33537-0190-32-1.5D seeded Pult_external):
            %   Fsu = 200000/sqrt(3) = 115,470 psi (von Mises)
            %   Le  = Q = 1.5*0.190 + p/2 = 0.3006 in
            %   As  = (5/8)*pi*Le*0.190 = 0.11214 in^2 (parent-side area)
            %   rating = 115470*0.11214 = 12,949 lb
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
            testCase.verifyEqual(row(r, "Interaction").MS, ...
                c.Expected.MS_Interaction, "AbsTol", tol);
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
    end
end

% ---- Local helpers --------------------------------------------------------
function e = row(r, name)
%ROW  Look up one Margins row by Name from an engine.Result.
mask = [r.Margins.Name] == name;
assert(nnz(mask) == 1, "margin ""%s"" not found exactly once", name);
e = r.Margins(mask);
end
