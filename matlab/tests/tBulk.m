classdef tBulk < matlab.unittest.TestCase
    %TBULK  engine.analyzeBulk end-to-end: full pipeline acceptance.
    %   The full bulk pipeline — data.loadJointLibrary (template CSV,
    %   joint-table layout) + data.loadSettings (global temps + factors) ->
    %   engine.loadCaseFromForces -> engine.analyze — must resolve loads
    %   without throwing, handle a missing joint gracefully, and emit the
    %   documented table shape.
    %
    %   The shipped joint_library_template.csv's first row ("Sample
    %   four-bolt SHCS/nut joint") is a representative demo joint built
    %   from real catalog hardware (NAS1351 3/8-24, A286, Al 7075-T7351) in
    %   a DABJ-Section-9-like configuration (bolt count, torque, factors) —
    %   not the DABJ validation fixture itself, which builds its own
    %   geometry inline (see validation.dabjSection9) so the answer key
    %   does not depend on library content.
    %
    %   The demo row's BoltSpec lookup hits library.json's NAS1351 3/8-24 +
    %   A286 pairing, so BoltRatedUltimateLoad / BoltRatedYieldLoad arrive
    %   as the FF-S-86F Table VII spec values, 14,050 / 10,500 lbf.
    %   boltTensileAllowable therefore takes its "rated" basis, not the
    %   derived At*Ftu convention per NASA-STD-5020B §4.4.2 and not the
    %   Eq. 18 yield estimate — 5020B offers Eq. 18 only "when a value is
    %   not explicitly defined in the corresponding fastener specification",
    %   and here one is. Tension-Yield resolves to a real, negative number
    %   (~-1.368): the same Fig. 8 gate this row's Tension-Ultimate uses
    %   (see below) is not assured here, so engine.marginTensionYield also
    %   takes the not-assured Eq. 16/17 branch (P'ty = (Pty_allow -
    %   PpMax)/(n*phi), then MS = P'ty/Pty - 1), and Pty_allow (10,500) is
    %   itself below PpMax (11,006.78), so the joint is genuinely
    %   over-torqued relative to its rated yield allowable (the same fact
    %   engine.preloadWatchdog reports on this row as a Critical warning —
    %   see tExport.m's runBulkEndToEnd). Eq. 15 never subtracts preload
    %   and would not surface this.
    %   engine.marginInteraction resolves a real Interaction ratio R too,
    %   carried on the bulk table's InteractionR column, sourced from
    %   Result.Margins("Interaction").R, not .MS (see engine.analyzeBulk's
    %   header and engine.analyze's INTERACTION IS NOT A MARGIN note) —
    %   verified both against the table and directly against the engine
    %   below.
    %
    %   Tension-Ultimate also resolves to a real number on this row: the
    %   row carries BodyLengthInGrip = 0.50 in (grip = 0.75 in, no washers)
    %   and NutHeight = 0.328 in (see data.makeTemplate's sampleNutJointRow
    %   for the geometry reasoning), so engine.stiffness computes Kb/Kc/phi
    %   instead of erroring. ThermalRate is not an analyst-facing column
    %   (it remains a model.PreloadSpec field set only by validation
    %   fixtures), so this row's thermal preload comes from the same
    %   stiffness geometry via TM-106943 Eq. 10, giving PpMax
    %   ~11,006.78 lbf. The rated Ptu_allow (14,050 lbf) is still low
    %   enough that the Fig. 8 preload gate is not assured (11,006.78
    %   exceeds 0.75*14,050 = 10,537.5), so the rupture branch
    %   (NASA-STD-5020B Eq. 10) governs, evaluating to a real margin rather
    %   than NaN. Force resolution (Axial/Shear) and the joint-mode-slip nf
    %   check both run before the margin solver, so they populate
    %   correctly regardless.
    %
    %   bulkJointSlipFromPatternAggregation is the one exception: its whole
    %   point is Eq. 84's joint-mode aggregation math, which needs a joint
    %   that can actually reach the Slip check. It builds its joint from
    %   validation.dabjSection9() directly (in-code, library-independent)
    %   instead of the shipped template, and pins the exact -0.65 answer
    %   key. The other tests below use the shipped template CSV and are
    %   structural pipeline checks, not answer-key reproductions; the
    %   published DABJ §9 numbers are pinned separately by tests/tDabjCase.m
    %   and the dabjSection9RegressionUnchanged guards in
    %   tThreadShear.m/tBearing.m.
    %
    %   Temperatures are global: the joint table carries no temperature
    %   columns, so each test applies the settings-template temps
    %   (NominalTempC/HotTempC/ColdTempC -> Reference/Max/MinTemperature) to
    %   the parsed joints exactly the way engine.runBulk does.
    %
    %   The demo element's forces are chosen so the bolt-axis resolution
    %   lands on representative per-bolt loads: BoltAxis = Z (the AxialZ
    %   mark in the template), so FZ = 5590 -> axial and FX = 1560
    %   (FY = 0) -> shear RSS = 1560.
    %
    %   Joint-mode slip: analyzeBulk aggregates the bolt pattern (same
    %   PatternId-or-JointName + load case), vector-sums the element forces
    %   into the joint totals, and evaluates Eq. 84 only when the pattern's
    %   element count equals Joint.BoltCount (the nf check). A count
    %   mismatch must leave Slip NaN with a Note saying why.
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
        function p = templatePath(name)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            p = string(fullfile(srcDir, "templates", name));
        end

        function [jl, s] = dabjLibraryWithSettings()
            %DABJLIBRARYWITHSETTINGS  Template joints + settings, temps applied.
            %   Parses the joint template, loads the settings template, and
            %   applies the global temperatures to every joint — the same
            %   pre-analysis step engine.runBulk performs.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulk.templatePath("joint_library_template.csv"), lib);
            s   = data.loadSettings( ...
                tBulk.templatePath("settings_template.csv"));
            for i = 1:numel(jl)
                j = jl(i).Joint;
                j.ReferenceTemperature = s.NominalTempC;
                j.MaxTemperature       = s.HotTempC;
                j.MinTemperature       = s.ColdTempC;
                jl(i).Joint = j;
            end
        end

        function [jl, fac] = dabjInlineJointWithFactors()
            %DABJINLINEJOINTWITHFACTORS  The DABJ §9 fixture as a one-entry
            %   joint library, built in-code via validation.dabjSection9
            %   (library-independent) rather than parsed from the shipped
            %   template. The shipped demo row ("Sample four-bolt SHCS/nut
            %   joint") also analyzes cleanly, including a real
            %   Tension-Ultimate (it carries BodyLengthInGrip/NutHeight —
            %   see the class header), but with derived allowables from
            %   catalog data, not the book's rated loads. This fixture
            %   instead carries the complete, exact §9 geometry (a real
            %   BoltRatedYieldLoad and full frustum inputs), so it can
            %   reach every margin check against the published answer key
            %   numbers — used only where a test's point requires that
            %   (bulkJointSlipFromPatternAggregation, bulkResultsTableShape).
            %   The local Name below is deliberately c.Name ("DABJ Section
            %   9 class problem", the fixture's own identity), not the
            %   shipped template row's name, so this wrapper can never be
            %   confused with (or accidentally coupled to) the template.
            c = validation.dabjSection9();
            jl = struct('Name', c.Name, 'Joint', c.Joint);
            fac = c.Factors;
        end

        function el = dabjElement(jointName)
            %DABJELEMENT  One in-code element that resolves to representative
            %   per-bolt loads (BoltAxis Z: FZ -> axial, FX/FY -> shear).
            %   jointName is REQUIRED (not defaulted) so every call site
            %   states, explicitly, which joint library it must match — the
            %   shipped template's demo row (dabjLibraryWithSettings, via
            %   jl(1).Name) or the DABJ §9 fixture wrapper
            %   (dabjInlineJointWithFactors, also via jl(1).Name) — rather
            %   than relying on the two happening to share a literal string.
            arguments
                jointName (1,1) string
            end
            el = struct( ...
                "ElementId",    "9001", ...
                "JointName",    jointName, ...
                "LoadCaseName", "DABJ Sec. 9 per-bolt limit loads", ...
                "Forces",       struct("FX", 1560, "FY", 0, "FZ", 5590, ...
                                       "MX", 0, "MY", 0, "MZ", 0), ...
                "ScaleFactor",  1, ...
                "Reversible",   false);
        end

        function els = dabjPatternElements(jointName)
            %DABJPATTERNELEMENTS  The demo joint's four-bolt pattern as four
            %   elements. Forces split the book's JOINT totals evenly
            %   (Solutions-22, option 1): sum FZ = 4 x 4022.5 = 16,090 lb and
            %   sum FX = 4 x 1422.5 = 5,690 lb, so the aggregation pre-pass
            %   feeds Eq. 84 the same joint totals the book works with.
            %   jointName is REQUIRED -- see dabjElement.
            arguments
                jointName (1,1) string
            end
            proto = tBulk.dabjElement(jointName);
            proto.LoadCaseName = "DABJ Sec. 9 joint totals";
            proto.Forces = struct("FX", 1422.5, "FY", 0, "FZ", 4022.5, ...
                                  "MX", 0, "MY", 0, "MZ", 0);
            els = repmat(proto, 1, 4);
            for i = 1:4
                els(i).ElementId = "910" + i;   % "9101".."9104"
            end
        end
    end

    methods (Test)
        function bulkRunsTemplateJointWithoutCrashing(testCase)
            % Template joint library (row 1 is the demo joint, carrying
            % BodyLengthInGrip/NutHeight; see the class header) + the
            % settings template (global temps + factors) + one in-code
            % element -> the bulk row must resolve its per-bolt loads
            % correctly and analyze cleanly (no Error): Tension-Yield/
            % Interaction fall back to the derived allowable, and
            % Tension-Ultimate resolves to a real rupture-branch margin
            % (stiffness geometry is available on this row).
            [jl, s] = tBulk.dabjLibraryWithSettings();

            T = engine.analyzeBulk(jl, tBulk.dabjElement(jl(1).Name), s.Factors);
            testCase.assertEqual(height(T), 1);

            % Force resolution.
            testCase.verifyEqual(T.Axial(1), 5590, "AbsTol", 1e-9);
            testCase.verifyEqual(T.Shear(1), 1560, "AbsTol", 1e-9);

            % The row analyzes without error.
            testCase.verifyEqual(T.Error(1), "");

            % Tension-Yield falls back to the derived allowable
            % (boltTensileAllowable: Eq. 18) for Pty_allow, but which of
            % Eq. 15 / Eq. 16-17 governs is decided by the same Fig. 8 gate
            % engine.marginTensionYield shares with Tension-Ultimate (both
            % call the private separationBeforeRuptureGate helper, so they
            % can never disagree about which branch applies) — and per the
            % Tension-Ultimate derivation below, that gate is not assured
            % on this row (PpMax 11,006.78 > 0.75*Ptu_allow 10,537.5), so
            % Tension-Yield also takes the rupture-side branch, Eq. 16/17,
            % not the separation-assured Eq. 15.
            % HAND-DERIVED, longhand (phi = 0.394005, PpMax = 11,006.78,
            % n = 0.5 -- the identical stiffness/preload chain the
            % Tension-Ultimate derivation below works out in full; only the
            % allowable changes, bolt yield instead of bolt ultimate):
            %   Pty_allow = 10,500 lbf, the FF-S-86F Table VII rated yield
            %             load for NAS1351 3/8-24 in A286 -- taken as-is,
            %             NOT estimated via Eq. 18, because 5020B offers
            %             that estimate only when the fastener spec does
            %             not define a value.
            %   P'ty = (Pty_allow - PpMax)/(n*phi)
            %        = (10,500 - 11,006.78)/(0.5*0.394005)
            %        = -506.78/0.197003 = -2,572.45 lbf            (Eq. 17)
            %   Pty  = FSY*FFY*Axial = 1.25*1*5590 = 6,987.5 lbf
            %   MS   = P'ty/Pty - 1 = -2,572.45/6,987.5 - 1 = -1.3682 (Eq. 16)
            % Pty_allow is itself below PpMax (10,500 < 11,006.78), so the
            % numerator of Eq. 17 is negative before the division even
            % starts — this is a genuinely over-torqued joint (the same
            % fact engine.preloadWatchdog reports on this row, see
            % tExport.m's runBulkEndToEnd Warnings check: PpMax is 104.8% of
            % this same 10,500 rated yield allowable), not a defect. Eq. 15
            % never subtracts preload and would not surface this.
            testCase.verifyFalse(isnan(T.TensionYield(1)));
            expectedPtuAllow = 14050;   % FF-S-86F Tbl VII, NAS1351 3/8-24 + A286
            expectedPtyAllow = 10500;   % FF-S-86F Tbl VII rated yield (no Eq. 18)
            phi = 0.394005;   n = 0.5;   PpMax = 11006.78;      % from the Tension-Ultimate derivation below
            fac = s.Factors;
            Pty = fac.FSY * fac.FFY * 5590;
            Pprime = (expectedPtyAllow - PpMax) / (n * phi);     % Eq. 17
            expectedTensionYield = Pprime / Pty - 1;             % Eq. 16
            testCase.verifyEqual(T.TensionYield(1), expectedTensionYield, "AbsTol", 1e-3);
            testCase.verifyEqual(T.TensionYield(1), -1.3682, "AbsTol", 1e-3);
            testCase.verifyLessThan(T.TensionYield(1), 0);   % over-torqued: assert the sign plainly

            % Interaction: T.InteractionR carries the real ratio R
            % directly, sourced from Result.Margins("Interaction").R, not
            % .MS (see engine.analyzeBulk's header). Verify it both against
            % the bulk table and independently, straight from
            % engine.marginInteraction, not copied from the engine's own
            % output.
            %
            % NASA-STD-5020B Eq. 20/21 criterion (body in shear, exp
            % 1.5/2.5): Psu_allow = Fsu*BodyArea with the catalog A286
            % Fsu = 93,400 psi and the NAS1351 3/8-24's 0.375-in body dia.
            %   Rt = Ptu/Ptu_allow, Rs = Psu/Psu_allow
            %   R  = Rt^1.5 + Rs^2.5   (direct evaluation, no root-find)
            % -- recomputed here from the same raw constants the engine
            % uses (not copied from its output), so this is an independent
            % check.
            Ptu      = fac.FSU * fac.FFU * 5590;
            Psu      = fac.FSU * fac.FFU * 1560;
            PsuAllow = 93400 * (pi/4 * 0.375^2);          % A286 Fsu * BodyArea
            Rt       = Ptu / expectedPtuAllow;
            Rs       = Psu / PsuAllow;
            % Rt = 0.640562, Rs = 0.243473 ->
            % R = 0.640562^1.5 + 0.243473^2.5 = 0.512675 + 0.029250 = 0.541925
            expectedR = Rt^1.5 + Rs^2.5;
            testCase.verifyEqual(T.InteractionR(1), expectedR, "AbsTol", 1e-6);
            testCase.verifyEqual(T.InteractionR(1), 0.541925, "AbsTol", 1e-4);
            d  = struct("Ptu", Ptu, "Pty", NaN, "Psu", Psu, "Psep", NaN);
            ia = engine.marginInteraction(jl(1).Joint, d);
            testCase.verifyEqual(ia.R, expectedR, "AbsTol", 1e-6);
            testCase.verifyEqual(ia.R, 0.541925, "AbsTol", 1e-4);
            testCase.verifyTrue(ia.Pass);       % R <= 1

            % Tension-Ultimate resolves to a real margin: the row carries
            % BodyLengthInGrip = 0.50 in and NutHeight = 0.328 in (see
            % data.makeTemplate's sampleNutJointRow). HAND-DERIVED,
            % longhand. ThermalRate is not an analyst-facing column, so
            % this row's thermal preload comes from engine.stiffness +
            % TM-106943 Eq. 10 — the same geometry Tension-Ultimate's phi
            % needs, so nothing here is NotEvaluated:
            %
            % 1) engine.stiffness on this row's geometry (grip = Flange1 +
            %    Flange2 = 0.75 in, no washers, so Lbolt = 0.75 in;
            %    L1 = BodyLengthInGrip = 0.50 in, L2 = 0.25 in; frustum
            %    angle blank -> 30 deg; NAS1351 3/8-24: D = 0.375 in,
            %    As = pi/4*0.375^2 = 0.110447 in^2, At = 0.08783 in^2,
            %    HeadBearingDiameter dwf = 0.5625 in; A286 Eb = 29.1e6 psi;
            %    Al 7075-T7351 Ec = 10.3e6 psi):
            %      kb = Eb / [(L1+0.4D)/As + (L2+0.4D)/At]
            %         = 29.1e6 / [0.65/0.110447 + 0.40/0.08783]
            %         = 29.1e6 / [5.88519 + 4.55425] = 29.1e6/10.43944
            %         = 2,787,504 lbf/in
            %      Dc = dwf (no washers, tw = 0) = 0.5625 in (below the
            %         "no washer OD" case, so nothing caps it further)
            %      kc = pi*tan(30deg)*Ec*D / (2*ln{[(tanA*L+Dc-D)(Dc+D)] /
            %                                       [(tanA*L+Dc+D)(Dc-D)]})
            %         with tanA = tan(30deg) = 0.577350, L = 0.75 in:
            %         arg = [(0.433013+0.1875)(0.9375)] /
            %               [(0.433013+0.9375)(0.1875)]
            %             = 0.581731/0.256974 = 2.263798, ln(arg) = 0.817044
            %         kc = pi*0.577350*10.3e6*0.375 / (2*0.817044)
            %            = 1.813799*10.3e6*0.375 / 1.634088
            %            = 7,005,800 / 1.634088 = 4,287,285 lbf/in
            %            (uses pi*tan(alpha), not a rounded 30deg-only
            %            constant -- see engine.stiffness and
            %            tests/tStiffness.m)
            %      phi = kb/(kb+kc) = 2,787,504/7,074,789 = 0.394005
            %
            % 2) Thermal preload (TM-106943 Eq. 10, since ThermalRate is
            %    unset/0): kSeries = kb*kc/(kb+kc) = 1,689,213 lbf/in;
            %    Al 7075-T7351 CTE alphaJ = 2.32e-5, A286 CTE alphaB =
            %    1.65e-5 (both 1/degC); grip L = 0.75 in; hot excursion
            %    dThot = HotTempC - NominalTempC = 33.8889 - 20 = 13.8889 degC:
            %      Pth = kSeries*L*dThot*(alphaJ-alphaB)
            %          = 1,689,213*0.75*13.8889*6.7e-6 = 117.89 lbf
            %    (the cold excursion is exactly symmetric, -13.8889 degC, so
            %    it contributes the same 117.89 lbf preload LOSS on the min
            %    side; neither excursion is floored to zero since each helps
            %    one side and hurts the other).
            %
            % 3) Preload chain (Eq. 3/24 torque control): Ppi_nom =
            %    470/(0.15*0.375) = 8,355.56 lbf; c_max = 1.042553,
            %    Gamma = 0.25 -> Ppi_max = 1.042553*1.25*8,355.56 =
            %    10,888.89 lbf. PpMax = Ppi_max + Pth = 10,888.89 + 117.89
            %    = 11,006.78 lbf.
            %
            % 4) Fig. 8 gate still NOT assured: PpMax(11,006.78) exceeds
            %    0.75*Ptu_allow = 0.75*14,050 = 10,537.5 -> rupture branch.
            %
            % 5) NASA-STD-5020B Eq. 10 (rupture): with n = LoadingPlaneFactor
            %    = 0.5,
            %      P'tu = (Ptu_allow - PpMax)/(n*phi)
            %           = (14,050 - 11,006.78)/(0.5*0.394005)
            %           = 3,043.22/0.197003 = 15,447.62 lbf
            %      Ptu  = FSU*FFU*Axial = 1.4*1.15*5590 = 8,999.9 lbf
            %      MS   = P'tu/Ptu - 1 = 15,447.62/8,999.9 - 1 = 0.716421
            %
            % (Adding NutHeight also makes the nut-thread-shear mode
            % assessable, but its computed ultimate, Fsu*As =
            % 93,400*0.75*pi*0.3479*0.328 ~= 25,100 lbf, is well above the
            % bolt's 14,050 lbf rating, so it does NOT change Ptu_allow or
            % this margin -- the bolt mode still governs the system
            % minimum.)
            testCase.verifyEqual(T.TensionUlt(1), 0.716421, "AbsTol", 1e-3);

            % WorstMargin is a real number, not NaN, once
            % Tension-Yield/Shear-Ultimate/etc. can evaluate (Interaction
            % is excluded from this pick regardless -- see above).
            testCase.verifyFalse(isnan(T.WorstMargin(1)));

            % The joint-mode-slip nf check runs BEFORE the margin solver, so
            % its Note (this pattern has only ONE element against
            % BoltCount = 4) still lands; Slip itself stays NotEvaluated.
            testCase.verifyTrue(isnan(T.Slip(1)));
            testCase.verifyGreaterThan(strlength(T.Note(1)), 0);
            testCase.verifySubstring(T.Note(1), "BoltCount");
        end

        function bulkJointSlipFromPatternAggregation(testCase)
            % Four elements sharing a joint (pattern key defaults to
            % JointName) and load case, forces splitting the
            % book's joint totals evenly. The pre-pass counts 4 elements =
            % Joint.BoltCount (nf check passes), vector-sums the forces to
            % PtL_joint = 16,090 / PsL_joint = 5,690 lb (Solutions-22), and
            % Eq. 84 reproduces the book's joint-slip margin on every row:
            % MS = 4*0.1*6,469.75 / (1.0*(5,690 + 0.1*16,090)) - 1 = -0.65
            % (Solutions-23) — the deliberate failing margin, governing.
            %
            % Uses dabjInlineJointWithFactors (validation.dabjSection9 built
            % in-code), NOT the shipped template: the shipped
            % elements_template.csv supplies only ONE element (1001) for
            % the demo joint, which never satisfies the nf check against
            % BoltCount = 4 on its own (see the class header), so exercising
            % Eq. 84's pattern aggregation needs the 4-element
            % dabjPatternElements set regardless of which joint it is paired
            % with. This test pairs it with the library-independent §9
            % fixture (not the shipped demo joint) so the exact -0.65
            % answer-key reproduction is pinned in code, decoupled from
            % whatever the shipped catalog bolt/material entries happen to
            % contain.
            [jl, fac] = tBulk.dabjInlineJointWithFactors();
            c = validation.dabjSection9();

            T = engine.analyzeBulk(jl, tBulk.dabjPatternElements(jl(1).Name), fac);
            testCase.assertEqual(height(T), 4);
            tol = c.Tol.MarginAbsTol;
            for k = 1:4
                testCase.verifyEqual(T.Error(k), "");
                testCase.verifyEqual(T.Note(k), "");   % nf check satisfied
                testCase.verifyEqual(T.Slip(k), c.Expected.MS_Slip, ...
                    "AbsTol", tol);                    % -0.65, Eq. 84
                testCase.verifyEqual(T.WorstMargin(k), c.Expected.MS_Slip, ...
                    "AbsTol", tol);
                testCase.verifyEqual(T.GoverningCheck(k), "Slip");
            end
            % Per-bolt resolution unchanged by the aggregation
            testCase.verifyEqual(T.Axial(1), 4022.5, "AbsTol", 1e-9);
            testCase.verifyEqual(T.Shear(1), 1422.5, "AbsTol", 1e-9);
        end

        function bulkPatternIdSplitsAndNfCheck(testCase)
            % PatternId defines the PHYSICAL joint instance: the same four
            % elements split into two 2-bolt patterns ("A"/"B") no longer
            % match Joint.BoltCount = 4, so the nf check refuses joint slip
            % on every row (Slip NaN + Note) regardless of the row otherwise
            % analyzing cleanly (see bulkRunsTemplateJointWithoutCrashing) --
            % the Note is set BEFORE the margin solver runs, so it lands
            % either way. Tension-Ultimate resolves on every row too (same
            % stiffness geometry as bulkRunsTemplateJointWithoutCrashing —
            % phi and PpMax don't depend on the per-bolt axial load, only
            % the final Ptu denominator does; see the derivation below).
            [jl, s] = tBulk.dabjLibraryWithSettings();

            els = tBulk.dabjPatternElements(jl(1).Name);
            [els(1:2).PatternId] = deal("A");
            [els(3:4).PatternId] = deal("B");

            T = engine.analyzeBulk(jl, els, s.Factors);
            testCase.assertEqual(height(T), 4);

            % Every row shares the same per-bolt loads (Axial 4022.5, Shear
            % 1422.5 -- see dabjPatternElements), so TensionYield and the
            % Interaction ratio R are identical across all four and
            % hand-derivable from the same raw constants as
            % bulkRunsTemplateJointWithoutCrashing (NAS1351 3/8-24 + A286:
            % the FF-S-86F Table VII rated pair 14,050/10,500, Eq. 20/21 criterion
            % R = Rt^1.5 + Rs^2.5 for interaction -- direct evaluation, no
            % root-find). T.InteractionR now carries this R directly
            % (renamed from "Interaction", sourced from .R not .MS -- see
            % engine.analyzeBulk's header); verified BOTH against the
            % table AND directly against engine.marginInteraction.
            % Tension-Yield ALSO takes the not-assured Eq. 16/17 branch here
            % (same shared Fig. 8 gate as bulkRunsTemplateJointWithoutCrashing
            % -- gate/phi/PpMax are pure geometry+preload, independent of
            % which element references the joint, so they carry over
            % unchanged; only Pty's per-bolt load, 4022.5 vs 5590, differs):
            %   Pty_allow = 10,500 (FF-S-86F Table VII rating, unchanged)
            %   P'ty = (10,500 - 11,006.78)/(0.5*0.394005) = -2,572.45 (Eq. 17, unchanged)
            %   Pty  = FSY*FFY*4022.5 = 1.25*1*4022.5 = 5,028.125 lbf
            %   MS   = -2,572.45/5,028.125 - 1 = -1.5116              (Eq. 16)
            expectedPtuAllow = 14050;
            expectedPtyAllow = 10500;
            phi = 0.394005;   n = 0.5;   PpMax = 11006.78;
            fac = s.Factors;
            Pty = fac.FSY * fac.FFY * 4022.5;
            Pprime = (expectedPtyAllow - PpMax) / (n * phi);   % Eq. 17
            expectedTensionYield = Pprime / Pty - 1;           % Eq. 16

            Ptu      = fac.FSU * fac.FFU * 4022.5;
            Psu      = fac.FSU * fac.FFU * 1422.5;
            PsuAllow = 93400 * (pi/4 * 0.375^2);          % A286 Fsu * BodyArea
            Rt       = Ptu / expectedPtuAllow;
            Rs       = Psu / PsuAllow;
            % Rt = 0.460941, Rs = 0.222013 ->
            % R = 0.460941^1.5 + 0.222013^2.5 = 0.312945 + 0.023225 = 0.336170
            expectedR = Rt^1.5 + Rs^2.5;
            d  = struct("Ptu", Ptu, "Pty", NaN, "Psu", Psu, "Psep", NaN);
            ia = engine.marginInteraction(jl(1).Joint, d);

            % Tension-Ultimate: same gate/phi/PpMax chain as
            % bulkRunsTemplateJointWithoutCrashing's hand-derivation (this
            % row's BodyLengthInGrip/NutHeight are unaffected by which
            % elements reference it, and ThermalRate no longer exists as an
            % analyst override -- both rows go through the same
            % engine.stiffness + TM-106943 Eq. 10 thermal path) --
            %   Ptu_allow = 14,050 (unchanged); PpMax = 11,006.78 lbf
            %   (unchanged -- the thermal/torque preload chain doesn't
            %   depend on the per-bolt load); phi = 0.394005 (unchanged,
            %   pure geometry) -> P'tu = 15,447.62 lbf (unchanged, Eq. 10's
            %   numerator/denominator don't involve the per-bolt load).
            % Only Ptu itself changes with the smaller per-bolt axial load
            % here (4022.5 vs 5590 lbf):
            %   Ptu = FSU*FFU*4022.5 = 1.4*1.15*4022.5 = 6,476.225 lbf
            %   MS  = 15,447.62/6,476.225 - 1 = 1.385282
            expectedTensionUlt = 1.385282;

            for k = 1:4
                testCase.verifyEqual(T.Error(k), "");
                testCase.verifyEqual(T.TensionYield(k), expectedTensionYield, "AbsTol", 1e-3);
                testCase.verifyEqual(T.TensionYield(k), -1.5116, "AbsTol", 1e-3);
                testCase.verifyLessThan(T.TensionYield(k), 0);   % over-torqued, same as bulkRunsTemplateJointWithoutCrashing
                testCase.verifyEqual(T.InteractionR(k), expectedR, "AbsTol", 1e-6);
                testCase.verifyEqual(T.InteractionR(k), 0.336170, "AbsTol", 1e-4);
                testCase.verifyTrue(isnan(T.Slip(k)));
                testCase.verifyGreaterThan(strlength(T.Note(k)), 0);
                testCase.verifySubstring(T.Note(k), "BoltCount");
                testCase.verifyEqual(T.TensionUlt(k), expectedTensionUlt, "AbsTol", 1e-3);
            end
            testCase.verifyEqual(ia.R, expectedR, "AbsTol", 1e-6);
            testCase.verifyEqual(ia.R, 0.336170, "AbsTol", 1e-4);
            testCase.verifyTrue(ia.Pass);       % R <= 1
        end

        function bulkHandlesMissingJoint(testCase)
            % An element referencing a nonexistent joint gets an Error row
            % (margins NaN) — the batch must NOT throw.
            [jl, s] = tBulk.dabjLibraryWithSettings();

            el = tBulk.dabjElement(jl(1).Name);
            el.ElementId = "9002";
            el.JointName = "No such joint";

            T = engine.analyzeBulk(jl, el, s.Factors);
            testCase.assertEqual(height(T), 1);
            testCase.verifyEqual(T.ElementId(1), "9002");
            testCase.verifyGreaterThan(strlength(T.Error(1)), 0);
            testCase.verifySubstring(T.Error(1), "No such joint");
            testCase.verifyTrue(isnan(T.TensionUlt(1)));
            testCase.verifyTrue(isnan(T.Separation(1)));
            testCase.verifyTrue(isnan(T.WorstMargin(1)));
        end

        function bulkHandlesDuplicateJointName(testCase)
            % data.loadJointLibrary enforces no uniqueness on Name, so a
            % library can legally carry two rows sharing a Name. Silently
            % taking the first match would analyze the element against
            % whichever duplicate happens to be found first, with nothing
            % in Error or Note to say so -- must instead be a reported
            % Error row (margins NaN), same "no throw, batch continues"
            % contract as bulkHandlesMissingJoint.
            [jl, s] = tBulk.dabjLibraryWithSettings();
            dup = jl(1);           % same Name, a second (distinct) Joint object
            dup.Joint.BoltCount = jl(1).Joint.BoltCount + 1;
            jlDup = [jl, dup];

            el = tBulk.dabjElement(jl(1).Name);
            el.ElementId = "9003";

            T = engine.analyzeBulk(jlDup, el, s.Factors);
            testCase.assertEqual(height(T), 1);
            testCase.verifyEqual(T.ElementId(1), "9003");
            testCase.verifyGreaterThan(strlength(T.Error(1)), 0);
            testCase.verifySubstring(T.Error(1), """" + jl(1).Name + """");
            testCase.verifySubstring(T.Error(1), "ambiguous");
            testCase.verifySubstring(T.Error(1), "2");   % names the count
            testCase.verifyTrue(isnan(T.TensionUlt(1)));
            testCase.verifyTrue(isnan(T.WorstMargin(1)));
        end

        function bulkResultsTableShape(testCase)
            % One row per element; the documented column set, in order.
            % Uses dabjInlineJointWithFactors (not the shipped template) for
            % the "good" row: the shipped demo joint also analyzes cleanly,
            % including a real Tension-Ultimate (see
            % bulkRunsTemplateJointWithoutCrashing), but this fixture
            % reaches every margin, including Slip, against the exact
            % published answer key, for the clean-vs-error contrast this
            % test wants to illustrate.
            [jl, fac] = tBulk.dabjInlineJointWithFactors();

            good = tBulk.dabjElement(jl(1).Name);
            bad  = tBulk.dabjElement(jl(1).Name);
            bad.ElementId = "9002";
            bad.JointName = "No such joint";

            T = engine.analyzeBulk(jl, [good, bad], fac);
            testCase.verifyClass(T, "table");
            testCase.assertEqual(height(T), 2);

            expectedVars = ["ElementId", "JointName", "LoadCase", ...
                "Axial", "Shear", ...
                "TensionUlt", "TensionYield", "ShearUlt", "ShearTearout", ...
                "Bearing", "BearingUnderHead", "BoltThreadShear", ...
                "NutStrength", "InsertInternal", "InsertExternal", ...
                "Separation", "Slip", "SepBeforeRupture", "InteractionR", ...
                "TappedParent", ...
                "WorstMargin", "GoverningCheck", "Error", "Note", "Warnings"];
            testCase.verifyEqual( ...
                string(T.Properties.VariableNames), expectedVars);

            % Row 1 analyzed clean, row 2 carries the error
            testCase.verifyEqual(T.Error(1), "");
            testCase.verifyGreaterThan(strlength(T.Error(2)), 0);

            % Trailing Warnings column: row 1 is the DABJ §9 fixture
            % (validation.dabjSection9, via dabjInlineJointWithFactors) --
            % the same fixture tests/tPreloadWatchdog.m's
            % dabjSection9TripsNearYieldByDesign pins directly against
            % engine.preloadWatchdog: PpMax ~11,069.14 vs its rated yield
            % 11,400 is 97.1% of yield (above the 85% band, below 100%) ->
            % one PreloadNearYield Warning (not Critical -- it has not
            % exceeded yield, only approached it). Row 2 never reaches
            % engine.analyze (missing-joint Error), so its Warnings column
            % stays "" like its other margin columns stay NaN.
            testCase.verifySubstring(T.Warnings(1), "Warning:");
            testCase.verifySubstring(T.Warnings(1), ...
                "is 97.1% of the bolt yield tensile allowable");
            testCase.verifyEqual(T.Warnings(2), "");
        end

        function bulkFailingInteractionVisibleButNeverGoverns(testCase)
            % Every other Interaction fixture in this codebase happens to
            % pass (R <= 1) — this test is the one genuinely failing case
            % (R > 1), pushed through the full engine.analyzeBulk pipeline,
            % to confirm the failure is visible on the InteractionR column
            % and on the check's own Status, while still never governing
            % WorstMargin/GoverningCheck (engine.analyze's INTERACTION IS
            % NOT A MARGIN rule).
            %
            % Uses the validation.dabjSection9 joint unchanged (BodyInShear,
            % BoltRatedUltimateLoad = 15,200, Fsu = 95,000, BodyDiameter
            % falls back to NominalDiameter 0.375 -- all already-validated
            % book constants, see tDabjCase.m) but a new LoadCase with much
            % larger limit loads (PtL = 15,000, PsL = 5,000 -- well beyond
            % the book's 5,590/1,560) so the interaction envelope is
            % genuinely exceeded, not just the book's DABJ answer key
            % (which this test does not touch or re-derive).
            %
            % HAND-DERIVED (NASA-STD-5020B Eq. 20/21, BodyInShear, exp
            % 1.5/2.5; factors FSU=1.4, FFU=1.15 per validation.dabjSection9):
            %   Ptu = 1.4*1.15*15,000 = 24,150     Psu = 1.4*1.15*5,000 = 8,050
            %   Psu_allow = 95,000*pi/4*0.375^2    = 10,492.43 (book constant,
            %       same as Solutions-19's shear allowable)
            %   Rt = 24,150/15,200 = 1.588816      Rs = 8,050/10,492.43 = 0.767220
            %   R  = Rt^1.5 + Rs^2.5 = 1.588816^1.5 + 0.767220^2.5
            %      = 2.001664 + 0.516595 = 2.518259  (FAIL -- R > 1, direct
            %      evaluation, no root-find)
            %   MS_TensionUlt = 15,200/24,150 - 1 = -0.370600 (a real,
            %      independently-failing margin -- confirms WorstMargin has
            %      a genuine non-Interaction candidate to be governed by)
            [jl, fac] = tBulk.dabjInlineJointWithFactors();
            lc = model.LoadCase(Name = "Overload case", ...
                BoltTensileLimitLoad = 15000, BoltShearLimitLoad = 5000);

            % This ad-hoc LoadCase carries only the per-bolt loads (this
            % test's whole point is Interaction, not Slip) -- it does NOT
            % set JointTensileLimitLoad/JointShearLimitLoad. The §9 fixture
            % joint is SlipMode.Joint, and engine.marginSlip's Eq. 84 branch
            % REQUIRES those joint-level loads (errors otherwise, by design
            % -- see marginSlip's engine:marginSlip:jointLoadsRequired). The
            % full engine.analyzeBulk pipeline below sidesteps this itself
            % (its nf check finds only 1 element against BoltCount = 4 and
            % downgrades its own local joint copy to SlipMode.Ignored before
            % calling engine.analyze -- Joint is a value class, so this
            % never touches jl(1).Joint). Calling engine.analyze directly
            % here bypasses that pre-pass, so mirror the same downgrade on a
            % local copy: Slip is irrelevant to what this test checks
            % (Interaction visibility), and this keeps part 2 directly
            % comparable to part 3's bulk row.
            jointNoSlip = jl(1).Joint;
            jointNoSlip.SlipMode = model.SlipMode.Ignored;

            % 1) Own row, straight from engine.marginInteraction (no bulk
            %    table in between) -- the independent hand-derivation above.
            d  = engine.designLoads(lc, fac);
            ia = engine.marginInteraction(jl(1).Joint, d);
            testCase.verifyEqual(ia.R, 2.518259, "AbsTol", 1e-4);
            testCase.verifyFalse(ia.Pass);        % R > 1 -- Fail

            % 2) engine.analyze's Margins row: Status = Fail from R <= 1
            %    (NOT from any MS sign test -- MS is NaN on this row by
            %    design), and it must NOT become GoverningCheck even though
            %    it fails (excluded from the WorstMargin min entirely).
            r = engine.analyze(jointNoSlip, lc, fac);
            iaRow = r.Margins([r.Margins.Name] == "Interaction");
            testCase.verifyTrue(isnan(iaRow.MS));
            testCase.verifyEqual(iaRow.R, ia.R, "AbsTol", 1e-9);
            testCase.verifyEqual(iaRow.Status, "Fail");
            testCase.verifyNotEqual(r.GoverningCheck, "Interaction");
            testCase.verifyFalse(isnan(r.WorstMargin));    % a real margin governs instead
            tuRow = r.Margins([r.Margins.Name] == "Tension-Ultimate");
            testCase.verifyEqual(tuRow.MS, -0.370600, "AbsTol", 1e-4);
            testCase.verifyEqual(tuRow.Status, "Fail");    % real, independent failure

            % 3) The bulk table: InteractionR carries the real, failing R
            %    (not NaN), and the row's WorstMargin/GoverningCheck agree
            %    with (2) -- Interaction never governs, but the row is not
            %    reported as clean either (a caller must read every 5020B
            %    column's own sign, not just WorstMargin, to know a bulk
            %    row is fully clean -- same rule as engine.analyze).
            el = struct( ...
                "ElementId",    "9101", ...
                "JointName",    jl(1).Name, ...
                "LoadCaseName", "Overload case", ...
                "Forces",       struct("FX", 5000, "FY", 0, "FZ", 15000, ...
                                       "MX", 0, "MY", 0, "MZ", 0), ...
                "ScaleFactor",  1, ...
                "Reversible",   false);
            T = engine.analyzeBulk(jl, el, fac);
            testCase.assertEqual(height(T), 1);
            testCase.verifyEqual(T.Error(1), "");
            testCase.verifyEqual(T.InteractionR(1), 2.518259, "AbsTol", 1e-4);
            testCase.verifyGreaterThan(T.InteractionR(1), 1);      % Fail region
            testCase.verifyEqual(T.TensionUlt(1), -0.370600, "AbsTol", 1e-4);
            testCase.verifyEqual(T.GoverningCheck(1), r.GoverningCheck);
            testCase.verifyEqual(T.WorstMargin(1), r.WorstMargin, "AbsTol", 1e-9);
        end
    end
end
