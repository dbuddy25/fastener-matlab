classdef tBoltLength < matlab.unittest.TestCase
    %TBOLTLENGTH  Bolt.Length as a first-class input (GUI step 4.8):
    %   - model.Bolt.Length defaults to NaN, and with the default every
    %     existing engine.stiffness result is UNCHANGED (the regression
    %     guard for the validated DABJ Example 8-b numbers).
    %   - When supplied, Bolt.Length replaces the NASA-STD-5020B §4.7.4
    %     bolt-length estimate in the L1 derivation (precedence level 2);
    %     an explicit Joint.BodyLengthInGrip still overrides everything
    %     (level 1).
    %   - engine.boltLengthCheck: the pure adequacy query behind the GUI's
    %     live bolt-length label — nut and insert/tapped configurations,
    %     and NaN-input tolerance (it must never throw on a half-filled
    %     joint).
    %
    %   Every expected number below is HAND-DERIVED on the DABJ Example
    %   8-b geometry (p. 8-18 inputs, via validation.dabjExample8b):
    %   two 0.40-in fittings + 0.078/0.062-in washers -> clamped length
    %   Lb = 0.80 + 0.140 = 0.940 in; 3/8-24 bolt (D = 0.375, pitch =
    %   1/24 in). The book publishes no bolt-length numbers — only the
    %   Kb/Kc/Phi answer key reused by the regression guard.
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
        function lengthDefaultsToNaN(testCase)
            % A bare bolt and a library bolt (library.json carries no
            % "length" fields) both default Length to NaN — the sentinel
            % that keeps every pre-existing code path untouched.
            testCase.verifyTrue(isnan(model.Bolt().Length));
            lib = data.Library.load();
            keys = lib.boltKeys();
            testCase.assumeNotEmpty(keys);
            testCase.verifyTrue(isnan(lib.bolt(keys(1)).Length));
        end

        function stiffnessUnchangedWithDefaultLength(testCase)
            % REGRESSION GUARD: the 8-b fixture supplies no Bolt.Length
            % (NaN default), so engine.stiffness must reproduce the same
            % validated answer key as tStiffness — DABJ Example 8-b
            % printed values Kb = 2.39e6, Kc = 4.73e6 lbf/in, Phi = 0.336
            % (pp. 8-19..8-21), with the book-supplied L1 = 0.70 in intact.
            c = validation.dabjExample8b();
            testCase.verifyTrue(isnan(c.Joint.Bolt.Length));
            s = engine.stiffness(c.Joint);
            testCase.verifyEqual(s.Kb,  c.Expected.Kb,  "RelTol", c.Tol.RelTol);
            testCase.verifyEqual(s.Kc,  c.Expected.Kc,  "RelTol", c.Tol.RelTol);
            testCase.verifyEqual(s.Phi, c.Expected.Phi, "AbsTol", c.Tol.PhiAbsTol);
            testCase.verifyEqual(s.L1, 0.70, "AbsTol", 1e-12);
        end

        function suppliedLengthDrivesL1(testCase)
            % Precedence level 2: with BodyLengthInGrip = NaN, a supplied
            % Bolt.Length is used directly — no §4.7.4 estimate, so it
            % works WITHOUT a nut height (EngagementLength stays NaN here;
            % the old fallback alone would error bodyLengthRequired).
            % HAND-DERIVED on the 8-b geometry: Lb = 0.94 in (fittings
            % 0.80 + washers 0.14); Bolt.Length = 1.30, ThreadLength = 0.5
            %   Ls = 1.30 - 0.5 = 0.80 in
            %   L1 = min(max(0.80, 0), 0.94) = 0.80 in;  L2 = 0.14 in
            c = validation.dabjExample8b();
            j = c.Joint;
            j.BodyLengthInGrip = NaN;
            j.Bolt.ThreadLength = 0.5;
            j.Bolt.Length = 1.30;
            testCase.verifyTrue(isnan(j.ThreadedMember.EngagementLength));
            s = engine.stiffness(j);
            testCase.verifyEqual(s.L1, 0.80, "AbsTol", 1e-12);
            testCase.verifyEqual(s.L2, 0.94 - 0.80, "AbsTol", 1e-12);
        end

        function bodyLengthStillOverridesSuppliedLength(testCase)
            % Precedence level 1: an explicit Joint.BodyLengthInGrip beats
            % a supplied Bolt.Length. 8-b keeps its book value L1 = 0.70
            % (p. 8-19) even though Length = 1.30 / ThreadLength = 0.5
            % would give 0.80 (previous test) if the override were broken.
            c = validation.dabjExample8b();
            j = c.Joint;                       % BodyLengthInGrip = 0.70
            j.Bolt.ThreadLength = 0.5;
            j.Bolt.Length = 1.30;
            s = engine.stiffness(j);
            testCase.verifyEqual(s.L1, 0.70, "AbsTol", 1e-12);
            testCase.verifyEqual(s.L2, 0.94 - 0.70, "AbsTol", 1e-12);
        end

        function nutConfigAdequateAndShort(testCase)
            % Nut config: NASA-STD-5020B §4.7.4 —
            %   Lmin = grip + nut height + 2·pitch
            % HAND-DERIVED on the 8-b geometry with nut height 0.3 in:
            %   grip = 0.40 + 0.40 + 0.078 + 0.062 = 0.94 in
            %   2·pitch = 2/24 in (3/8-24)
            %   Lmin = 0.94 + 0.3 + 2/24 = 1.32333... in
            % Supplied 1.35 in -> adequate (shortfall 0);
            % supplied 1.25 in -> short by 1.32333... - 1.25 = 0.07333... in.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.ThreadedMember.EngagementLength = 0.3;   % nut height, in
            required = 0.94 + 0.3 + 2/24;

            j.Bolt.Length = 1.35;
            r = engine.boltLengthCheck(j);
            testCase.verifyEqual(r.GripLength, 0.94, "AbsTol", 1e-12);
            testCase.verifyEqual(r.Engagement, 0.3, "AbsTol", 1e-12);
            testCase.verifyEqual(r.ThreadAllowance, 2/24, "AbsTol", 1e-12);
            testCase.verifyEqual(r.RequiredLength, required, "AbsTol", 1e-12);
            testCase.verifyTrue(r.Evaluated);
            testCase.verifyTrue(r.IsAdequate);
            testCase.verifyEqual(r.Shortfall, 0, "AbsTol", 1e-12);
            testCase.verifySubstring(r.Method, "4.7.4");

            j.Bolt.Length = 1.25;
            r = engine.boltLengthCheck(j);
            testCase.verifyTrue(r.Evaluated);
            testCase.verifyFalse(r.IsAdequate);
            testCase.verifyEqual(r.Shortfall, required - 1.25, "AbsTol", 1e-12);
        end

        function threadedInConfig(testCase)
            % Insert: NASA-STD-5020B §4.7.4 names "nut, nut plate, or
            % insert" together for the SAME 2·pitch protrusion term, so
            % Insert gets Lmin = grip + Le + 2·pitch, exactly like Nut —
            % see boltLengthCheck's header. Le itself is still the
            % DERIVED CONVENTION (supplied EngagementLength, else 1.5·D;
            % 5020B gives no formula for Le).
            % HAND-DERIVED on the 8-b geometry (grip 0.94 in; 3/8-24 UNF,
            % so pitch p = 1/24 in, 2p = 2/24 = 0.083333... in):
            %   Le supplied 0.5 in  -> Lmin = 0.94 + 0.5 + 2/24
            %                       = 1.44 + 0.083333... = 1.523333... in
            %   Le unspecified      -> Le = 1.5·D = 1.5·0.375 = 0.5625 in
            %                          (reference-tool default)
            %                       -> Lmin = 0.94 + 0.5625 + 2/24
            %                       = 1.5025 + 0.083333... = 1.585833... in
            c = validation.dabjExample8b();
            j = c.Joint;
            j.ThreadedMember.Type = model.ThreadedMemberType.Insert;
            j.ThreadedMember.EngagementLength = 0.5;
            j.Bolt.Length = 1.5;
            r = engine.boltLengthCheck(j);
            required = 0.94 + 0.5 + 2/24;
            testCase.verifyEqual(r.ThreadAllowance, 2/24, "AbsTol", 1e-12);
            testCase.verifyEqual(r.RequiredLength, required, "AbsTol", 1e-12);
            testCase.verifyEqual(r.EngagementBasis, "specified engagement");
            testCase.verifyTrue(r.Evaluated);
            % Supplied 1.5 in is now SHORT of 1.523333... in by 2/24 in
            % (the newly-applied 2·pitch term) -- this bolt was adequate
            % under the old (wrong) Insert formula, but is not under the
            % corrected one.
            testCase.verifyFalse(r.IsAdequate);
            testCase.verifyEqual(r.Shortfall, required - 1.5, "AbsTol", 1e-12);
            testCase.verifySubstring(r.Method, "4.7.4");

            % A length that actually clears the corrected minimum.
            j.Bolt.Length = 1.6;
            r = engine.boltLengthCheck(j);
            testCase.verifyTrue(r.IsAdequate);
            testCase.verifyEqual(r.Shortfall, 0, "AbsTol", 1e-12);

            j.ThreadedMember.Type = model.ThreadedMemberType.TappedHole;
            j.ThreadedMember.EngagementLength = NaN;
            r = engine.boltLengthCheck(j);
            testCase.verifyEqual(r.Engagement, 1.5 * 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(r.EngagementBasis, "1.5D default");
            % TappedHole is NOT named in §4.7.4's 2·pitch sentence -- no
            % allowance term, Lmin = grip + Le only (see header).
            testCase.verifyEqual(r.ThreadAllowance, 0, "AbsTol", 1e-12);
            testCase.verifyEqual(r.RequiredLength, 0.94 + 1.5 * 0.375, ...
                "AbsTol", 1e-12);
            testCase.verifySubstring(r.Method, "does not");
        end

        function engagementRatioPrecedenceViaBoltLengthCheck(testCase)
            % resolveEngagementLength precedence, exercised through
            % engine.boltLengthCheck (the simplest direct caller -- no
            % loadCase/factors/preload setup needed, and its
            % Engagement/EngagementBasis fields are exactly the resolver's
            % Le/Basis surfaced to a caller). Nut config deliberately
            % chosen for this: unlike Insert/TappedHole, Nut has NO 1.5D
            % derived-convention fallback of its own (see boltLengthCheck's
            % header), so the "neither set" case below cleanly shows the
            % RESOLVER's own NaN, not a different fallback masking it.
            %
            % HAND-DERIVED on the 8-b geometry (grip 0.94 in; 3/8-24 UNF,
            % D = 0.375, 2·pitch = 2/24 in):
            %   ratio-only:  EngagementRatio=1.5 -> Le = 1.5*0.375 = 0.5625 in
            %   length-only: EngagementLength=0.3 -> Le = 0.3 in (unchanged)
            %   both set:    ratio WINS -> Le = 0.5625 in (0.3 in ignored,
            %                but its value must still be named in Detail)
            %   neither set: Le = NaN -> RequiredLength NaN, basis "unknown"
            c = validation.dabjExample8b();
            j = c.Joint;
            j.Bolt.Length = 2.0;   % comfortably long enough to stay adequate throughout

            % ---- ratio-only ----------------------------------------------
            j.ThreadedMember.EngagementRatio  = 1.5;
            j.ThreadedMember.EngagementLength = NaN;
            r = engine.boltLengthCheck(j);
            testCase.verifyEqual(r.Engagement, 1.5 * 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(r.EngagementBasis, "engagement ratio");
            testCase.verifyEqual(r.RequiredLength, 0.94 + 0.5625 + 2/24, "AbsTol", 1e-12);
            testCase.verifySubstring(r.Method, "EngagementRatio");

            % ---- length-only (the pre-existing path, unchanged) -----------
            j.ThreadedMember.EngagementRatio  = NaN;
            j.ThreadedMember.EngagementLength = 0.3;
            r = engine.boltLengthCheck(j);
            testCase.verifyEqual(r.Engagement, 0.3, "AbsTol", 1e-12);
            testCase.verifyEqual(r.EngagementBasis, "nut height");
            testCase.verifyEqual(r.RequiredLength, 0.94 + 0.3 + 2/24, "AbsTol", 1e-12);

            % ---- both set -- the ratio WINS, and it must be visible ------
            j.ThreadedMember.EngagementRatio  = 1.5;
            j.ThreadedMember.EngagementLength = 0.3;
            r = engine.boltLengthCheck(j);
            testCase.verifyEqual(r.Engagement, 1.5 * 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(r.EngagementBasis, "engagement ratio");
            testCase.verifyEqual(r.RequiredLength, 0.94 + 0.5625 + 2/24, "AbsTol", 1e-12);
            % A reviewer must never be left guessing which number was used
            % -- Detail must name BOTH the value used and that it overrode
            % EngagementLength.
            testCase.verifySubstring(r.Detail, "EngagementRatio");
            testCase.verifySubstring(r.Detail, "overrides");
            testCase.verifySubstring(r.Detail, "0.3");

            % ---- neither set -- resolver returns NaN, Nut has no fallback
            j.ThreadedMember.EngagementRatio  = NaN;
            j.ThreadedMember.EngagementLength = NaN;
            r = engine.boltLengthCheck(j);
            testCase.verifyTrue(isnan(r.Engagement));
            testCase.verifyEqual(r.EngagementBasis, "unknown");
            testCase.verifyTrue(isnan(r.RequiredLength));
        end

        function nanInputsNeverThrow(testCase)
            % The GUI calls this on a half-filled form — a fully default
            % joint (empty stack, all-NaN bolt) must return NaNs and a
            % Detail, never error. IsAdequate stays TRUE when unknown
            % ("not proven inadequate" — documented in boltLengthCheck):
            % callers key alarm styling off Evaluated/Shortfall, so an
            % empty form must not open the app in a red state.
            r = engine.boltLengthCheck(model.Joint());
            testCase.verifyTrue(isnan(r.GripLength));
            testCase.verifyTrue(isnan(r.RequiredLength));
            testCase.verifyTrue(isnan(r.SuppliedLength));
            testCase.verifyTrue(isnan(r.Shortfall));
            testCase.verifyFalse(r.Evaluated);
            testCase.verifyTrue(r.IsAdequate);
            testCase.verifySubstring(r.Detail, "not evaluated");

            % Partially filled: grip known, required known, supplied NaN.
            c = validation.dabjExample8b();
            j = c.Joint;
            j.ThreadedMember.EngagementLength = 0.3;
            r = engine.boltLengthCheck(j);   % Bolt.Length stays NaN
            testCase.verifyEqual(r.RequiredLength, 0.94 + 0.3 + 2/24, ...
                "AbsTol", 1e-12);
            testCase.verifyTrue(isnan(r.SuppliedLength));
            testCase.verifyFalse(r.Evaluated);
            testCase.verifyTrue(r.IsAdequate);
        end
    end
end
