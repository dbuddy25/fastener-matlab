classdef tStiffness < matlab.unittest.TestCase
    %TSTIFFNESS  Phase 3.1 acceptance: engine.stiffness (30° conical
    %   frustum, through-bolt configuration) reproduces the DABJ Example
    %   8-b published stiffnesses (validation.dabjExample8b): Kb = 2.39e6,
    %   Kc = 4.73e6 lbf/in, Phi = 0.336. Insert/tapped-hole joints are
    %   covered against a SECOND answer key, DABJ Table 8-3 (slide 8-26),
    %   via the shortened grip L = t1 + D/2; only MIXED FLANGE MODULI
    %   remain deferred (STIFFNESS_PLAN.md Job B). Phase 3.1b wiring
    %   is exercised here too: the stiffness-based thermal preload path
    %   (thermalFromStiffness) and the Eq. 10 tension rupture branch
    %   (tensionRuptureBranch) — both against HAND-DERIVED numbers, not
    %   book values. Also covers the Eq. 16/17 bolt-yield rupture branch
    %   (boltYieldRuptureBranch, the yield analogue sharing the same Fig. 8
    %   gate) and the Fig. 8 e/D edge-distance condition
    %   (edgeDistanceVerifiedAssuresGate / edgeDistanceVerifiedFailingBreaksGate /
    %   edgeDistanceUnknownIsAssumedNotVerified) — all HAND-DERIVED.
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
            % recomputation, with kc's coefficient as the exact
            % pi*tan(30 deg) = 1.81380 rather than the book's own
            % 3-sig-fig 1.81, gives 2.3892e6 / 4.7352e6 / 0.3354 — Kc
            % ~0.21% above the book's 4.73e6, still inside RelTol below).
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

        function bodyLengthFallbackComputed(testCase)
            % When BodyLengthInGrip is NaN, L1 falls back to the computed
            % estimate: bolt length ≈ Lb + nut height + 2·pitch
            % (NASA-STD-5020B §4.7.4), shank Ls = boltLength − ThreadLength,
            % L1 = min(max(Ls,0), Lb) with Lb = fittings + washers
            % (8-b: 0.94 in). An explicit L1 always wins — the 8-b answer-key
            % test above exercises that path (L1 = 0.70 as supplied).
            c = validation.dabjExample8b();
            j = c.Joint;
            j.BodyLengthInGrip = NaN;
            j.ThreadedMember.EngagementLength = 0.3;   % nut height, in
            j.Bolt.ThreadLength = 0.5;                 % threaded length from the tip, in
            s = engine.stiffness(j);
            expectedL1 = min(max((0.94 + 0.3 + 2/24) - 0.5, 0), 0.94);
            testCase.verifyEqual(s.L1, expectedL1, "AbsTol", 1e-12);
            testCase.verifyEqual(s.L2, 0.94 - expectedL1, "AbsTol", 1e-12);
            % Missing fallback inputs (ThreadLength / EngagementLength NaN)
            % still error with the existing id -> callers render NotEvaluated.
            j2 = c.Joint;
            j2.BodyLengthInGrip = NaN;
            testCase.verifyError(@() engine.stiffness(j2), ...
                "engine:stiffness:bodyLengthRequired");
        end

        function threadedInMatchesDabjTable83(testCase)
            % ANSWER KEY: DABJ Table 8-3 (slide 8-26) — fixed fasteners into
            % threaded inserts, aluminium members Ec = 10e6, countersunk
            % washer t = 0.078 under the head, t1 varied 2D then 1D.
            %
            % The threaded-in rule (DABJ slide 8-23, quoting Shigley &
            % Mischke) is the SAME symmetric back-to-back frustum as the nut
            % case fed a SHORTENED grip, L = t1 + D/2. Two rows are pinned
            % here; the rest stay in the (copyrighted) book. Both reproduce
            % ~0.15% high, which is the book's OWN rounding — it prints the
            % frustum coefficient as 1.81 where pi*tan(30 deg) = 1.81380.
            % That the residual is the SAME on both rows (not merely small)
            % is the evidence the form is structurally right.
            %
            % Note the single-washer spread: Dc = dwf + 2*tan(30 deg)*tw uses
            % the FULL head washer thickness, not the nut-case two-washer
            % average — a threaded-in joint has no nut washer. Table 8-3's
            % own dc confirms it: 0.523 + 2*tan(30 deg)*0.078 = 0.613.
            rows = struct( ...
                "Name", {"NAS 1956 (3/8, t1 = 2D)", "NAS 1958 (1/2, t1 = 1D)"}, ...
                "D",    {0.375,   0.500}, ...
                "At",   {0.0878,  0.1599}, ...
                "dwf",  {0.523,   0.710}, ...
                "t1",   {0.750,   0.500}, ...
                "Kc",   {4.532347e6, 7.472956e6});
            for k = 1:numel(rows)
                r = rows(k);
                j = tStiffness.threadedInJoint(r.D, r.At, r.dwf, r.t1, 0.078);
                s = engine.stiffness(j);
                % kc against the book (RelTol covers the 0.15% rounding gap)
                testCase.verifyEqual(s.Kc, r.Kc, "RelTol", 0.005);
                % Shortened grip L = t1 + D/2 (DABJ slide 8-23)
                testCase.verifyEqual(s.Lc, r.t1 + r.D/2, "AbsTol", 1e-12);
                % Single-washer spread, NOT the two-washer average
                testCase.verifyEqual(s.Dc, r.dwf + 2*tand(30)*0.078, ...
                    "AbsTol", 1e-12);
                % Table 8-3's Lb column: 0.4D + tw + t1 + D/2. In engine
                % terms the effective bolt length is (L1 + 0.4D) + (L2 + D/2)
                % with L1 + L2 = t1 + tw — i.e. NO nut washer in the clamp.
                testCase.verifyEqual(s.L1 + 0.4*r.D + s.L2 + r.D/2, ...
                    0.4*r.D + 0.078 + r.t1 + r.D/2, "AbsTol", 1e-12);
                testCase.verifySubstring(s.Method, "h = D/2 ASSUMED");
            end
        end

        function threadedInShortensGripAndDropsPoint4D(testCase)
            % Both branch differences on ONE geometry (NAS 1956 row, single
            % 0.078 head washer, L1 = 0.50 supplied), flipping only
            % ThreadedMember.Type.
            %
            % kb IS a clean one-variable comparison: L1, L2, As, At and Eb
            % are identical, and only the threaded end's extension changes —
            % +0.4D = 0.150 for the nut vs h = D/2 = 0.1875 threaded-in. A
            % longer effective bolt is more compliant, so kb DROPS.
            %   As = pi/4*0.375^2 = 0.110447,  At = 0.0878,  Eb = 29e6
            %   Lbolt = t1 + tw = 0.750 + 0.078 = 0.828,  L2 = 0.828 - 0.50 = 0.328
            %   threaded-in kb = 29e6/[(0.50+0.150)/0.110447 + (0.328+0.1875)/0.0878]
            %                  = 2,466,722 lbf/in
            %   nut         kb = 29e6/[(0.50+0.150)/0.110447 + (0.328+0.150)/0.0878]
            %                  = 2,559,715 lbf/in
            %
            % kc is NOT a clean comparison and deliberately is not asserted
            % as an inequality: flipping the type changes the grip (0.750 ->
            % 0.9375, which lowers kc) AND the washer rule (averaged 0.039 ->
            % the full head 0.078, which raises the cone start diameter and
            % so raises kc). Here the diameter effect WINS — threaded-in kc
            % comes out HIGHER, 4,540,245 vs 4,258,048 — which is exactly why
            % both are pinned numerically instead.
            %   Dc(threaded-in) = 0.523 + 2*tan(30 deg)*0.078 = 0.613067
            %   Dc(nut)         = 0.523 + 2*tan(30 deg)*0.039 = 0.568033
            jIn  = tStiffness.threadedInJoint(0.375, 0.0878, 0.523, 0.750, 0.078);
            jIn.BodyLengthInGrip = 0.50;
            jNut = jIn;
            jNut.ThreadedMember.Type = model.ThreadedMemberType.Nut;

            sIn  = engine.stiffness(jIn);
            sNut = engine.stiffness(jNut);

            % kb — pinned, plus the isolated inequality
            testCase.verifyEqual(sIn.Kb,  2.4667217e6, "RelTol", 1e-5);
            testCase.verifyEqual(sNut.Kb, 2.5597147e6, "RelTol", 1e-5);
            testCase.verifyLessThan(sIn.Kb, sNut.Kb);

            % Grip: shortened-grip rule vs the plain fitting stack
            testCase.verifyEqual(sIn.Lc,  0.9375, "AbsTol", 1e-12);
            testCase.verifyEqual(sNut.Lc, 0.750,  "AbsTol", 1e-12);

            % Washer rule: full head thickness vs the two-washer average
            testCase.verifyEqual(sIn.Dc,  0.523 + 2*tand(30)*0.078, "AbsTol", 1e-12);
            testCase.verifyEqual(sNut.Dc, 0.523 + 2*tand(30)*0.039, "AbsTol", 1e-12);

            % kc — pinned on both branches (see the note above)
            testCase.verifyEqual(sIn.Kc,  4.5402454e6, "RelTol", 1e-5);
            testCase.verifyEqual(sNut.Kc, 4.2580477e6, "RelTol", 1e-5);

            % phi stays well below the old blanket phi = 1 — the whole point.
            testCase.verifyEqual(sIn.Phi, 0.352038, "AbsTol", 1e-5);
            testCase.verifySubstring(sNut.Method, "through-bolt");
        end

        function threadedInThermalPreloadRuns(testCase)
            % REGRESSION: engine.preload calls engine.stiffness on the
            % thermal path, and engine.analyze / engine.summary do NOT guard
            % that call — so before the threaded-in frustum existed, ANY
            % insert or tapped-hole joint with a temperature excursion threw
            % and failed the whole analysis. It must now simply compute.
            j = tStiffness.threadedInJoint(0.375, 0.0878, 0.523, 0.750, 0.078);
            j.BodyLengthInGrip = 0.50;
            j.PreloadSpec = model.PreloadSpec( ...
                Method=model.PreloadMethod.DirectPreload, ...
                NominalPreload=2000, Uncertainty=0.25);
            j.MinTemperature = -54;        % °C (see UNITS.md — engine is °C)
            j.MaxTemperature = 71;
            p = engine.preload(j);
            testCase.verifyFalse(isnan(p.PpMax), ...
                "thermal preload must evaluate for a threaded-in joint");
            testCase.verifyFalse(isnan(p.PpMin));
            % A thermal term was actually applied (bolt/joint CTEs differ).
            testCase.verifyNotEqual(p.PpMax, 2500);
        end

        function mixedModulusStillDeferred(testCase)
            % Job B is NOT in scope here: per-layer frustum slicing for a
            % stack whose layers differ in modulus remains deferred, and the
            % guard must still fire (on the threaded-in branch too, so the
            % new branch cannot smuggle a mixed stack through).
            c = validation.dabjExample8b();
            j = c.Joint;
            j.FlangeStack(2).Material = model.Material( ...
                Name="Steel", Ftu=180000, Fty=160000, Fsu=108000, E=29e6);
            testCase.verifyError(@() engine.stiffness(j), ...
                "engine:stiffness:mixedModulusDeferred");
            j.ThreadedMember.Type = model.ThreadedMemberType.Insert;
            testCase.verifyError(@() engine.stiffness(j), ...
                "engine:stiffness:mixedModulusDeferred");
        end

        function kcAtNonDefaultFrustumAngle(testCase)
            % Regression for the frustum coefficient: kc's leading
            % constant is pi*tan(alpha), not a 30°-only 1.81 — must track
            % FrustumAngle. Reuses the Example 8-b geometry (D = 0.375,
            % Ec = 10e6, L = tFit = 0.80, dwf = 0.523, washer thickness tw
            % = 0.070) but at alpha = 45° instead of 30°, with both
            % washer ODs left unspecified (NaN) so Dc is the bare cone
            % diameter (not capped by an OD) — isolating the constant
            % change from the OD-cap branch already covered by 8-b.
            %
            % HAND DERIVATION (no book number; checkable with a
            % calculator, no MATLAB):
            %   tanA = tan(45 deg) = 1
            %   Dc = dwf + 2*tanA*tw = 0.523 + 2*1*0.070 = 0.663 in
            %   numerator   = (tanA*L + Dc - D)*(Dc + D)
            %               = (1*0.80 + 0.663 - 0.375)*(0.663 + 0.375)
            %               = (0.80 + 0.288)*(1.038) = 1.088*1.038 = 1.129344
            %   denominator = (tanA*L + Dc + D)*(Dc - D)
            %               = (0.80 + 0.663 + 0.375)*(0.663 - 0.375)
            %               = (1.838)*(0.288) = 0.529344
            %   arg = 1.129344/0.529344 = 2.13348
            %   ln(arg) = 0.75775
            %   kc = pi*tanA*Ec*D / (2*ln(arg))
            %      = pi*1*10e6*0.375 / (2*0.75775)
            %      = 11,780,972.5 / 1.51551
            %      = 7,773,616 lbf/in  (approx; RelTol below covers the
            %        rounding in this longhand chain)
            %   By contrast, the pre-fix code (hardcoded 1.81 regardless
            %   of angle) would have returned
            %      1.81*10e6*0.375 / (2*0.75775) = 4,478,698 lbf/in,
            %   about 42% low — consistent with the ~43%-low estimate for
            %   45 deg used to justify this fix. Kb is angle-independent
            %   (unaffected by this bug either way), so only Kc is checked.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.FrustumAngle = 45;
            j.HeadWasher.OuterDiameter = NaN;
            j.NutWasher.OuterDiameter  = NaN;
            s = engine.stiffness(j);
            testCase.verifyEqual(s.Dc, 0.663, "AbsTol", 1e-9);
            testCase.verifyEqual(s.Kc, 7773616, "RelTol", 1e-4);
        end

        function thermalFromStiffness(testCase)
            % Phase 3.1b: with no ThermalRate override, engine.preload
            % computes the thermal preload change from the joint stiffness
            % per NASA TM-106943 (Chambers) Eq. 10 —
            % Pth = (Kb·Kc/(Kb+Kc))·L·ΔT·(αj − αb).
            % HAND-DERIVED expected value (no book number): the Example 8-b
            % geometry gives Kb = 2.3892e6 lbf/in (unaffected by the
            % frustum-coefficient fix) and Kc = 4.7352e6 lbf/in (pi*tan(30
            % deg) exact coefficient, NOT the book's own rounded 1.81 — see
            % engine.stiffness), so kSeries = 2.3892e6*4.7352e6/7.1244e6 =
            % 1.5880e6 lbf/in. With L (grip) = 0.80 in, a hot-only
            % excursion ΔT = +50 °C, and the fixture CTEs αj = 2.32e-5
            % (aluminum members) and αb = 1.69e-5 (A-286) 1/°C:
            %   Pth = 1.5880e6 · 0.80 · 50 · (2.32e-5 − 1.69e-5) = 400.2 lbf
            % Hot-only with αj > αb means the excursion only ADDS preload:
            % the max side gains 400.2 lbf and the min side loses nothing.
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
            testCase.verifyEqual(p.ThermalDelta, 400.2, "AbsTol", 1.0);
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
            % geometry gives phi = Kb/(Kb+Kc) = 2.3892e6/7.1244e6 = 0.3354
            % (Kc = 4.7352e6, the exact pi*tan(30 deg) coefficient — see
            % engine.stiffness) and the fixture n = 0.5. With
            % Ptu_allow = 10,000 lbf and PpMax = 8,000 lbf (direct preload,
            % zero uncertainty, no thermal excursion), the preload gate
            % fails (8,000 >= 0.75·10,000 = 7,500) -> rupture branch.
            % PtL = 2,000 with the DABJ default factors (FSU 1.4, FFU 1.15)
            % gives Ptu = 3,220 lbf, so:
            %   P'tu = (10,000 - 8,000)/(0.5·0.3354) = 11,928 lbf
            %   MS   = 11,928/3,220 - 1 = +2.704
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
            testCase.verifyEqual(r.MS, 2.704, "AbsTol", 0.01);
        end

        function boltYieldRuptureBranch(testCase)
            % Task 2: when the Fig. 8 gate fails, the bolt YIELD margin
            % switches to NASA-STD-5020B Eq. 16/17 — the yield analogue of
            % the ultimate side's Eq. 7/10 (tensionRuptureBranch above),
            % sharing the SAME gate evaluation.
            % HAND-DERIVED expected value (no book number): same Example
            % 8-b geometry/phi/n as tensionRuptureBranch (phi = 0.3354,
            % n = 0.5). BoltRatedUltimateLoad = 10,000 and PpMax = 8,000
            % (direct preload, zero uncertainty) fail the preload gate
            % condition exactly as in tensionRuptureBranch (8,000 >=
            % 0.75*10,000 = 7,500) -> NOT assured, regardless of the yield
            % allowable (the gate is about Ptu_allow, shared with the
            % ultimate side). BoltRatedYieldLoad = 9,000 (independent of
            % the ultimate rating). PtL = 2,000 with DABJ default factors
            % (FSY 1.25, FFY 1.0) gives Pty(design) = 2,500, so:
            %   P'ty = (9,000 - 8,000)/(0.5*0.3354) = 5,964 lbf   (Eq. 17)
            %   MS   = 5,964/2,500 - 1 = +1.386                    (Eq. 16)
            c = validation.dabjExample8b();
            j = c.Joint;
            j.BoltRatedUltimateLoad = 10000;
            j.BoltRatedYieldLoad    = 9000;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 8000, ...
                Uncertainty    = 0);      % PpMax = 8,000 exactly
            lc  = model.LoadCase(Name = "yield rupture-branch check", ...
                BoltTensileLimitLoad = 2000, BoltShearLimitLoad = 0);
            fac = model.Factors();        % DABJ defaults: FSY 1.25, FFY 1.0
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            r = engine.marginTensionYield(j, p, d);
            testCase.verifyFalse(r.SeparationBeforeYield);
            testCase.verifySubstring(r.Method, "Eq. 16");
            testCase.verifyEqual(r.MS, 1.386, "AbsTol", 0.01);
        end

        function edgeDistanceVerifiedAssuresGate(testCase)
            % Task 1: when EVERY flange layer records EdgeDistance, the
            % Fig. 8 e/D condition is TESTED, not assumed. Both layers get
            % e/D = 0.60/0.375 = 1.60 >= 1.5 -- condition holds and Trace
            % must say VERIFIED (not ASSUMED). Preload kept small (direct
            % 2,000 lbf, Gamma 0.25 -> PpMax = 2,500) so every other Fig. 8
            % condition also holds on this geometry (Ec 10e6 > Eb/3
            % 9.667e6; PpMax 2,500 <= 0.75*Ptu_allow, Ptu_allow = At*Ftu =
            % 0.0878*160,000 = 14,048 derived, threshold 10,536; n = 0.5
            % <= 0.9) -> gate ASSURED, Eq. 6:
            %   MS = 14,048/(1.15*1.4*2,000) - 1 = 14,048/3,220 - 1 = +3.363
            c = validation.dabjExample8b();
            j = c.Joint;
            j.FlangeStack(1).EdgeDistance = 0.60;
            j.FlangeStack(2).EdgeDistance = 0.60;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0.25);
            lc  = model.LoadCase(Name = "edge-verified-pass", ...
                BoltTensileLimitLoad = 2000, BoltShearLimitLoad = 0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            r = engine.marginTensionUlt(j, p, d);
            testCase.verifyTrue(r.SeparationBeforeRupture);
            testCase.verifySubstring(r.Decision, "e/D");
            testCase.verifySubstring(r.Decision, "VERIFIED");
            testCase.verifyFalse(contains(r.Decision, "ASSUMED"));
            testCase.verifySubstring(r.Method, "Eq. 6");
            testCase.verifyEqual(r.MS, 3.363, "AbsTol", 0.01);
        end

        function edgeDistanceVerifiedFailingBreaksGate(testCase)
            % Task 1: a KNOWN e/D below 1.5 fails the condition outright --
            % an unrecorded layer could not un-fail it, so this is decisive
            % evidence, not an assumption. One layer set to e/D =
            % 0.30/0.375 = 0.80 < 1.5; every other Fig. 8 condition still
            % holds (same small preload as edgeDistanceVerifiedAssuresGate)
            % -> gate NOT assured, purely on e/D, rupture branch (Eq. 10).
            % HAND-DERIVED (phi = 0.3354 as in tensionRuptureBranch;
            % Ptu_allow = At*Ftu = 14,048 derived; PpMax = 2,500; n = 0.5;
            % PtL = 2,000; DABJ default factors FSU 1.4, FFU 1.15):
            %   P'tu = (14,048 - 2,500)/(0.5*0.3354) = 68,870 lbf
            %   Ptu(design) = 1.4*1.15*2,000 = 3,220 lbf
            %   MS = 68,870/3,220 - 1 = +20.388
            c = validation.dabjExample8b();
            j = c.Joint;
            j.FlangeStack(1).EdgeDistance = 0.30;   % e/D = 0.80 < 1.5
            j.FlangeStack(2).EdgeDistance = 0.60;   % e/D = 1.60 (not the tight layer)
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0.25);
            lc  = model.LoadCase(Name = "edge-verified-fail", ...
                BoltTensileLimitLoad = 2000, BoltShearLimitLoad = 0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            r = engine.marginTensionUlt(j, p, d);
            testCase.verifyFalse(r.SeparationBeforeRupture);
            testCase.verifySubstring(r.Decision, "e/D");
            testCase.verifySubstring(r.Decision, "VERIFIED failing");
            testCase.verifySubstring(r.Method, "Eq. 10");
            testCase.verifyEqual(r.MS, 20.388, "AbsTol", 0.05);
        end

        function edgeDistanceUnknownIsAssumedNotVerified(testCase)
            % Task 1: no flange layer records EdgeDistance (the default,
            % unconfigured NaN) -> the e/D condition is ASSUMED satisfied,
            % not verified -- and Trace must say so. Same DABJ Example 8-b
            % geometry, unmodified (no EdgeDistance set anywhere), with the
            % small preload that keeps every other condition passing ->
            % gate ASSURED, but on an ASSUMED (not VERIFIED) e/D.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.PreloadSpec = model.PreloadSpec( ...
                Method         = model.PreloadMethod.DirectPreload, ...
                NominalPreload = 2000, ...
                Uncertainty    = 0.25);
            lc  = model.LoadCase(Name = "edge-unknown", ...
                BoltTensileLimitLoad = 2000, BoltShearLimitLoad = 0);
            fac = model.Factors();
            p = engine.preload(j);
            d = engine.designLoads(lc, fac);
            r = engine.marginTensionUlt(j, p, d);
            testCase.verifyTrue(r.SeparationBeforeRupture);
            testCase.verifySubstring(r.Decision, "e/D");
            testCase.verifySubstring(r.Decision, "ASSUMED");
            testCase.verifyFalse(contains(r.Decision, "VERIFIED"));
            % Same arithmetic as edgeDistanceVerifiedAssuresGate (the e/D
            % condition being assumed vs. verified changes only the Trace
            % wording, never the margin): MS = 14,048/3,220 - 1 = +3.363
            testCase.verifyEqual(r.MS, 3.363, "AbsTol", 0.01);
        end
    end

    methods (Static, Access = private)
        function j = threadedInJoint(D, At, dwf, t1, tw)
            %THREADEDINJOINT  Minimal DABJ Table 8-3-shaped insert joint.
            %   One aluminium member of thickness t1 (the through-hole
            %   stack), one countersunk washer of thickness tw under the
            %   head, NO nut washer, A-286 bolt at the example's printed
            %   Eb = 29e6. Table 8-3's stated assumptions (slide 8-26).
            bm = model.Material(Name="A-286 (Table 8-3, E=29e6)", ...
                Ftu=160000, Fty=120000, Fsu=95000, E=29e6, CTE=1.69e-5);
            fm = model.Material(Name="Aluminum (Table 8-3, E=10e6)", ...
                Ftu=68000, Fty=57000, Fsu=39000, E=10e6, CTE=2.32e-5);
            b = model.Bolt( ...
                Designation         = sprintf("%.3f-in (Table 8-3)", D), ...
                NominalDiameter     = D, ...
                Series              = model.ThreadSeries.UNF, ...
                TensileStressArea   = At, ...
                BodyDiameter        = D, ...
                HeadBearingDiameter = dwf);
            j = model.Joint( ...
                Name             = "DABJ Table 8-3 insert joint", ...
                Bolt             = b, ...
                BoltMaterial     = bm, ...
                FlangeStack      = model.FlangeLayer(Material=fm, Thickness=t1), ...
                HeadWasher       = model.Washer(Thickness=tw), ...
                BodyLengthInGrip = t1, ...   % kc is independent of L1
                FrustumAngle     = 30, ...
                ThreadedMember   = model.ThreadedMember( ...
                                       Type     = model.ThreadedMemberType.Insert, ...
                                       Material = fm), ...
                LoadingPlaneFactor = 0.5);   % LIF n = 0.5 (slide 8-26)
        end
    end
end
