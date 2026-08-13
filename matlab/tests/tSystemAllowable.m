classdef tSystemAllowable < matlab.unittest.TestCase
    %TSYSTEMALLOWABLE  The fastening-system tensile allowable (5020B §4.4.1).
    %   engine.systemTensileAllowable returns Ptu-allow as NASA-STD-5020B
    %   §4.4.1 defines it — "the allowable ultimate load for the FASTENING
    %   SYSTEM", the minimum over bolt tension and the internal-thread
    %   member's tensile mode — and engine.marginTensionUlt consumes it in
    %   the Fig. 8 preload gate (PpMax <= 0.75·Ptu_allow) and in both margin
    %   equations (Eq. 6 assured / Eq. 10 rupture).
    %
    %   Every expected number is HAND-DERIVED with its arithmetic inline
    %   (sources cited per test), and the DABJ §9 answer key is re-run to
    %   prove the system allowable does not disturb it: on that fixture the
    %   nut is rated at the bolt's 15,200 lbf ("nuts as strong as the
    %   bolts", dabjSection9 p. 9-6), so the system minimum IS the bolt
    %   allowable.
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
        function dabjSystemIsBoltGoverned(testCase)
            % DABJ §9 fixture (validation.dabjSection9): bolt spec
            % Ptu-allow = 15,200 lbf (p. 9-6) and the nut is rated at the
            % same 15,200 lbf with NO engagement length -> the nut mode
            % assesses on the flat-rating basis (5020B §4.4.1). System:
            %   Ptu_allow = min(15,200 bolt, 15,200 nut) = 15,200 lbf
            % governed by "bolt tension" (tie goes to the first-listed
            % mode), with a COMPLETE assessment (both modes produced a
            % number).
            c = validation.dabjSection9();
            s = engine.systemTensileAllowable(c.Joint);
            testCase.verifyEqual(s.PtuAllow, 15200, "AbsTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "bolt tension");
            testCase.verifyTrue(s.Complete);
            testCase.verifyEmpty(s.Unassessed);
            testCase.verifyEqual(numel(s.Modes), 2);
            % The nut mode row carries the rated 15,200 lbf
            nutRow = s.Modes([s.Modes.Name] == "nut thread shear");
            testCase.verifyEqual(nutRow.Allowable, 15200, "AbsTol", 1e-9);
            testCase.verifyTrue(nutRow.Assessed);
        end

        function dabjAnswerKeyUnchanged(testCase)
            % REGRESSION GUARD (the safety constraint of this change): with
            % Ptu_allow now the SYSTEM allowable, the DABJ §9 answer key
            % must not move — the system minimum resolves to the bolt's
            % 15,200 lbf (see dabjSystemIsBoltGoverned), so the Fig. 8 gate
            % still passes (PpMax 11,070 < 0.75*15,200 = 11,400,
            % Solutions-13/16) and Eq. 6 still gives
            %   MS = 15,200/9,000 - 1 = +0.69 (Solutions-16).
            % WorstMargin stays -0.65 governed by Slip (Solutions-23) and
            % Bearing stays +5.775 (tests/tBearing.m pin).
            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            tol = c.Tol.MarginAbsTol;
            testCase.verifyEqual(row(r, "Tension-Ultimate").MS, ...
                c.Expected.MS_TensionUlt, "AbsTol", tol);        % +0.69
            testCase.verifyEqual(row(r, "Bearing").MS, 5.775, "AbsTol", 0.01);
            testCase.verifyEqual(r.WorstMargin, c.Expected.MS_Slip, ...
                "AbsTol", tol);                                  % -0.65
            testCase.verifyEqual(r.GoverningCheck, "Slip");
            % The gate decision must still read as assured (Narrative pin)
            testCase.verifySubstring(r.Narrative, ...
                "Separation before rupture assured");
            % ... and the COMPLETE §9 assessment must NOT be flagged as
            % incomplete (both modes assessed, see dabjSystemIsBoltGoverned)
            testCase.verifyFalse(contains(r.Narrative, "INCOMPLETE"));
            % Decision names the governing mode of the system allowable
            testCase.verifySubstring(r.Narrative, "bolt tension");
        end

        function nutAreaGovernsSystem(testCase)
            % A nut SOFTER than the bolt must set the system allowable.
            % Ex 8-b joint (validation.dabjExample8b) + Phase 3.3 thread
            % inputs (E = 0.3479 in, the 3/8-24 UNF basic pitch dia;
            % Le = 0.375 in), nut Fsu = 30,000 psi, no rating; bolt rated
            % 15,200 lbf (the §9 spec value). HAND-DERIVED:
            %   As        = 0.75*pi*0.3479*0.375       = 0.307395 in^2
            %             (TM-106943 Eq. 76, pitch-diameter form)
            %   nut allow = 30,000 * 0.307395          = 9,221.86 lbf
            %             (TM-106943 Eq. 77, Pult = Fsu*As)
            %   system    = min(15,200, 9,221.86)      = 9,221.86 lbf
            %             (NASA-STD-5020B §4.4.1 minimum)
            j = tSystemAllowable.softNutJoint(30000, 0, 15200);
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 30000*0.75*pi*0.3479*0.375, ...
                "RelTol", 1e-9);
            testCase.verifyEqual(s.PtuAllow, 9221.86, "AbsTol", 0.5);
            testCase.verifyEqual(s.GoverningMode, "nut thread shear");
            testCase.verifyTrue(s.Complete);
        end

        function nutRatingCapsSystem(testCase)
            % The spec rating is a lower-of CEILING on the computed nut
            % allowable (NASA-STD-5020B §4.4.1, "limited to the load
            % rating of the nut") — same arithmetic the nut margin row uses
            % (memberTensileUltAllowable is shared). HAND-DERIVED:
            %   computed = 30,000 * 0.75*pi*0.3479*0.375 = 9,221.86 lbf
            %   rating 8,000 < computed -> system = min(15,200, 8,000)
            %                                     = 8,000 lbf  (rating caps)
            %   rating 20,000 > computed -> system = min(15,200, 9,221.86)
            %                                      = 9,221.86 lbf (no cap)
            j = tSystemAllowable.softNutJoint(30000, 8000, 15200);
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 8000, "AbsTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "nut thread shear");

            j = tSystemAllowable.softNutJoint(30000, 20000, 15200);
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 30000*0.75*pi*0.3479*0.375, ...
                "RelTol", 1e-9);
        end

        function insertGovernsSystem(testCase)
            % Insert pull-out below the bolt allowable governs the system.
            % #10-32 Heli-Coil fixture (tests/tThreadShear.m insertJoint
            % provenance): shear engagement area 0.1121 in^2, parent
            % Al 6061-T651 Fsu = 27,000 psi, rated pull-out 12,949 lbf;
            % bolt rated 15,200 lbf. HAND-DERIVED (5020B §4.4.1):
            %   computed = 0.1121 * 27,000            = 3,026.7 lbf
            %   rating 12,949 not limiting            -> insert = 3,026.7
            %   system   = min(15,200, 3,026.7)       = 3,026.7 lbf
            j = tSystemAllowable.insertJoint( ...
                model.Material(Name="Al 6061-T651", Ftu=42000, Fty=36000, ...
                    Fsu=27000), 0.1121, 12949, 15200);
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 0.1121*27000, "AbsTol", 1e-9);
            testCase.verifyEqual(s.PtuAllow, 3026.7, "AbsTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "insert pull-out");
            testCase.verifyTrue(s.Complete);

            % Ceiling side: rated pull-out 2,500 < computed 3,026.7 caps
            % the insert mode (lower-of per 5020B): system = 2,500 lbf.
            j = tSystemAllowable.insertJoint( ...
                model.Material(Name="Al 6061-T651", Ftu=42000, Fty=36000, ...
                    Fsu=27000), 0.1121, 2500, 15200);
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 2500, "AbsTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "insert pull-out");
        end

        function tappedParentGovernsSystem(testCase)
            % Tapped-hole parent thread governs a strong bolt in soft
            % aluminum. DABJ Example 6-a geometry (tests/tThreadShear.m
            % tappedParentMatchesDABJ6a): #10-32 (E = 0.1697 in) fully
            % engaged in 0.250-in 6061-T651 (Fsu = 27,000 psi); bolt rated
            % 15,200 lbf. HAND-DERIVED (TM-106943 Eq. 79, pitch-diameter area form):
            %   As     = 0.75*pi*0.1697*0.250 = 0.09996 in^2
            %   parent = 27,000 * 0.09996     = 2,698.96 lbf
            %   system = min(15,200, 2,698.96) = 2,698.96 lbf
            j = tSystemAllowable.tappedJoint(15200);
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 27000*0.75*pi*0.1697*0.250, ...
                "RelTol", 1e-9);
            testCase.verifyEqual(s.PtuAllow, 2698.96, "AbsTol", 0.5);
            testCase.verifyEqual(s.GoverningMode, "tapped-hole parent thread");
            testCase.verifyTrue(s.Complete);
        end

        function weakNutFlipsFig8Gate(testCase)
            % THE POINT OF THE CHANGE: the Fig. 8 preload gate
            % (PpMax <= 0.75·Ptu_allow) must test the SYSTEM allowable. A
            % preload that sits between the two thresholds selects Eq. 6
            % off the bolt's allowable but Eq. 10 off the system's.
            %
            % Ex 8-b joint (real stiffness path, phi = 0.3354 per
            % tests/tStiffness.m -- Kc taken with its exact pi*tan(30 deg)
            % coefficient, not the book's own rounded 1.81), soft nut
            % Fsu = 30,000 psi, bolt rated 15,200 lbf, direct preload
            % 8,000 lbf (zero uncertainty, no thermal). HAND-DERIVED:
            %   system Ptu_allow = 30,000*0.75*pi*0.3479*0.375 = 9,221.86 lbf
            %   BOLT-ONLY gate:  PpMax 8,000 <= 0.75*15,200  = 11,400 -> "assured" (WRONG)
            %   SYSTEM gate:     PpMax 8,000 >  0.75*9,221.86 = 6,916.4 -> rupture (Eq. 10)
            % Rupture branch (NASA-STD-5020B Eq. 10, n = 0.5 fixture):
            %   P'tu = (9,221.86 - 8,000)/(0.5*0.3354) = 1,221.86/0.1677
            %        = 7,287 lbf
            %   Ptu  = 1.15*1.4*2,000 = 3,220 lbf (DABJ default factors)
            %   MS   = 7,287/3,220 - 1 = +1.263
            j = tSystemAllowable.softNutJoint(30000, 0, 15200);
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 8000, ...
                Uncertainty    = 0);      % PpMax = 8,000 exactly
            lc  = model.LoadCase(Name="gate-flip check", ...
                BoltTensileLimitLoad=2000, BoltShearLimitLoad=0);
            fac = model.Factors();        % DABJ defaults: FSU 1.4, FFU 1.15
            p = engine.preload(j);
            testCase.verifyEqual(p.PpMax, 8000, "AbsTol", 1e-9);
            d = engine.designLoads(lc, fac);
            r = engine.marginTensionUlt(j, p, d);
            % The flip itself: below the bolt threshold, at/above the system's
            testCase.verifyLessThan(p.PpMax, 0.75*15200);
            testCase.verifyGreaterThanOrEqual(p.PpMax, ...
                0.75*r.SystemAllowable.PtuAllow);
            testCase.verifyFalse(r.SeparationBeforeRupture);
            testCase.verifySubstring(r.Method, "Eq. 10");   % P'tu
            % The MARGIN is Eq. 7; Eq. 10 only supplies P'tu.
            % A.6 p65: "If rupture would occur before separation, the
            % margin of safety is given by Eq. 7." Pinned so the label
            % cannot drift back — Method is user-visible.
            testCase.verifySubstring(r.Method, "Eq. 7");
            testCase.verifyEqual(r.MS, 1.263, "AbsTol", 0.01);
            % Decision names the governing system mode
            testCase.verifySubstring(r.Decision, "nut thread shear");

            % CONTRAST: same joint and preload with a nut as strong as the
            % bolt (Fsu = 95,000 -> computed 29,202 lbf > 15,200, bolt
            % governs) keeps the gate assured and Eq. 6 applies:
            %   MS = 15,200/3,220 - 1 = +3.72
            j2 = tSystemAllowable.softNutJoint(95000, 0, 15200);
            j2.PreloadSpec = j.PreloadSpec;
            r2 = engine.marginTensionUlt(j2, engine.preload(j2), d);
            testCase.verifyTrue(r2.SeparationBeforeRupture);
            testCase.verifySubstring(r2.Method, "Eq. 6");
            testCase.verifyEqual(r2.MS, 15200/3220 - 1, "AbsTol", 1e-9);
        end

        function incompleteAssessmentFlagged(testCase)
            % A mode that CANNOT be assessed must be reported, not silently
            % dropped from the minimum. Ex 8-b as-shipped has a Nut member
            % with NO rating, NO engagement length, and no pitch diameter
            % on the bolt -> the nut mode has no basis; only the bolt's
            % 10,000 lbf is assessable, so the system minimum covers an
            % INCOMPLETE set (optimistic) and must say so.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.BoltRatedUltimateLoad = 10000;
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 10000, "AbsTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "bolt tension");
            testCase.verifyFalse(s.Complete);
            testCase.verifyEqual(s.Unassessed, "nut thread shear");
            testCase.verifySubstring(s.Note, "INCOMPLETE");
            testCase.verifySubstring(s.Note, "OPTIMISTIC");

            % ... and the tension margin's Decision carries the warning.
            % Low preload keeps the gate assured (2,000 < 0.75*10,000 =
            % 7,500), so Eq. 6: MS = 10,000/(1.15*1.4*2,000) - 1
            %                      = 10,000/3,220 - 1 = +2.106
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0);
            lc  = model.LoadCase(Name="incomplete-assessment check", ...
                BoltTensileLimitLoad=2000, BoltShearLimitLoad=0);
            fac = model.Factors();
            r = engine.marginTensionUlt(j, engine.preload(j), ...
                engine.designLoads(lc, fac));
            testCase.verifyEqual(r.MS, 10000/3220 - 1, "AbsTol", 1e-9);
            testCase.verifySubstring(r.Decision, "INCOMPLETE");
            testCase.verifySubstring(r.Decision, "nut thread shear");
        end

        function areaWithoutFsuIsNotSilentlyRated(testCase)
            % NO SILENT FALLBACK: with a thread-shear area available but no
            % nut Fsu, the true allowable min(Fsu·As, rating) is unknowable
            % and is <= the rating — standing the 10,000 lbf rating in for
            % it would be OPTIMISTIC. The mode must report unassessed (the
            % same rule engine.marginNutStrength applies), leaving the
            % system minimum incomplete at the bolt's 15,200 lbf.
            j = tSystemAllowable.softNutJoint(NaN, 10000, 15200);  % Fsu NaN
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, 15200, "AbsTol", 1e-9);
            testCase.verifyFalse(s.Complete);
            testCase.verifyEqual(s.Unassessed, "nut thread shear");
            testCase.verifySubstring(s.Note, "INCOMPLETE");
        end

        function noBoltRatingFallsBackToDerivedAllowable(testCase)
            % BEHAVIOR CHANGED (see boltTensileAllowable): with
            % BoltRatedUltimateLoad unset but the bolt's own At/Ftu present,
            % the tension margin no longer throws — it uses the DERIVED
            % Ptu_allow = At*Ftu fallback (NASA-STD-5020B §4.4.2 derived
            % convention, not a numbered equation). Ex 8-b fixture: At =
            % 0.0878, Ftu = 160,000 -> Ptu_allow = 14,048 lbf; the Nut mode
            % still can't be assessed (no rating, no engagement length), so
            % the bolt's derived allowable alone sets the system minimum —
            % an INCOMPLETE (optimistic) but non-error assessment.
            c = validation.dabjExample8b();   % BoltRatedUltimateLoad = NaN
            j = c.Joint;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0);
            lc  = model.LoadCase(Name="derived-fallback check", ...
                BoltTensileLimitLoad=2000, BoltShearLimitLoad=0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);

            expectedPtuAllow = 0.0878 * 160000;   % At * Ftu
            s = engine.systemTensileAllowable(j);
            testCase.verifyEqual(s.PtuAllow, expectedPtuAllow, "AbsTol", 1e-6);
            testCase.verifyEqual(s.GoverningMode, "bolt tension");
            testCase.verifyFalse(s.Complete);       % nut mode still unassessed
            testCase.verifySubstring(s.Note, "derived Ptu_allow");

            r = engine.marginTensionUlt(j, p, d);
            testCase.verifyFalse(isnan(r.MS));
            testCase.verifyEqual(r.MS, ...
                expectedPtuAllow / (1.15 * 1.4 * 2000) - 1, "AbsTol", 1e-6);
            testCase.verifySubstring(r.Decision, "derived Ptu_allow");
            testCase.verifySubstring(r.Decision, "INCOMPLETE");
        end

        % ---- The YIELD system allowable (5020B §4.4.2) --------------------
        % engine.systemTensileYieldAllowable is the yield counterpart of
        % everything above: the minimum over the bolt's yield allowable and
        % the internally threaded member's As*Fsy, which is the quantity
        % NASA-STD-5020B p30 names when it introduces Eq. 17 ("the fastening
        % SYSTEM'S allowable yield tensile load"). engine.marginTensionYield
        % consumes it in Eq. 15 and Eq. 17, exactly as marginTensionUlt
        % consumes the ultimate one in Eq. 6 and Eq. 10.

        function dabjYieldSystemBoltGovernedButIncomplete(testCase)
            % THE REGRESSION GUARD FOR THIS CHANGE, and the executable form
            % of the argument that let it ship: DABJ §9's +0.63 must not
            % move, and the reason it cannot is worth pinning, not just
            % asserting.
            %
            % validation.dabjSection9 builds a Nut with
            % RatedUltimateLoad = 15,200 lbf and NO EngagementLength. A spec
            % rating is an ULTIMATE quantity and carries no yield
            % information (memberTensileYldAllowable rule 2 —
            % engine.marginNutStrength has treated a flat rating as
            % ultimate-only all along), so the nut has an ultimate mode and
            % NO yield mode. The yield minimum therefore degenerates to the
            % bolt's rated 11,400 lbf and Eq. 15 still gives
            %   MS = 11,400/6,987.5 - 1 = +0.63   (Solutions-18)
            %
            % But it is INCOMPLETE, and that is a real finding rather than
            % bookkeeping: on this joint the tool genuinely does not know
            % the nut's yield capability, and before this change nothing
            % said so. Pin the flag alongside the number.
            c = validation.dabjSection9();
            s = engine.systemTensileYieldAllowable(c.Joint);
            testCase.verifyEqual(s.PtyAllow, 11400, "AbsTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "bolt yield");
            testCase.verifyFalse(s.Complete);
            testCase.verifyEqual(s.Unassessed, "nut thread shear");
            testCase.verifySubstring(s.Note, "INCOMPLETE");
            testCase.verifySubstring(s.Note, "OPTIMISTIC");
            testCase.verifySubstring(s.Note, "a rating carries no yield information");

            % ... and the answer key itself, through the full run.
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            testCase.verifyEqual(row(r, "Tension-Yield").MS, ...
                c.Expected.MS_BoltYield, "AbsTol", c.Tol.MarginAbsTol);   % +0.63
            testCase.verifySubstring(row(r, "Tension-Yield").Method, "Eq. 15");
            testCase.verifySubstring(row(r, "Tension-Yield").Detail, "INCOMPLETE");
        end

        function nutYieldGovernsSystem(testCase)
            % A nut softer than the bolt sets the system YIELD allowable,
            % the same way nutAreaGovernsSystem shows it setting the
            % ultimate one. Ex 8-b + Phase 3.3 thread inputs (E = 0.3479 in,
            % Le = 0.375 in), nut Fsu = 30,000 psi with Fsy SUPPLIED as
            % 0.9*Fsu = 27,000 psi (softNutJoint's convention — so this pin
            % does not depend on the von Mises estimate); bolt rated
            % ultimate 15,200 lbf, no rated yield. HAND-DERIVED:
            %   As        = 0.75*pi*0.3479*0.375        = 0.3073950 in^2
            %   nut yield = 27,000 * 0.3073950          = 8,299.67 lbf
            %   bolt yield (5020B Eq. 18 on the RATED ultimate)
            %             = (120,000/160,000)*15,200    = 11,400 lbf
            %   system    = min(11,400, 8,299.67)       = 8,299.67 lbf
            j = tSystemAllowable.softNutJoint(30000, 0, 15200);
            s = engine.systemTensileYieldAllowable(j);
            testCase.verifyEqual(s.PtyAllow, 27000*0.75*pi*0.3479*0.375, ...
                "RelTol", 1e-9);
            testCase.verifyEqual(s.PtyAllow, 8299.67, "AbsTol", 0.5);
            testCase.verifyEqual(s.GoverningMode, "nut thread shear");
            testCase.verifyTrue(s.Complete);
            % Supplied, NOT estimated — the basis must say which.
            testCase.verifySubstring(s.Note, "supplied");

            % NOT capped by the rating: a rating is an ultimate quantity.
            % 4,000 lbf would halve the ultimate allowable and must leave
            % the yield allowable exactly where it was.
            j2 = tSystemAllowable.softNutJoint(30000, 4000, 15200);
            s2 = engine.systemTensileYieldAllowable(j2);
            testCase.verifyEqual(s2.PtyAllow, s.PtyAllow, "AbsTol", 1e-9);
            testCase.verifyEqual(engine.systemTensileAllowable(j2).PtuAllow, ...
                4000, "AbsTol", 1e-9);     % the ultimate side IS capped
        end

        function insertYieldGovernsSystem(testCase)
            % Insert pull-out at YIELD, from the PARENT material — the same
            % interface insertGovernsSystem checks at ultimate. #10-32
            % Heli-Coil fixture: shear engagement area 0.1121 in^2, parent
            % Al 6061-T651 with Fty = 36,000 psi and NO Fsy, so Fsy comes
            % from the von Mises estimate NASA-STD-5020B §4.4.2 p31
            % sanctions and Eq. 63 prints; bolt rated ultimate 15,200 lbf. HAND-DERIVED:
            %   Fsy    = 36,000/sqrt(3)                 = 20,784.61 psi
            %   insert = 0.1121 * 20,784.61             = 2,329.95 lbf
            %   bolt yield (Eq. 18)                     = 11,400 lbf
            %   system = min(11,400, 2,329.95)          = 2,329.95 lbf
            j = tSystemAllowable.insertJoint( ...
                model.Material(Name="Al 6061-T651", Ftu=42000, Fty=36000, ...
                    Fsu=27000), 0.1121, 12949, 15200);
            s = engine.systemTensileYieldAllowable(j);
            testCase.verifyEqual(s.PtyAllow, 0.1121*36000/sqrt(3), "RelTol", 1e-9);
            testCase.verifyEqual(s.PtyAllow, 2329.95, "AbsTol", 0.5);
            testCase.verifyEqual(s.GoverningMode, "insert pull-out");
            testCase.verifyTrue(s.Complete);
        end

        function tappedHoleYieldModeAssessed(testCase)
            % THE DEFERRED DECISION, NOW SETTLED. engine.marginTappedParentThread
            % has always been ultimate-only, with a header note saying a
            % yield criterion for tapped parent threads was an open question.
            % NASA-STD-5020B §4.4.2 answers it: p29 requires the yield
            % assessment to address "all elements of the threaded fastening
            % system, including the fastener, the internally threaded part
            % such as a nut or an insert" — illustrative, and in a tapped
            % configuration the parent IS that part — and p30 removes the
            % obstacle that caused the deferral by sanctioning a failure
            % theory for shear yield. So the mode is assessed HERE, in the
            % system minimum, while the Pb-based ROW stays ultimate-only so
            % DABJ Example 6-a's pin is untouched.
            %
            % DABJ Example 6-a geometry: #10-32 (E = 0.1697 in) fully
            % engaged in 0.250-in 6061-T651 (Fty = 36,000, no Fsy).
            % HAND-DERIVED:
            %   As     = 0.75*pi*0.1697*0.250           = 0.0999616 in^2
            %   Fsy    = 36,000/sqrt(3)                 = 20,784.61 psi
            %   parent = 0.0999616 * 20,784.61          = 2,077.66 lbf
            %   bolt yield (Eq. 18 on the rated 15,200) = 11,400 lbf
            %   system = min(11,400, 2,077.66)          = 2,077.66 lbf
            j = tSystemAllowable.tappedJoint(15200);
            s = engine.systemTensileYieldAllowable(j);
            testCase.verifyEqual(s.PtyAllow, ...
                0.75*pi*0.1697*0.250 * 36000/sqrt(3), "RelTol", 1e-9);
            testCase.verifyEqual(s.PtyAllow, 2077.66, "AbsTol", 0.5);
            testCase.verifyEqual(s.GoverningMode, "tapped-hole parent thread");
            testCase.verifyTrue(s.Complete);

            % The ROW is still ultimate-only, deliberately — the yield
            % criterion lives in the minimum above, not as a second margin
            % on the tapped-hole check. Guard both halves of that split.
            lc  = model.LoadCase(Name="tapped yield split", ...
                BoltTensileLimitLoad=200, BoltShearLimitLoad=0);
            fac = model.Factors();
            tp  = engine.marginTappedParentThread(j, lc, fac, engine.preload(j));
            testCase.verifyFalse(isnan(tp.MS));            % ultimate: evaluated
            % The row carries no yield FIELD at all — not a NaN one. That is
            % the stronger statement and the one that would actually break
            % if someone added a yield criterion to this row without
            % revisiting DABJ Example 6-a's pin.
            testCase.verifyFalse(isfield(tp, "AllowYld"));
        end

        function ratedOnlyMemberYieldUnassessedFlagged(testCase)
            % A member assessable ONLY through its rating has an ultimate
            % mode and NO yield mode — the doctrine that keeps DABJ §9
            % intact, checked here on a non-DABJ fixture so the two cannot
            % be confused. Strip the engagement length from the soft-nut
            % joint and give it a rating: the ultimate side assesses at
            % 9,000 lbf, the yield side reports nothing and says why.
            j = tSystemAllowable.softNutJoint(30000, 9000, 15200);
            j.ThreadedMember.EngagementLength = NaN;

            u = engine.systemTensileAllowable(j);
            testCase.verifyEqual(u.PtuAllow, 9000, "AbsTol", 1e-9);
            testCase.verifyTrue(u.Complete);            % ultimate: complete

            s = engine.systemTensileYieldAllowable(j);
            testCase.verifyEqual(s.PtyAllow, 11400, "AbsTol", 1e-9);  % bolt Eq. 18
            testCase.verifyEqual(s.GoverningMode, "bolt yield");
            testCase.verifyFalse(s.Complete);           % yield: incomplete
            testCase.verifyEqual(s.Unassessed, "nut thread shear");
            testCase.verifySubstring(s.Note, "a rating carries no yield information");
        end

        function noYieldModeAtAllNotEvaluated(testCase)
            % Neither mode assessable -> PtyAllow NaN and Tension-Yield
            % NotEvaluated, with BOTH reasons in Detail rather than a
            % throw. Ex 8-b with the tensile stress area stripped (so the
            % Eq. 18 fallback has no Ptu_allow to work from) and no rating;
            % its Nut has no engagement length either.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.Bolt.TensileStressArea = NaN;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0);

            s = engine.systemTensileYieldAllowable(j);
            testCase.verifyTrue(isnan(s.PtyAllow));
            testCase.verifyEqual(s.GoverningMode, "");
            testCase.verifyFalse(s.Complete);
            testCase.verifyEqual(numel(s.Unassessed), 2);

            lc  = model.LoadCase(Name="no yield mode at all", ...
                BoltTensileLimitLoad=2000, BoltShearLimitLoad=0);
            fac = model.Factors();
            r = engine.marginTensionYield(j, engine.preload(j), ...
                engine.designLoads(lc, fac));
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifyTrue(isnan(r.SystemAllowable));
            testCase.verifySubstring(r.Detail, "bolt yield");
            testCase.verifySubstring(r.Detail, "nut thread shear");
        end

        function derivedFsyFlagSurvivesIntoSystemNote(testCase)
            % A DERIVED Fsy must never pass as test data. engine.shearYieldStrength
            % flags the von Mises estimate — NASA-STD-5020B §4.4.2 p31
            % directs a failure theory and Eq. 63 (p66, A.8) prints the
            % result — and that flag has to survive two hops — through
            % memberTensileYldAllowable into the system Note, and from
            % there into the Tension-Yield row's Detail — or an analyst
            % reads an estimated allowable as a measured one.
            j = tSystemAllowable.tappedJoint(15200);   % parent has Fty, no Fsy
            s = engine.systemTensileYieldAllowable(j);
            testCase.verifySubstring(s.Note, "von Mises");
            testCase.verifySubstring(s.Note, "Fty/sqrt(3)");
            % The EQUATION NUMBER must travel too. 5020B prints this as
            % Eq. 63 (p66, Appendix A.8); the engine used to cite prose and
            % state that no equation number was claimed, which is the
            % document-hierarchy violation the 2026-08-13 audit found.
            testCase.verifySubstring(s.Note, "NASA-STD-5020B Eq. 63");

            lc  = model.LoadCase(Name="derived Fsy trace", ...
                BoltTensileLimitLoad=200, BoltShearLimitLoad=0);
            fac = model.Factors();
            r = engine.marginTensionYield(j, engine.preload(j), ...
                engine.designLoads(lc, fac));
            testCase.verifySubstring(r.Detail, "von Mises");
        end

        function memberGovernedYieldRuptureBranchHandDerived(testCase)
            % THE PIN THAT SHOWS THE CORRECTION MATTERS — Eq. 16/17 with a
            % MEMBER-governed Pty_allow, the case min() over the per-mode
            % rows provably cannot reproduce (those rows divide by
            % boltDesignLoad's Pb; Eq. 17 subtracts PpMax first and divides
            % by n*phi, a different function of the same allowable).
            %
            % Ex 8-b geometry, so phi comes from the real stiffness path
            % (phi = 0.3354, n = 0.5 — the same chain
            % tests/tStiffness.m boltYieldRuptureBranch derives). Nut
            % Fsu = 20,000 psi, Fsy SUPPLIED = 18,000 psi (softNutJoint's
            % 0.9*Fsu); bolt rated ultimate 10,000 and rated yield 9,000;
            % direct preload 5,000 with zero uncertainty, PtL = 2,000.
            % HAND-DERIVED:
            %   As         = 0.75*pi*0.3479*0.375      = 0.3073950 in^2
            %   nut ult    = 20,000 * 0.3073950        = 6,147.90 lbf
            %   system Ptu = min(10,000, 6,147.90)     = 6,147.90 lbf
            %   Fig. 8 gate: PpMax 5,000 > 0.75*6,147.90 = 4,610.93
            %                -> NOT assured, so Eq. 16/17 governs
            %   nut yield  = 18,000 * 0.3073950        = 5,533.11 lbf
            %   system Pty = min(9,000 bolt, 5,533.11) = 5,533.11 lbf
            %   P'ty = (5,533.11 - 5,000)/(0.5*0.3354) = 3,178.95 lbf (Eq. 17)
            %   Pty  = FSY*FFY*PtL = 1.25*1.0*2,000    = 2,500 lbf
            %   MS   = 3,178.95/2,500 - 1              = +0.2716    (Eq. 16)
            % The bolt-only allowable this row used before would have given
            % P'ty = (9,000 - 5,000)/0.1677 = 23,851 and MS = +8.54 — the
            % same SIGN, a different order of magnitude, and the wrong part
            % named as the limit.
            j = tSystemAllowable.softNutJoint(20000, 0, 10000);
            j.BoltRatedYieldLoad = 9000;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 5000, ...
                Uncertainty    = 0);          % PpMax = 5,000 exactly
            lc  = model.LoadCase(Name="member-governed yield rupture branch", ...
                BoltTensileLimitLoad=2000, BoltShearLimitLoad=0);
            fac = model.Factors();            % DABJ defaults: FSY 1.25, FFY 1.0

            s = engine.systemTensileYieldAllowable(j);
            testCase.verifyEqual(s.PtyAllow, 18000*0.75*pi*0.3479*0.375, ...
                "RelTol", 1e-9);
            testCase.verifyEqual(s.GoverningMode, "nut thread shear");

            r = engine.marginTensionYield(j, engine.preload(j), ...
                engine.designLoads(lc, fac));
            testCase.verifyFalse(r.SeparationBeforeYield);
            testCase.verifySubstring(r.Method, "Eq. 16");
            testCase.verifyEqual(r.MS, 0.2716, "AbsTol", 0.01);
            testCase.verifyEqual(r.SystemAllowable, s.PtyAllow, "AbsTol", 1e-9);
            % Detail must name WHICH part is the limit — the whole point of
            % carrying the system Note through.
            testCase.verifySubstring(r.Detail, "nut thread shear");
            % And it is emphatically not the bolt-only answer.
            testCase.verifyLessThan(r.MS, 1);
        end

        function noAllowableAtAllStaysNotEvaluated(testCase)
            % TRUE unavailable case: no rating AND no At (so the derived
            % fallback cannot be formed either) AND no member mode ->
            % NotEvaluated (MS = NaN), not a throw.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.Bolt.TensileStressArea = NaN;   % strips the derived-fallback input too
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0);
            lc  = model.LoadCase(Name="no-allowable-at-all check", ...
                BoltTensileLimitLoad=2000, BoltShearLimitLoad=0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);

            r = engine.marginTensionUlt(j, p, d);
            testCase.verifyTrue(isnan(r.MS));
            testCase.verifySubstring(r.Decision, "not assessed");

            % The helper itself does not error — it reports: nothing
            % assessable -> NaN with both modes listed as unassessed.
            s = engine.systemTensileAllowable(j);
            testCase.verifyTrue(isnan(s.PtuAllow));
            testCase.verifyEqual(s.GoverningMode, "");
            testCase.verifyFalse(s.Complete);
            testCase.verifyEqual(numel(s.Unassessed), 2);
        end
    end

    methods (Static)
        function j = softNutJoint(nutFsu, rating, boltRated)
            %SOFTNUTJOINT  Ex 8-b Nut joint + Phase 3.3 thread inputs,
            %   parameterised on nut Fsu (NaN = unset), the spec rating
            %   (0 = unset), and the bolt rated ultimate load. Same
            %   geometry as tests/tThreadShear.m nutJoint (E = 0.3479 in,
            %   Le = 0.375 in; real stiffness path, phi = 0.3354).
            c = validation.dabjExample8b();
            j = c.Joint;
            j.BoltRatedUltimateLoad = boltRated;
            j.Bolt.PitchDiameter = 0.3479;            % 3/8-24 UNF basic pitch dia, in
            j.ThreadedMember.EngagementLength = 0.375;
            if isnan(nutFsu)
                j.ThreadedMember.Material = model.Material(Name="Nut (no strengths)");
            else
                j.ThreadedMember.Material = model.Material( ...
                    Name="Soft nut (system pin)", Fsu=nutFsu, Fsy=0.9*nutFsu);
            end
            j.ThreadedMember.RatedUltimateLoad = rating;
        end

        function j = insertJoint(parent, area, rating, boltRated)
            %INSERTJOINT  #10-32 Heli-Coil insert fixture (same geometry as
            %   tests/tThreadShear.m insertJoint), parameterised on the
            %   parent material, shear engagement area, rated pull-out, and
            %   bolt rated ultimate load.
            b = model.Bolt(Designation="#10-32 UNF", ...
                NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
                ThreadsPerInch=32, TensileStressArea=0.0200, ...
                MinorDiameter=0.156, PitchDiameter=0.1697);
            bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
                Fsu=95000, E=29.1e6);
            j = model.Joint(Name="system-allowable insert joint", ...
                Bolt=b, BoltMaterial=bm, ...
                BoltRatedUltimateLoad=boltRated, ...
                ThreadedMember=model.ThreadedMember( ...
                    Type=model.ThreadedMemberType.Insert, ...
                    Material=parent, RatedUltimateLoad=rating, ...
                    ShearEngagementArea=area, EngagementLength=0.3006), ...
                PreloadSpec=model.PreloadSpec( ...
                    Method=model.PreloadMethod.DirectPreload, ...
                    NominalPreload=1000, Uncertainty=0.25));
        end

        function j = tappedJoint(boltRated)
            %TAPPEDJOINT  DABJ Example 6-a tapped joint (#10-32 A-286 in
            %   0.250-in 6061-T651; same fixture as tests/tThreadShear.m
            %   tappedParentMatchesDABJ6a) + a bolt rated ultimate load.
            b = model.Bolt(Designation="#10-32 UNF (Ex 6-a)", ...
                NominalDiameter=0.190, Series=model.ThreadSeries.UNF, ...
                ThreadsPerInch=32, TensileStressArea=0.0200, ...
                MinorDiameter=0.156, PitchDiameter=0.1697);
            bm = model.Material(Name="A-286", Ftu=160000, Fty=120000, ...
                Fsu=95000, E=29.1e6);
            parent = model.Material(Name="Al 6061-T651", Ftu=42000, ...
                Fty=36000, Fsu=27000, E=9.9e6);
            j = model.Joint(Name="system-allowable tapped joint", ...
                Bolt=b, BoltMaterial=bm, ...
                BoltRatedUltimateLoad=boltRated, ...
                ThreadedMember=model.ThreadedMember( ...
                    Type=model.ThreadedMemberType.TappedHole, ...
                    Material=parent, EngagementLength=0.250), ...
                PreloadSpec=model.PreloadSpec( ...
                    Method=model.PreloadMethod.DirectPreload, ...
                    NominalPreload=1000, Uncertainty=0.25));
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
