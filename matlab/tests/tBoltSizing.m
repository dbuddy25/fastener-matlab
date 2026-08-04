classdef tBoltSizing < matlab.unittest.TestCase
    %TBOLTSIZING  engine.boltSizingSweep — preliminary strength screen.
    %   PRELIMINARY MATERIAL-STRENGTH SCREEN ONLY: 3 reported margins of
    %   the 15 NASA-STD-5020B margins (tension-ultimate, tension-yield,
    %   shear), because no bolt has been chosen yet and therefore no
    %   preload exists — see boltSizingSweep.m's header. Interaction
    %   (Eq. 20-23) is evaluated too, but ONLY as a pass/fail GATE folded
    %   into Status — it is no longer a reported number/column (no `R`,
    %   no margin, not the retired "solve-for-a" MS_Interaction). When the
    %   gate is the reason (or a contributing reason) a row fails, the
    %   Notes column carries the explanation so a row that passes
    %   tension/yield/shear individually but still fails is never an
    %   unexplained rejection.
    %
    %   This has no DABJ answer-key analogue (DABJ never covers a
    %   preload-free sizing sweep), so every expected number here is
    %   HAND-DERIVED with its arithmetic inline, sourced from the shipped
    %   library (+data/library.json: A286 bolt material, NAS1351/NAS1352
    %   socket-head bolts) and model.Factors() defaults (FSU 1.4, FSY
    %   1.25, FFU 1.15, FFY 1.0). Interaction R values are re-derived
    %   longhand where asserted (e.g. via ln/exp for the non-integer
    %   exponent, since MATLAB is not available to check the arithmetic
    %   directly) but the tests below deliberately assert only the
    %   pass/fail OUTCOME and the presence of the Notes explanation, not
    %   an exact formatted R string, since the longhand ln/exp arithmetic
    %   carries more rounding slack than a direct power evaluation would.
    %
    %   Threaded-member context (system-vs-bolt-only tension-ultimate):
    %   MS_TensionUlt/TensionUltBasis now depend on whether the caller
    %   supplies Library+NutSpec (per-size nut resolution) or a fixed
    %   ThreadedMember template (Insert/TappedHole) -- see
    %   nutGovernsBelowBoltFlipsPassToFail (the defect this task fixes: a
    %   size the bolt-only screen would Pass actually fails once the
    %   governing nut is considered), noMatchingNutFallsBackToBoltOnlyHonestly
    %   and unassessedThreadedMemberRefusedNotGuessed (honest fallback,
    %   never a fabricated system number), noContextStaysBoltOnlyWithBasisStated
    %   (today's call shape, basis stated in the table itself),
    %   engagementRatioResolvesPerRowNominalDiameter (a fixed
    %   Insert/TappedHole template's EngagementRatio must still resolve a
    %   DIFFERENT Le per candidate size, scaled by THAT row's own
    %   NominalDiameter -- see model.ThreadedMember / resolveEngagementLength),
    %   insertStiPitchDiameterResolvesPerRow (a fixed Insert template's
    %   StiPitchDiameter is ALSO resolved per candidate size, from
    %   Library.insertFor, when a Library is supplied alongside it -- the
    %   real seeded NASM33537 catalogue, mirroring the Nut branch's
    %   per-row nutFor resolution), and misconfiguredThreadedMemberContextErrors
    %   (programming-error guards). MS_TensionYield, MS_Shear, and the interaction gate are
    %   UNCHANGED by any of this -- they stay bolt-only in every case,
    %   mirroring engine.marginTensionYield / engine.marginInteraction's
    %   own deliberate bolt-only rules (see boltSizingSweep.m's header).
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
        function tensionYieldShearAndInteractionMargins(testCase)
            % NAS1351 1/4-28 UNF (At=0.03637 in^2, MinorDiameter=0.2036 in,
            % NominalDiameter=0.25 in; +data/library.json), A286 (Ftu
            % 160,000 / Fty 120,000 / Fsu 93,400 psi, same file),
            % model.Factors() defaults (FSU 1.4, FFU 1.15, FSY 1.25,
            % FFY 1.0). PtL = 2,000 lbf, PsL = 500 lbf, BodyInShear.
            %
            % HAND-DERIVED (NASA-STD-5020B forms; no preload exists at
            % this sizing stage, so Ptu/Pty/Psu ARE the whole design
            % load — there is no preload term to add):
            %   Ptu_allow = At*Ftu = 0.03637*160,000      = 5,819.2 lbf
            %   Pty_allow = At*Fty = 0.03637*120,000      = 4,364.4 lbf
            %   Ptu = FSU*FFU*PtL  = 1.4*1.15*2,000       = 3,220 lbf
            %   Pty = FSY*FFY*PtL  = 1.25*1.0*2,000       = 2,500 lbf
            %   Psu = FSU*FFU*PsL  = 1.4*1.15*500         = 805 lbf
            %   MS_TensionUlt   = 5,819.2/3,220 - 1       = +0.807205 (Eq. 6)
            %   MS_TensionYield = 4,364.4/2,500 - 1       = +0.745760 (Eq. 15)
            %   BodyArea = pi/4*0.25^2                    = 0.0490874 in^2
            %   Psu_allow(body) = 93,400*0.0490874        = 4,584.76 lbf
            %   MS_Shear(body)  = 4,584.76/805 - 1        = +4.695356 (Eq. 12/14)
            %   Rt = 3,220/5,819.2   = 0.553341
            %   Rs = 805/4,584.76    = 0.175582
            %   R (Eq. 20/21, et=1.5/es=2.5) = Rt^1.5 + Rs^2.5
            %     Rt^1.5 = Rt*sqrt(Rt) = 0.553341*0.743868 = 0.411613
            %     Rs^2.5 = Rs^2*sqrt(Rs) = 0.030829*0.419026 = 0.012918
            %     R = 0.411613 + 0.012918 = 0.424531 <= 1 -> interaction
            %     gate PASSES (this is well inside the envelope; the old
            %     solve-for-a reading, a = 1.744126, agreed: a >= 1 iff
            %     R <= 1, same pass/fail direction).
            % Every core margin >= 0 AND the interaction gate passes ->
            % Status must be Pass, with no Notes explanation needed.
            [b, m, fac] = tBoltSizing.fixture();
            T = engine.boltSizingSweep(b, m, 2000, 500, fac, ...
                model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(T.ThreadSize(1), "1/4-28 UNF");
            testCase.verifyEqual(T.Spec(1), "NAS1351");
            testCase.verifyEqual(T.NominalDiameter, 0.25, "AbsTol", 1e-9);
            testCase.verifyEqual(T.At, 0.03637, "AbsTol", 1e-9);
            testCase.verifyEqual(T.MS_TensionUlt, 0.807205, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionYield, 0.745760, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_Shear, 4.695356, "AbsTol", 1e-5);
            testCase.verifyFalse(ismember("MS_Interaction", T.Properties.VariableNames));
            testCase.verifyEqual(T.Status, "Pass");
            testCase.verifyEqual(strlength(T.Notes), 0);   % gate passed, nothing to explain
        end

        function shearPlaneChangesAllowable(testCase)
            % Same fixture/loads (PtL=2,000, PsL=500) — only the shear
            % plane changes. Confirms ThreadsInShear uses MinorArea (NOT
            % the tensile stress area At) exactly like marginShearUlt.m,
            % giving a DIFFERENT, smaller allowable/margin than
            % BodyInShear.
            % HAND-DERIVED: MinorArea = pi/4*0.2036^2 = 0.0325566 in^2
            %   Psu_allow(threads) = 93,400*0.0325566 = 3,040.83 lbf
            %   MS_Shear(threads)  = 3,040.83/805 - 1  = +2.777430
            [b, m, fac] = tBoltSizing.fixture();
            Tbody = engine.boltSizingSweep(b, m, 2000, 500, fac, ...
                model.ShearPlaneCondition.BodyInShear);
            Tthread = engine.boltSizingSweep(b, m, 2000, 500, fac, ...
                model.ShearPlaneCondition.ThreadsInShear);
            testCase.verifyEqual(Tthread.MS_Shear, 2.777430, "AbsTol", 1e-5);
            testCase.verifyLessThan(Tthread.MS_Shear, Tbody.MS_Shear);
            % Both shear planes evaluate the interaction GATE (no NaN --
            % geometry is present for this fixture). HAND-DERIVED (Eq.
            % 22/23, et=2.0/es=1.2, the ThreadsInShear exponent pair):
            %   Rt = Ptu/PtuAllow = 3,220/5,819.2       = 0.553341 (same as
            %        the tension check -- Ptu/PtuAllow unchanged by
            %        shear plane)
            %   Rs = Psu/PsuAllow(threads) = 805/3,040.83 = 0.264730
            %   R = Rt^2.0 + Rs^1.2
            %     Rt^2.0 = 0.553341^2               = 0.306186
            %     Rs^1.2 = Rs * Rs^0.2, via ln/exp (non-integer exponent):
            %       ln(0.264730) = ln(0.25) + ln(0.264730/0.25)
            %                    = -1.386294 + ln(1.058920)
            %                    = -1.386294 + 0.057252 = -1.329042
            %       0.2 * (-1.329042) = -0.265808
            %       exp(-0.265808) = exp(-0.27) * exp(0.004192)
            %                      = 0.763379 * 1.004201 = 0.766586
            %       -> Rs^0.2 = 0.766586 -> Rs^1.2 = 0.264730*0.766586
            %                                       = 0.202917
            %     R = 0.306186 + 0.202917 = 0.509103 <= 1 -> gate PASSES
            %     (agrees with the retired solve-for-a reading, a =
            %     1.483829 >= 1, same pass/fail direction).
            % Both shear planes therefore pass the gate here, so neither
            % Tbody nor Tthread needs a Notes explanation.
            testCase.verifyEqual(strlength(Tbody.Notes), 0);
            testCase.verifyEqual(strlength(Tthread.Notes), 0);
            testCase.verifyEqual(Tbody.Status, "Pass");
            testCase.verifyEqual(Tthread.Status, "Pass");
        end

        function oneNegativeMarginFails(testCase)
            % Same bolt/material, PtL=2,000 (unchanged) but PsL=3,200,
            % BodyInShear — pushes the shear margin negative while tension
            % stays positive: ONE negative core margin must flip Status to
            % Fail even though 2 of 3 core margins are still healthy.
            % HAND-DERIVED:
            %   Psu = 1.4*1.15*3,200 = 5,152 lbf
            %   MS_Shear = 4,584.76/5,152 - 1 = -0.110101 (Fail, core)
            %   Rt = 0.553341 (unchanged); Rs = 5,152/4,584.76 = 1.123723
            %   R (Eq. 20/21) = Rt^1.5 + Rs^2.5:
            %     Rt^1.5 = 0.411613 (from tensionYieldShearAndInteractionMargins)
            %     Rs^2.5 = Rs^2*sqrt(Rs) = 1.262754*1.060058 = 1.338592
            %       (Rs^2 = 1.123723^2 = 1.262754; sqrt(1.123723): 1.06^2=
            %       1.1236, so sqrt(Rs) ~= 1.060058)
            %     R = 0.411613 + 1.338592 = 1.750205 > 1 -> interaction gate
            %     ALSO fails (agrees with the retired solve-for-a reading,
            %     a = 0.779014 < 1, same pass/fail direction).
            % Since MS_Shear already fails (coreOk = false), Notes uses the
            % "Also fails" wording, not the interaction-ONLY wording.
            [b, m, fac] = tBoltSizing.fixture();
            T = engine.boltSizingSweep(b, m, 2000, 3200, fac, ...
                model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(T.MS_TensionUlt, 0.807205, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionYield, 0.745760, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_Shear, -0.110101, "AbsTol", 1e-5);
            testCase.verifyEqual(T.Status, "Fail");
            testCase.verifyTrue(contains(T.Notes, "Also fails"));
            testCase.verifyTrue(contains(T.Notes, "interaction"));
        end

        function bothLoadsZeroGiveInfiniteMarginsAndPass(testCase)
            % PtL = PsL = 0: no preload and no applied load means no
            % failure mode is possible. Every allowable is a finite
            % positive number (At*Ftu / At*Fty / Fsu*area, all > 0)
            % divided by an exactly-zero design load, which is IEEE-754
            % +Inf, not NaN — see boltSizingSweep.m's header on the
            % decision. Rt = Rs = 0, so R = 0^1.5 + 0^2.5 = 0 <= 1 -- the
            % interaction gate passes with no special-case code needed
            % (direct R evaluation, unlike the retired solve-for-a
            % reading, handles this case for free).
            [b, m, fac] = tBoltSizing.fixture();
            T = engine.boltSizingSweep(b, m, 0, 0, fac, ...
                model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(T.MS_TensionUlt, Inf);
            testCase.verifyEqual(T.MS_TensionYield, Inf);
            testCase.verifyEqual(T.MS_Shear, Inf);
            testCase.verifyEqual(T.Status, "Pass");
            testCase.verifyEqual(strlength(T.Notes), 0);
        end

        function oneSidedZeroLoadStaysFinite(testCase)
            % PtL = 0 (pure-shear screen), PsL = 500, BodyInShear: the
            % TENSION margins are +Inf (zero tension load, as above).
            % HAND-DERIVED: Rt = 0, Rs = 805/4,584.76 = 0.175582 (same Psu
            % as the first test — PsL unchanged). With Rt = 0, Rt^1.5 = 0
            % for any nonnegative exponent, so R collapses to Rs^2.5 alone:
            %   R = 0^1.5 + 0.175582^2.5 = 0 + 0.012918 = 0.012918 <= 1
            %   (Rs^2.5 re-used from tensionYieldShearAndInteractionMargins)
            % Gate passes comfortably -- with no tension load at all, the
            % interaction envelope reduces to the shear check alone, which
            % is exactly the physical limit the retired solve-for-a
            % reading also showed (its a = 1/Rs = 5.695356, matching
            % MS_Shear exactly, since with Rt = 0 the envelope becomes
            % (a*Rs)^2.5 = 1).
            [b, m, fac] = tBoltSizing.fixture();
            T = engine.boltSizingSweep(b, m, 0, 500, fac, ...
                model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(T.MS_TensionUlt, Inf);
            testCase.verifyEqual(T.MS_TensionYield, Inf);
            testCase.verifyEqual(T.MS_Shear, 4.695356, "AbsTol", 1e-5);
            testCase.verifyEqual(T.Status, "Pass");
            testCase.verifyEqual(strlength(T.Notes), 0);
        end

        function sweepPreservesOrderAndMarksSmallestPasser(testCase)
            % Four bolts in LIBRARY ORDER (ascending nominal diameter,
            % UNC before UNF at the same diameter — +data/library.json):
            % #10-24 UNC, #10-32 UNF, 1/4-20 UNC, 1/4-28 UNF, all A286,
            % PtL=3,000 / PsL=300, ThreadsInShear (default). HAND-DERIVED
            % tension-ultimate:
            %   Ptu = 1.4*1.15*3,000 = 4,830 lbf
            %   #10-24 UNC (At=0.01753): Ptu_allow=2,804.80 lbf -> MS=-0.419296 (Fail)
            %   #10-32 UNF (At=0.01999): Ptu_allow=3,198.40 lbf -> MS=-0.337805 (Fail)
            %   1/4-20 UNC (At=0.03182): Ptu_allow=5,091.20 lbf -> MS=+0.054079
            %   1/4-28 UNF (At=0.03637): Ptu_allow=5,819.20 lbf -> MS=+0.204803
            % Rows 1-2 fail on tension-ultimate alone regardless of
            % interaction. Rows 3-4 pass tension/yield/shear individually,
            % but the Eq. 22/23 interaction GATE (ThreadsInShear, exp
            % 2.0/1.2) is evaluated for every row, and row 3's combined
            % tension+shear envelope is EXCEEDED even though neither the
            % tension nor the shear margin alone catches it -- exactly the
            % failure mode Eq. 20-23 exists to catch. This is the key case
            % for the gate: 1/4-20 UNC (row 3) fails ONLY on interaction.
            % HAND-DERIVED (Psu = 1.4*1.15*300 = 483; MinorArea/PsuAllow
            % per bolt as in shearPlaneChangesAllowable's pattern; Rt, Rs
            % as before -- R = Rt^2.0 + Rs^1.2, non-integer exponent via
            % ln/exp):
            %   #10-24 UNC: MinorArea=pi/4*0.1359^2=0.0145054, PsuAllow=1,354.80,
            %       Rt=4,830/2,804.80=1.722048, Rs=483/1,354.80=0.356510
            %       Rt^2 = 1.722048^2 = 2.965449
            %       Rs^1.2: ln(0.356510) = ln(0.35)+ln(1.018600)
            %             = -1.049822+0.018428 = -1.031394
            %             0.2*(-1.031394) = -0.206279
            %             exp(-0.206279) = exp(-0.2)*exp(-0.006279)
            %                            = 0.818731*0.993740 = 0.813605
            %             Rs^1.2 = 0.356510*0.813605 = 0.290059
            %       R = 2.965449+0.290059 = 3.255508 > 1 -> gate FAILS
            %       (core also fails on tension-ultimate alone, so Status
            %       was already Fail; matches the retired solve-for-a
            %       reading, a=0.539089 < 1, same direction)
            %   #10-32 UNF: MinorArea=pi/4*0.1494^2=0.0175304, PsuAllow=1,637.34,
            %       Rt=4,830/3,198.40=1.510130, Rs=483/1,637.34=0.294991
            %       Rt^2 = 1.510130^2 = 2.280493
            %       Rs^1.2: ln(0.294991) = ln(0.3)+ln(0.983303)
            %             = -1.203973-0.016827 = -1.220800
            %             0.2*(-1.220800) = -0.244160
            %             exp(-0.244160) = exp(-0.25)*exp(0.005840)
            %                            = 0.778801*1.005857 = 0.783362
            %             Rs^1.2 = 0.294991*0.783362 = 0.231085
            %       R = 2.280493+0.231085 = 2.511578 > 1 -> gate FAILS
            %       (core also fails on tension-ultimate; Status was
            %       already Fail; matches a=0.617778 < 1)
            %   1/4-20 UNC: MinorArea=pi/4*0.1850^2=0.0268803, PsuAllow=2,510.62,
            %       Rt=4,830/5,091.20=0.948696, Rs=483/2,510.62=0.192383
            %       Rt^2 = 0.948696^2 = 0.900023
            %       Rs^1.2: ln(0.192383) = ln(0.2)+ln(0.961915)
            %             = -1.609438-0.038824 = -1.648262
            %             0.2*(-1.648262) = -0.329652
            %             exp(-0.329652) = exp(-0.33)*exp(0.000348)
            %                            = 0.718924*1.000348 = 0.719174
            %             Rs^1.2 = 0.192383*0.719174 = 0.138357
            %       R = 0.900023+0.138357 = 1.038380 > 1 -> gate FAILS
            %       (matches the retired reading, a=0.980298 < 1) --
            %       tension-ultimate/tension-yield/shear ALL individually
            %       pass here (this row's core margins are unaffected by
            %       this rework); ONLY the interaction gate rejects it, so
            %       Notes must carry the "ONLY" wording and the reason.
            %   1/4-28 UNF: MinorArea=pi/4*0.2036^2=0.0325571, PsuAllow=3,040.83,
            %       Rt=4,830/5,819.20=0.830011, Rs=483/3,040.83=0.158838
            %       Rt^2 = 0.830011^2 = 0.688918
            %       Rs^1.2: ln(0.158838) = ln(0.16)+ln(0.992738)
            %             = -1.832581-0.007289 = -1.839870
            %             0.2*(-1.839870) = -0.367974
            %             exp(-0.367974) = exp(-0.37)*exp(0.002026)
            %                            = 0.690734*1.002028 = 0.692135
            %             Rs^1.2 = 0.158838*0.692135 = 0.109937
            %       R = 0.688918+0.109937 = 0.798855 <= 1 -> gate PASSES
            %       (matches a=1.125866 >= 1) -- core also passes, so row 4
            %       is a clean Pass with no Notes explanation.
            % So the sweep returns exactly this 4-row order (this function
            % must NOT re-sort), rows 1-3 Fail, row 4 Pass -- 1/4-28 UNF
            % (row 4) is the ONLY / smallest passer, and row 3 (1/4-20 UNC)
            % is the case that demonstrates the gate: rejected despite a
            % clean core, with the reason surfaced in Notes.
            lib = data.Library.load();
            m   = lib.material("A286");
            keys = ["NAS1352 #10-24", "NAS1351 #10-32", ...
                    "NAS1352 1/4-20",  "NAS1351 1/4-28"];
            bolts = model.Bolt.empty(1, 0);
            for i = 1:numel(keys)
                bolts(i) = lib.bolt(keys(i)); %#ok<AGROW>
            end
            fac = model.Factors();
            T = engine.boltSizingSweep(bolts, m, 3000, 300, fac, ...
                model.ShearPlaneCondition.ThreadsInShear);

            testCase.verifyEqual(height(T), 4);
            testCase.verifyEqual(T.ThreadSize, ["#10-24 UNC"; "#10-32 UNF"; ...
                "1/4-20 UNC"; "1/4-28 UNF"]);
            testCase.verifyEqual(T.MS_TensionUlt(1), -0.419296, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionUlt(2), -0.337805, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionUlt(3), 0.054079, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionUlt(4), 0.204803, "AbsTol", 1e-5);
            testCase.verifyFalse(ismember("MS_Interaction", T.Properties.VariableNames));
            testCase.verifyEqual(T.Status, ["Fail"; "Fail"; "Fail"; "Pass"]);

            % Rows 1-2: coreOk is already false (tension-ultimate fails),
            % so Notes uses the "Also fails" wording for the interaction
            % gate rather than the "ONLY" wording.
            testCase.verifyTrue(contains(T.Notes(1), "Also fails"));
            testCase.verifyTrue(contains(T.Notes(2), "Also fails"));

            % Row 3: the case this test exists for -- a size that clears
            % tension-ultimate, tension-yield and shear individually, yet
            % is rejected because it fails the interaction gate ALONE, and
            % that reason is surfaced in Notes rather than left as an
            % unexplained Fail.
            testCase.verifyGreaterThanOrEqual(T.MS_TensionYield(3), 0);
            testCase.verifyGreaterThanOrEqual(T.MS_Shear(3), 0);
            testCase.verifyTrue(contains(T.Notes(3), "interaction"));
            testCase.verifyTrue(contains(T.Notes(3), "ONLY"));
            testCase.verifyTrue(contains(T.Notes(3), "R = "));

            % Row 4: clean Pass, nothing to explain.
            testCase.verifyEqual(strlength(T.Notes(4)), 0);

            firstPass = find(T.Status == "Pass", 1);
            testCase.verifyEqual(firstPass, 4);
            testCase.verifyEqual(T.ThreadSize(firstPass), "1/4-28 UNF");
        end

        function sizeFailingOnlyOnInteractionIsRejectedAndExplained(testCase)
            % Isolates NAS1352 1/4-20 UNC (the same bolt/loads as row 3 of
            % sweepPreservesOrderAndMarksSmallestPasser) as a single-bolt
            % case: it clears tension-ultimate, tension-yield and shear
            % individually, yet Status must be Fail because the Eq. 22/23
            % interaction gate rejects it (R > 1) -- and that rejection
            % must be explained in Notes, not silently absorbed into an
            % unexplained Fail. This is the dedicated proof the task asks
            % for: a size failing ONLY on interaction is both rejected AND
            % explained.
            %
            % HAND-DERIVED (ThreadsInShear, PtL=3,000, PsL=300, A286;
            % NAS1352 1/4-20 UNC: At=0.03182, MinorDiameter=0.1850,
            % +data/library.json):
            %   Ptu = FSU*FFU*PtL = 1.4*1.15*3,000        = 4,830 lbf
            %   Pty = FSY*FFY*PtL = 1.25*1.0*3,000        = 3,750 lbf
            %   Psu = FSU*FFU*PsL = 1.4*1.15*300          = 483 lbf
            %   Ptu_allow = At*Ftu = 0.03182*160,000      = 5,091.20 lbf
            %   Pty_allow = At*Fty = 0.03182*120,000      = 3,818.40 lbf
            %   MinorArea = pi/4*0.1850^2                 = 0.0268803 in^2
            %   Psu_allow = 93,400*0.0268803               = 2,510.62 lbf
            %   MS_TensionUlt   = 5,091.20/4,830 - 1        = +0.054079 (Pass)
            %   MS_TensionYield = 3,818.40/3,750 - 1        = +0.018240 (Pass)
            %   MS_Shear        = 2,510.62/483 - 1          = +4.197971 (Pass)
            %   Rt = 4,830/5,091.20 = 0.948696; Rs = 483/2,510.62 = 0.192383
            %   R = Rt^2.0 + Rs^1.2 = 0.900023 + 0.138357 = 1.038380 > 1
            %       (re-derived longhand in sweepPreservesOrderAndMarksSmallestPasser
            %       above) -- interaction gate FAILS despite every core
            %       margin passing.
            lib = data.Library.load();
            b   = lib.bolt("NAS1352 1/4-20");
            m   = lib.material("A286");
            fac = model.Factors();
            T = engine.boltSizingSweep(b, m, 3000, 300, fac, ...
                model.ShearPlaneCondition.ThreadsInShear);

            testCase.verifyEqual(T.MS_TensionUlt, 0.054079, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionYield, 0.018240, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_Shear, 4.197971, "AbsTol", 1e-4);
            testCase.verifyGreaterThanOrEqual(T.MS_TensionUlt, 0);
            testCase.verifyGreaterThanOrEqual(T.MS_TensionYield, 0);
            testCase.verifyGreaterThanOrEqual(T.MS_Shear, 0);

            % Rejected...
            testCase.verifyEqual(T.Status, "Fail");
            % ...and explained: Notes must name the interaction gate as
            % the SOLE cause, not leave it as a mystery Fail alongside
            % three clean-looking margins.
            testCase.verifyTrue(strlength(T.Notes) > 0);
            testCase.verifyTrue(contains(T.Notes, "interaction"));
            testCase.verifyTrue(contains(T.Notes, "ONLY"));
            testCase.verifyFalse(contains(T.Notes, "Also fails"));
        end

        % ---- Threaded-member context (system-vs-bolt-only rework) --------

        function noContextStaysBoltOnlyWithBasisStated(testCase)
            % Today's call shape (no Library/NutSpec/ThreadedMember at all)
            % must keep EXACTLY today's bolt-only arithmetic -- reusing
            % tensionYieldShearAndInteractionMargins' fixture/loads
            % (MS_TensionUlt = 0.807205, hand-derived there) -- but the new
            % TensionUltBasis column must say so explicitly, in the output
            % table itself, not only in the function header.
            [b, m, fac] = tBoltSizing.fixture();
            T = engine.boltSizingSweep(b, m, 2000, 500, fac, ...
                model.ShearPlaneCondition.BodyInShear);
            testCase.verifyEqual(T.MS_TensionUlt, 0.807205, "AbsTol", 1e-5);
            testCase.verifyEqual(T.TensionUltBasis, ...
                "Bolt-only (no threaded-member context supplied)");
        end

        function nutGovernsBelowBoltFlipsPassToFail(testCase)
            % THE DEFECT THIS TASK EXISTS TO FIX: NAS1351 1/4-28 UNF + A286
            % (fixture()), PtL=3,000/PsL=300, ThreadsInShear -- the EXACT
            % same bolt/loads as row 4 of sweepPreservesOrderAndMarksSmallestPasser,
            % which showed a clean bolt-only Pass (MS_TensionUlt = +0.204803).
            % Supplying the NAS1291 nut family (the shipped library's
            % NAS1291C4M entry matches this bolt's 1/4-28 thread size)
            % reveals the nut is actually the governing tensile mode, and
            % MS_TensionUlt must now be NEGATIVE -- a bolt size the
            % bolt-only screen would have waved through actually fails a
            % full system-consistent check, exactly the scenario the task
            % describes.
            %
            % HAND-DERIVED (+data/library.json NAS1291C4M: height 0.219 in,
            % bearingDiameter 0.386, material "A286" (Fsu 93,400 psi),
            % ratedUltimateLoad 4,580 lbf; NAS1351 1/4-28 pitchDiameter
            % 0.2268 in):
            %   PtuAllowBolt = At*Ftu = 0.03637*160,000       = 5,819.2 lbf
            %   As (nut, TM-106943 Eq. 76 pitch-diameter form) = 0.75*pi*E*Le
            %     = 0.75*pi*0.2268*0.219                       = 0.11703030 in^2
            %   AllowUlt(nut, area basis) = Fsu*As = 93,400*0.11703030
            %                                                  = 10,930.6296 lbf
            %   nut EffUlt = min(AllowUlt, rating) = min(10,930.63, 4,580)
            %                                                  = 4,580 lbf
            %     (the rating GOVERNS the nut's own ultimate allowable --
            %     the computed area basis is far larger, so this is a
            %     clean, unambiguous "rating wins" case, not a knife-edge
            %     comparison)
            %   System Ptu_allow = min(bolt 5,819.2, nut 4,580) = 4,580 lbf
            %     -- the NUT governs, well below the bolt's own allowable.
            %   Ptu = FSU*FFU*PtL = 1.4*1.15*3,000            = 4,830 lbf
            %   MS_TensionUlt (system) = 4,580/4,830 - 1        = -0.051760
            %     (vs. the bolt-only +0.204803 the pre-existing screen would
            %     have reported for this exact bolt/load pair)
            %   Pty = FSY*FFY*PtL = 1.25*1.0*3,000             = 3,750 lbf
            %   PtyAllowBolt = At*Fty = 0.03637*120,000         = 4,364.4 lbf
            %   MS_TensionYield (ALWAYS bolt-only, per marginTensionYield's
            %     own rule) = 4,364.4/3,750 - 1                = +0.163840
            %   MinorArea = pi/4*0.2036^2                       = 0.03255708 in^2
            %   Psu = FSU*FFU*PsL = 1.4*1.15*300                = 483 lbf
            %   PsuAllow = 93,400*0.03255708                    = 3,040.831 lbf
            %   MS_Shear (ALWAYS bolt-only) = 3,040.831/483 - 1  = +5.295717
            %   Interaction Rt = Ptu/PtuAllowBolt (ALWAYS bolt-only, per
            %     marginInteraction's own deliberate rule) = 4,830/5,819.2
            %                                                  = 0.830011
            %   Rs = Psu/PsuAllow = 483/3,040.831                = 0.158838
            %   R (Eq. 22/23, ThreadsInShear) = Rt^2.0 + Rs^1.2
            %                                 = 0.688918 + 0.109937 = 0.798856
            %     <= 1 -> interaction gate PASSES (matches the longhand
            %     re-derivation in sizeFailingOnlyOnInteractionIsRejectedAndExplained,
            %     R = 1.038380, for the DIFFERENT bolt/Rt/Rs there -- not
            %     reused, just the same method).
            % core = [-0.051760, +0.163840, +5.295717] -- one negative ->
            % coreOk = false -> Status = Fail. interactionOk is TRUE (gate
            % passes), so Notes stays EMPTY (Notes only ever explains an
            % interaction-gate-caused Fail, per the header/Status rules) --
            % the explanation for THIS Fail lives in TensionUltBasis
            % instead, which is exactly the column this task added.
            lib = data.Library.load();
            b   = lib.bolt("NAS1351 1/4-28");
            m   = lib.material("A286");
            fac = model.Factors();
            T = engine.boltSizingSweep(b, m, 3000, 300, fac, ...
                model.ShearPlaneCondition.ThreadsInShear, ...
                Library = lib, NutSpec = "NAS1291");

            testCase.verifyEqual(T.MS_TensionUlt, -0.051760, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionYield, 0.163840, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_Shear, 5.295717, "AbsTol", 1e-5);
            testCase.verifyTrue(contains(T.TensionUltBasis, "System"));
            testCase.verifyTrue(contains(T.TensionUltBasis, "nut thread shear"));
            testCase.verifyEqual(T.Status, "Fail");
            testCase.verifyEqual(strlength(T.Notes), 0);
        end

        function noMatchingNutFallsBackToBoltOnlyHonestly(testCase)
            % NAS1352 #10-24 UNC (0.19 in, 24 tpi) does not exist in the
            % NASM21042 family at all -- that family's smallest UNF/UNC
            % entry at nominalDiameter 0.19 is tpi 32 (NASM21042-3, a
            % #10-32), not 24. Library.nutFor(0.19, 24, "NASM21042") must
            % therefore return no match, and this row must fall back to
            % the SAME bolt-only number the no-context path would have
            % given -- reusing row 1 of
            % sweepPreservesOrderAndMarksSmallestPasser (MS_TensionUlt =
            % -0.419296, PtL=3,000/PsL=300, ThreadsInShear) -- NEVER a
            % fabricated system number, and the basis column must say
            % plainly that no match was found.
            lib = data.Library.load();
            b   = lib.bolt("NAS1352 #10-24");
            m   = lib.material("A286");
            fac = model.Factors();
            T = engine.boltSizingSweep(b, m, 3000, 300, fac, ...
                model.ShearPlaneCondition.ThreadsInShear, ...
                Library = lib, NutSpec = "NASM21042");

            testCase.verifyEqual(T.MS_TensionUlt, -0.419296, "AbsTol", 1e-5);
            testCase.verifyTrue(contains(T.TensionUltBasis, "Bolt-only"));
            testCase.verifyTrue(contains(T.TensionUltBasis, "NASM21042"));
            testCase.verifyTrue(contains(T.TensionUltBasis, "no"));
        end

        function unassessedThreadedMemberRefusedNotGuessed(testCase)
            % A fixed ThreadedMember template (TappedHole -- no per-size
            % catalog resolution applies) whose parent Material carries no
            % Fsu (model.Material() defaults every strength field to NaN):
            % memberTensileUltAllowable's TappedHole branch cannot form an
            % allowable at all (needs Bolt.PitchDiameter AND
            % EngagementLength AND the parent Fsu) and reports
            % Assessed=false with a Reason -- this must NOT be silently
            % treated as an assessed system value, and the row must fall
            % back to the EXACT SAME bolt-only number as the no-context
            % test above (same fixture/loads: MS_TensionUlt = 0.807205),
            % never a guessed or partially-computed number.
            [b, m, fac] = tBoltSizing.fixture();
            tm = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.TappedHole, ...
                Material = model.Material(), ...      % Fsu = NaN (default)
                EngagementLength = 0.3);
            T = engine.boltSizingSweep(b, m, 2000, 500, fac, ...
                model.ShearPlaneCondition.BodyInShear, ...
                ThreadedMember = tm);

            testCase.verifyEqual(T.MS_TensionUlt, 0.807205, "AbsTol", 1e-5);
            testCase.verifyTrue(contains(T.TensionUltBasis, "Bolt-only"));
            testCase.verifyTrue(contains(T.TensionUltBasis, "tapped-hole parent thread not assessed"));
            testCase.verifyTrue(contains(T.TensionUltBasis, "Fsu"));
        end

        function engagementRatioResolvesPerRowNominalDiameter(testCase)
            % EngagementRatio on a FIXED TappedHole template (no per-size
            % insert/tapped catalog exists -- see boltSizingSweep's header)
            % must still resolve a DIFFERENT Le for EACH candidate bolt
            % size, because Le = EngagementRatio x THAT row's own
            % Bolt.NominalDiameter (resolveEngagementLength, called
            % per-row via the throwaway joint built inside
            % boltSizingSweep -- the SAME template object is reused
            % unchanged for every row, so only the per-row re-resolution
            % of Le, not the template itself, can be responsible for the
            % two different numbers below). This is the whole point of
            % EngagementRatio (see model.ThreadedMember's header): a fixed
            % EngagementLength inch value on this one shared template
            % would be correct for at most one row.
            %
            % HAND-DERIVED, straight from the shipped library
            % (+data/library.json): #10-24 (D=0.19, E=0.1629, At=0.01753)
            % and 1/4-28 (D=0.25, E=0.2268, At=0.03637), both NAS1351/1352
            % A286 (Ftu=160,000 psi). EngagementRatio = 1.5 -> Le = 1.5*D:
            %   #10-24: Le = 1.5*0.19  = 0.285 in
            %           As = 0.75*pi*0.1629*0.285 = 0.1093899 in^2
            %   1/4-28: Le = 1.5*0.25  = 0.375 in
            %           As = 0.75*pi*0.2268*0.375 = 0.2003943 in^2
            % Parent Fsu = 20,000 psi (arbitrary, chosen low enough that
            % the tapped-hole thread-shear mode GOVERNS the system minimum
            % over the bolt-only Ptu_allow = At*Ftu on both rows, so this
            % test actually exercises the ratio-driven area, not a
            % bolt-only fallback):
            %   Pult = Fsu*As: #10-24 2187.797 lbf ; 1/4-28 4007.887 lbf
            %   (bolt-only At*Ftu: #10-24 2804.8 lbf ; 1/4-28 5819.2 lbf --
            %   both larger, so the tapped-hole mode governs on both rows)
            % Ptu = FSU*FFU*PtL = 1.4*1.15*500 = 805 lbf (default Factors)
            %   MS_TensionUlt = Pult/Ptu - 1:
            %     #10-24: 2187.797/805 - 1 = 1.717761
            %     1/4-28: 4007.887/805 - 1 = 3.978741
            lib = data.Library.load();
            b1  = lib.bolt("NAS1352 #10-24");   % D = 0.19 in
            b2  = lib.bolt("NAS1351 1/4-28");   % D = 0.25 in
            m   = lib.material("A286");
            fac = model.Factors();
            parentMat = model.Material(Fsu = 20000);
            tm = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.TappedHole, ...
                Material = parentMat, ...
                EngagementRatio = 1.5);

            T = engine.boltSizingSweep([b1, b2], m, 500, 100, fac, ...
                model.ShearPlaneCondition.ThreadsInShear, ...
                ThreadedMember = tm);

            testCase.verifyTrue(all(contains(T.TensionUltBasis, "System")));
            testCase.verifyTrue(all(contains(T.TensionUltBasis, "tapped-hole parent thread")));
            testCase.verifyEqual(T.MS_TensionUlt(1), 1.717761, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionUlt(2), 3.978741, "AbsTol", 1e-5);
            % Not equal -- the whole point: one ratio, two different
            % Le/As/Pult, each scaled by that row's OWN NominalDiameter.
            testCase.verifyNotEqual(T.MS_TensionUlt(1), T.MS_TensionUlt(2));
        end

        function insertStiPitchDiameterResolvesPerRow(testCase)
            % Mirrors engagementRatioResolvesPerRowNominalDiameter, but for
            % an Insert template's StiPitchDiameter (the NEW per-row
            % resolution this task added): a Library supplied alongside a
            % fixed Insert ThreadedMember template must resolve EACH
            % candidate size's OWN StiPitchDiameter via Library.insertFor,
            % so the COMPUTED area (engine.marginInsert's
            % As = 0.75·pi·D2·(Le-1.125·p) fallback) varies row-to-row —
            % the same "one template, many per-row numbers" pattern the
            % ratio test proves for Le, now proven for D2.
            %
            % HAND-DERIVED, straight from the shipped library
            % (+data/library.json inserts section, real NASM33537 seeded
            % values -- not illustrative numbers):
            %   #10-24 (D=0.19, TPI=24, At=0.01753): insertFor ->
            %     StiPitchDiameterMin = 0.2170 in
            %   1/4-28  (D=0.25, TPI=28, At=0.03637): insertFor ->
            %     StiPitchDiameterMin = 0.2732 in
            % Both NAS1351/1352 A286 (Ftu=160,000 psi). EngagementRatio =
            % 1.5 -> Le = 1.5*D (mirrors the ratio test):
            %   #10-24: Le = 1.5*0.19 = 0.285 in, TPI 24 -> p = 1/24 = 0.041667 in
            %     netLe = 0.285 - 1.125*0.041667 = 0.238125 in
            %     As    = 0.75*pi*0.2170*0.238125 = 0.1217519 in^2
            %   1/4-28: Le = 1.5*0.25 = 0.375 in, TPI 28 -> p = 1/28 = 0.035714 in
            %     netLe = 0.375 - 1.125*0.035714 = 0.334821 in
            %     As    = 0.75*pi*0.2732*0.334821 = 0.2155287 in^2
            % Parent Fsu = 20,000 psi (arbitrary, low enough that the
            % insert mode GOVERNS the system minimum over the bolt-only
            % Ptu_allow = At*Ftu on both rows, exactly as
            % engagementRatioResolvesPerRowNominalDiameter chose for the
            % tapped-hole case -- so this test actually exercises the
            % per-row D2, not a bolt-only fallback):
            %   Pult = Fsu*As: #10-24 2,435.04 lbf ; 1/4-28 4,310.57 lbf
            %   (bolt-only At*Ftu: #10-24 2,804.80 lbf ; 1/4-28 5,819.20 lbf
            %   -- both larger, so the insert mode governs on both rows)
            % Ptu = FSU*FFU*PtL = 1.4*1.15*500 = 805 lbf (default Factors)
            %   MS_TensionUlt = Pult/Ptu - 1:
            %     #10-24: 2435.04/805 - 1 = 2.024893
            %     1/4-28: 4310.57/805 - 1 = 4.354750
            lib = data.Library.load();
            b1  = lib.bolt("NAS1352 #10-24");   % D = 0.19 in, TPI 24
            b2  = lib.bolt("NAS1351 1/4-28");    % D = 0.25 in, TPI 28
            m   = lib.material("A286");
            fac = model.Factors();
            parentMat = model.Material(Name="insert parent (per-row D2 pin)", Fsu = 20000);
            tm = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.Insert, ...
                Material = parentMat, ...
                EngagementRatio = 1.5);

            T = engine.boltSizingSweep([b1, b2], m, 500, 100, fac, ...
                model.ShearPlaneCondition.ThreadsInShear, ...
                Library = lib, ThreadedMember = tm);

            testCase.verifyTrue(all(contains(T.TensionUltBasis, "System")));
            testCase.verifyTrue(all(contains(T.TensionUltBasis, "insert pull-out")));
            testCase.verifyEqual(T.MS_TensionUlt(1), 2.024893, "AbsTol", 1e-5);
            testCase.verifyEqual(T.MS_TensionUlt(2), 4.354750, "AbsTol", 1e-5);
            % Not equal -- the whole point: one template, two different
            % StiPitchDiameter/As/Pult, each resolved from THAT row's own
            % bolt thread size.
            testCase.verifyNotEqual(T.MS_TensionUlt(1), T.MS_TensionUlt(2));

            % A size with NO helical insert catalogued at all (#0-80,
            % #5-44 -- absent from both NASM33537 and the Stanley
            % catalogue, see model.ThreadedMember's StiPitchDiameter doc)
            % must fall back to the SAME honest bolt-only number the
            % no-match nut case does -- never a fabricated system value,
            % and TensionUltBasis must say plainly that the insert mode
            % was not assessed (StiPitchDiameter never got set for this
            % row's template copy).
            b3 = lib.bolt("NAS1351 #0-80");
            T2 = engine.boltSizingSweep(b3, m, 500, 100, fac, ...
                model.ShearPlaneCondition.ThreadsInShear, ...
                Library = lib, ThreadedMember = tm);
            testCase.verifyTrue(contains(T2.TensionUltBasis, "Bolt-only"));
            testCase.verifyTrue(contains(T2.TensionUltBasis, "insert pull-out not assessed"));
        end

        function misconfiguredThreadedMemberContextErrors(testCase)
            % Programming-error guards, not data limitations: each one
            % must fail loudly with a specific error id rather than
            % silently doing something the caller did not ask for.
            [b, m, fac] = tBoltSizing.fixture();
            lib = data.Library.load();

            % NutSpec without Library -- can't resolve anything.
            testCase.verifyError(@() engine.boltSizingSweep(b, m, 2000, 500, ...
                fac, model.ShearPlaneCondition.BodyInShear, NutSpec = "NAS1291"), ...
                "engine:boltSizingSweep:missingLibrary");

            % Library without NutSpec (and no ThreadedMember template) --
            % nothing tells the sweep which nut family to resolve.
            testCase.verifyError(@() engine.boltSizingSweep(b, m, 2000, 500, ...
                fac, model.ShearPlaneCondition.BodyInShear, Library = lib), ...
                "engine:boltSizingSweep:missingNutSpec");

            % NutSpec AND a fixed ThreadedMember template together --
            % mutually exclusive resolution strategies.
            tmInsert = model.ThreadedMember(Type = model.ThreadedMemberType.Insert);
            testCase.verifyError(@() engine.boltSizingSweep(b, m, 2000, 500, ...
                fac, model.ShearPlaneCondition.BodyInShear, ...
                Library = lib, NutSpec = "NAS1291", ThreadedMember = tmInsert), ...
                "engine:boltSizingSweep:conflictingThreadedMemberContext");

            % A fixed ThreadedMember template with Type Nut -- a nut
            % varies by thread size, so a FIXED template can never be
            % right for it; the caller must use Library+NutSpec instead.
            tmNut = model.ThreadedMember(Type = model.ThreadedMemberType.Nut);
            testCase.verifyError(@() engine.boltSizingSweep(b, m, 2000, 500, ...
                fac, model.ShearPlaneCondition.BodyInShear, ...
                ThreadedMember = tmNut), ...
                "engine:boltSizingSweep:useNutSpecForNut");
        end

        function templateCarryingStiPitchDiameterIsRefused(testCase)
            % StiPitchDiameter varies by thread size, so it cannot ride in
            % one template applied across a sweep -- the same category of
            % mistake as the Nut template refused just above.
            %
            % REGRESSION GUARD for a silent wrong number. The per-row
            % Library.insertFor overwrite only fires when a Library was
            % supplied AND that row's size matches. A template arriving
            % with StiPitchDiameter already set -- e.g. a ThreadedMember
            % lifted off a Joint that gui.FastenerApp.buildJoint had
            % already resolved -- was otherwise reused for EVERY candidate
            % size, with Detail affirmatively labelling it the NASM33537
            % value for that row. Non-conservative whenever the template's
            % size exceeds the row's: a 3/8-24 D2 (0.4020 in) applied to a
            % #10-32 row nearly doubles the true 0.2103 in, roughly
            % doubling the insert pull-out allowable and able to show Pass
            % where the insert-governed margin actually fails.
            %
            % The GUI never hit this -- collectBoltSizingMemberSelection
            % builds a fresh template and tBoltSizingMemberArgs.m's
            % insertTemplateNeverCarriesAStiPitchDiameter pins that -- but
            % the headless/API path is a supported workflow (CLAUDE.md).
            b   = [data.Library.load().bolt("NAS1351 #10-32"), ...
                   data.Library.load().bolt("NAS1351 3/8-24")];
            m   = data.Library.load().material("A286");
            fac = model.Factors();
            tmSti = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.Insert, ...
                Material = data.Library.load().material("Al 6061-T6"), ...
                EngagementRatio = 1.5, StiPitchDiameter = 0.4020);
            testCase.verifyError(@() engine.boltSizingSweep(b, m, 2000, 500, ...
                fac, model.ShearPlaneCondition.BodyInShear, ...
                ThreadedMember = tmSti), ...
                "engine:boltSizingSweep:templateCarriesPerSizeGeometry");
            % Refused with a Library present too -- supplying one does not
            % launder a template value, since a row whose size misses the
            % catalogue would still fall back to it.
            testCase.verifyError(@() engine.boltSizingSweep(b, m, 2000, 500, ...
                fac, model.ShearPlaneCondition.BodyInShear, ...
                ThreadedMember = tmSti, Library = data.Library.load()), ...
                "engine:boltSizingSweep:templateCarriesPerSizeGeometry");
        end
    end

    methods (Static)
        function [b, m, fac] = fixture()
            %FIXTURE  NAS1351 1/4-28 UNF + A286 + default Factors, straight
            %   from the shipped library (+data/library.json).
            lib = data.Library.load();
            b   = lib.bolt("NAS1351 1/4-28");
            m   = lib.material("A286");
            fac = model.Factors();
        end
    end
end
