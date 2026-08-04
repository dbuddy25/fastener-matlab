% +ENGINE  Analysis math — the core (GUI-independent, headless-capable).
%
%   preload          - Min/max bolt preload incl. thermal (NASA-STD-5020B Eq. 3/4/5
%                      + Eq. 24 + Eq. 1/2; thermal change per TM-106943 Eq. 10 —
%                      stiffness-based since Phase 3.1b, with the ThermalRate
%                      override retained).
%                      ✅ Phase 2.4 — validated against DABJ §9 (tests/tDabjCase.m).
%   designLoads      - Design ultimate/yield/separation loads from limit loads
%                      x safety/fitting factors.
%                      ✅ Phase 2.5 — validated against DABJ §9.
%   marginTensionUlt - Ultimate-tension margin with the NASA-STD-5020B Fig. 8
%                      separation-before-rupture gate (Eq. 6 assured; Eq. 10
%                      rupture via the stiffness factor phi since Phase 3.1b).
%                      Ptu-allow is the FASTENING-SYSTEM allowable
%                      (systemTensileAllowable, 5020B §4.4.1) in the gate
%                      and both equations.
%                      ✅ Phase 2.5 — validated against DABJ §9 (+0.69).
%   systemTensileAllowable - The fastening system's allowable ultimate
%                      tensile load (NASA-STD-5020B §4.4.1): minimum over
%                      bolt tension (spec rating, else a derived
%                      Ptu_allow = At*Ftu — §4.4.2 derived convention, see
%                      boltTensileAllowable) and the internal-thread
%                      member's mode (nut thread shear / rating, insert
%                      pull-out, tapped-hole parent thread), with the
%                      governing mode named and unassessable modes reported
%                      (an incomplete minimum is flagged OPTIMISTIC, never
%                      silent).
%                      ✍️ Hand-derived pins + DABJ §9 regression
%                      (tests/tSystemAllowable.m, tests/tBoltAllowable.m).
%   marginSeparation - Joint-separation margin, min preload vs separation
%                      load (NASA-STD-5020B Eq. 19).
%                      ✅ Phase 2.6 — validated against DABJ §9 (+0.16).
%   marginTensionYield - Bolt yield margin, gated on the SAME Fig. 8
%                      separation-before-rupture decision as marginTensionUlt:
%                      Eq. 15 (assured) or Eq. 16/17 (not assured, needs
%                      phi from engine.stiffness); Pty-allow falls back to
%                      Eq. 18 (Fty/Ftu)*Ptu_allow when unrated
%                      (boltTensileAllowable).
%                      ✅ Phase 2.6 — validated against DABJ §9 (+0.63);
%                      ✍️ Eq. 16/17 branch hand-derived (tests/tStiffness.m).
%   marginShearUlt   - Bolt ultimate-shear margin, Fsu x area by
%                      shear-plane condition (NASA-STD-5020B Eq. 14).
%                      ✅ Phase 2.7 — validated against DABJ §9 (+3.18).
%   marginInteraction- Combined tension-shear interaction CHECK (NASA-STD-5020B
%                      Eq. 20-23: BodyInShear exp 1.5/2.5, ThreadsInShear exp
%                      2.0/1.2 — no bending term modeled, see the function
%                      header's NO-BENDING-TERM note). NOT A MARGIN — 5020B
%                      states this as a pass/fail CRITERION (R <= 1), so the
%                      function reports the ratio R and Pass, not an MS (a
%                      secondary "a" load-scale field is kept, informationally,
%                      but is not the result — see the function header).
%                      engine.analyze reports it as its own Margins row
%                      (MS = NaN, excluded from WorstMargin/GoverningCheck,
%                      Status set directly from R <= 1 — never hidden). Ptu-
%                      allow is the BOLT's own allowable (rated, else derived —
%                      boltTensileAllowable), not the fastening-system minimum.
%                      ✅ Phase 2.7 — BodyInShear validated against DABJ §9
%                      (R = 0.483642, Pass; book's own a = 1.59 solve-for-a
%                      kept as the secondary field). ✍️ ThreadsInShear —
%                      hand-derived (tests/tDabjCase.m; DABJ §9 has no
%                      threads-in-shear example).
%   marginSlip       - Slip margin, switched on Joint.SlipMode:
%                      single-fastener (default, per-bolt loads, NASA-STD-5020B
%                      Eq. 86), joint (nf·μ·PpMin vs joint totals, NASA-STD-5020B
%                      Eq. 84), or ignored (NotEvaluated).
%                      ✅ Phase 2.8 — validated against DABJ §9 (-0.65, joint mode).
%   analyze          - Single-joint solver: preload + design loads + every
%                      margin check in one call -> engine.Result, plus the
%                      bolt-length/preload Warnings collection (see
%                      Result.Warnings and engine.boltLengthCheck /
%                      engine.preloadWatchdog below).
%                      ✅ Phase 2.9 — one call reproduces all 6 DABJ §9 margins.
%   Result           - Standard result object: Preload, DesignLoads, the
%                      15-check Margins table (Pass|Fail|NotEvaluated),
%                      WorstMargin/GoverningCheck, Fig. 8 Narrative,
%                      Warnings (0+ rows, bolt-length/preload), asTable().
%                      ✅ Phase 2.9 — the engine interface contract.
%   marginBearing    - Bolt-bearing-on-flange margin, worst layer over
%                      ultimate/yield (NASA TM-106943 Eq. 72-74; required by
%                      NASA-STD-5020B §4.4.2).
%                      ✅ Phase 3.2 — allowable validated vs DABJ Ex 5-b
%                      (Pbr = 14,760 lbf; tests/tBearing.m).
%   marginShearTearout - Flange shear tear-out margin, worst checked layer
%                      (NASA TM-106943 Eq. 69-71; required by NASA-STD-5020B
%                      §4.4.2; e/D < 1.5 flagged as outside validity).
%                      ✍️ Phase 3.2 — hand-derived pin (tests/tBearing.m).
%   marginBearingUnderHead - Bearing under head/nut annulus vs the bolt
%                      axial load Pb (NASA TM-106943 Eq. 75 area + Eq. 74
%                      MS form; Pb per NASA-STD-5020B Eq. 8; required by
%                      5020B §4.4.2), gated on the SAME Fig. 8 separation-
%                      before-rupture decision as engine.boltDesignLoad:
%                      CLAMPED branch MS = Fbr·Abr / (PpMax + FF·FS·n·phi·PtL) - 1
%                      (5020B §4.4.5 — "a factor of safety is not applied
%                      to preload", so FF·FS multiplies only the external
%                      term, matching boltDesignLoad exactly); SEPARATED
%                      branch Pb = PtL (no preload term at all).
%                      ✍️ Phase 3.2 — hand-derived pin on the Ex 8-b
%                      geometry (tests/tBearing.m).
%   boltDesignLoad   - Design bolt loads for the thread checks,
%                      Pb = PpMax + FFU·FSU·n·phi·PtL and
%                      PbYield = PpMax + FFY·FSY·n·phi·PtL (NASA-STD-5020B
%                      Eq. 8 form, ultimate / yield factor pairs; a
%                      threaded-in config whose frustum geometry is
%                      incomplete falls back to the conservative bound
%                      phi = 1 — a fully-defined one gets its real phi).
%                      ✍️ Phase 3.3 — exercised through the thread checks
%                      (tests/tThreadShear.m).
%   marginBoltThreadShear - Bolt external-thread shear over the engagement,
%                      the pitch-diameter area form As = 0.75·pi·E·Le (E = pitch
%                      dia, Le = engagement; TM-106943 Eq. 63 basis) with
%                      Pult = Fsu·As, MS = Pult/Pb - 1 (Eq. 64/65).
%                      ✍️ Phase 3.3 — hand-derived pin (tests/tThreadShear.m).
%   marginNutStrength - Nut internal-thread shear (Nut config only), the
%                      0.75·pi·E·Le area (always computed; a
%                      per-joint ShearEngagementArea is not read on this
%                      path) with the NUT material Fsu/Fsy,
%                      worst of the ultimate/yield pair (TM-106943
%                      Eq. 76/77 basis + Eq. 65 MS); a spec rating caps
%                      the ultimate allowable (lower-of, 5020B §4.4.1),
%                      or stands alone (ultimate-only) when no area is
%                      available.
%                      ✍️ Phase 3.3 — hand-derived pins (tests/tThreadShear.m).
%   marginInsert     - Insert pull-out (NASA-STD-5020B §4.4.1; Insert
%                      config only): shear engagement area x PARENT
%                      material shear strength, worst of the
%                      ultimate/yield pair. The area is SPECIFIED
%                      (ThreadedMember.ShearEngagementArea) when supplied,
%                      else COMPUTED (DERIVED) from catalogue geometry
%                      (ThreadedMember.StiPitchDiameter, TM-106943/
%                      NASM33537 form), with the rated load as a
%                      ceiling on the ultimate allowable (lower-of) either
%                      way; else the MANUFACTURER rated load
%                      (RatedUltimateLoad) alone — MS = rating/Pb - 1.
%                      ✍️ Phase 3.3 — hand-derived pins (tests/tThreadShear.m).
%   shearYieldStrength - Material Fsy resolver: supplied value, or the von
%                      Mises estimate Fsy = Fty/sqrt(3) with a Basis string
%                      the margin Detail must surface (estimates never look
%                      like test data).
%                      ✍️ Hand-derived pins (tests/tThreadShear.m).
%   marginTappedParentThread - Tapped-hole PARENT-material thread shear
%                      (TappedHole config only), 0.75·pi·E·Le area
%                      with the parent Fsu (TM-106943 Eq. 79 + Eq. 65) —
%                      closes the long-standing tapped-hole gap.
%                      ✅ Phase 3.3 — area/allowable cross-checked vs DABJ
%                      Ex 6-a (0.0999 vs 0.0986 in^2; 2,698 vs 2,660 lb,
%                      both within 1.5%); MS hand-derived
%                      (tests/tThreadShear.m).
%   summary          - Analysis inputs + computed preload band as one
%                      display table (Group/Item/Value/Unit, one row per
%                      item) — a human-readable record of what went in.
%   stiffness        - Bolt/member stiffness + stiffness factor phi
%                      (Shigley conical-frustum method, general half-angle
%                      alpha = joint.FrustumAngle, default 30°, see also
%                      DABJ §8; kc uses the symbolic coefficient pi*tan(alpha),
%                      NOT a 30°-only hardcoded constant, so it stays correct
%                      at other angles; phi per NASA-STD-5020B Eq. 9).
%                      Through-bolt (nut) only; insert/tapped frustum deferred.
%                      ✅ Phase 3.1a — validated against DABJ Example 8-b
%                      (Kb 2.39e6, Kc 4.73e6, Phi 0.336; tests/tStiffness.m).
%   boltLengthCheck  - Bolt-length adequacy QUERY: supplied Bolt.Length vs
%                      the required minimum — Nut AND Insert config
%                      Lmin = grip + Le + 2·pitch (NASA-STD-5020B §4.7.4,
%                      which names "nut, nut plate, or insert" together
%                      for the SAME 2·pitch protrusion term; Le = nut
%                      height for Nut, engagement/1.5·D-default for
%                      Insert); TappedHole Lmin = grip + Le only, NO
%                      2·pitch allowance (§4.7.4's list stops at insert —
%                      a directly-tapped hole is covered by a different,
%                      non-formulaic thread-stripping criterion instead).
%                      Never errors on NaN inputs — drives the GUI's live
%                      label AND (since the Warnings build) is called by
%                      analyze on every run, feeding Result.Warnings'
%                      "BoltLengthShort" row when Shortfall > 0; still
%                      writes no Margins row.
%                      ✍️ GUI step 4.8 — hand-derived pins on the Ex 8-b
%                      geometry (tests/tBoltLength.m).
%   preloadWatchdog  - Preload-vs-allowable QUERY: PpMax (NASA-STD-5020B
%                      Eq. 1) vs the bolt's own tensile yield/ultimate
%                      allowables (boltTensileAllowable, rated-or-derived).
%                      Worst-wins bands: PreloadExceedsUltimate / Exceeds-
%                      Yield (Critical) / NearYield at 85% of yield
%                      (Warning) — the 85%/100% thresholds are a DERIVED
%                      CONVENTION, no 5020B equation number. Never errors;
%                      feeds Result.Warnings via engine.analyze.
%                      ✍️ Hand-derived pins + DABJ §9 (expected to trip the
%                      near-yield band, ~97% of its rated yield) —
%                      tests/tPreloadWatchdog.m.
%   resolveForces    - Resolve a FEM element's 6-DOF force vector onto the
%                      bolt axis: axial = signed F along the axis, shear =
%                      RSS of the two transverse forces, bending = RSS of
%                      the transverse moments (informational); torsion
%                      ignored. Single-fastener (CBUSH) projection — a
%                      geometric identity, no 5020B equation.
%                      ✍️ Phase 3.5a — hand-derived 3-4-5 pins
%                      (tests/tForces.m).
%   loadCaseFromForces - Convenience: element forces + bolt axis → a
%                      model.LoadCase with per-bolt PtL/PsL set. Options
%                      Name / Reversible (PtL = |axial| vs max(axial,0)) /
%                      ScaleFactor (applied before resolution); joint-level
%                      loads stay NaN.
%                      ✍️ Phase 3.5a — hand-derived pins (tests/tForces.m).
%   analyzeBulk      - Bulk orchestrator: joint library (data.loadJointLibrary)
%                      + elements (data.loadElements) + factors → one
%                      writetable-ready results-table row per element
%                      (identity, resolved per-bolt Axial/Shear, 14 margin MS
%                      columns + InteractionR, WorstMargin/GoverningCheck,
%                      Error, Note). NOTE: "InteractionR" (renamed from
%                      "Interaction") is sourced from Result.Margins
%                      ("Interaction").R, NOT .MS — Interaction reports a
%                      pass/fail ratio R (Pass iff R <= 1), not a margin (see
%                      marginInteraction/analyze above), so this ONE column
%                      carries a real number on the OPPOSITE-direction scale
%                      from the other 14; consumers must not sign-test or
%                      envelope it the way they do an ordinary margin. Bad
%                      rows are error-marked, never abort the batch. Joint-mode slip
%                      (3.5d): the element's
%                      bolt pattern (pattern_id, or joint name when blank)
%                      is aggregated — scaled forces vector-summed into the
%                      Eq. 84 joint totals — and evaluated ONLY when the
%                      pattern's element count equals Joint.BoltCount (the
%                      nf check); a mismatch leaves Slip NaN with a Note.
%                      Pattern torsion not modeled (Eq. 84 scope).
%                      ✅ Phase 3.5c/3.5d — end-to-end reproduces the DABJ
%                      §9 per-bolt margins AND the §9 joint-slip -0.65
%                      from a four-element pattern (tests/tBulk.m).
%   runBulk          - One-call headless workflow:
%                      runBulk(jointFile, elementsFile, settingsFile,
%                      outFile) — library load -> data.loadJointLibrary +
%                      data.loadSettings (global temps applied to every
%                      Joint + the factors) + data.loadElements ->
%                      analyzeBulk -> optional report.exportResults.
%                      settingsFile optional (empty/omitted -> default
%                      model.Factors(), temps as-is; a model.Factors
%                      object in the slot is accepted for back-compat);
%                      orchestration only. The Headless Release entry
%                      point — see matlab/examples/run_bulk_example.m.
%                      ✅ Phase 3.6 (tests/tExport.m; Step 2a settings).
%   runWorkbook      - One-call bulk run from a SINGLE multi-sheet
%                      workbook: runWorkbook(workbookFile, outFile) reads
%                      the Joints/Elements/Settings sheets by name (the
%                      data.makeTemplate fill-in workbook; both table
%                      readers header-auto-detect, so the friendly banner
%                      rows need no cleanup), applies the global temps +
%                      factors via the same shared helper runBulk uses,
%                      and runs analyzeBulk -> optional exportResults.
%                      outFile optional; must differ from workbookFile
%                      (refuses to clobber the filled input sheets). The
%                      streamlined bulk entry point — see USER_GUIDE.md §4.
%                      ✅ Step 2c — a fresh template reproduces the DABJ §9
%                      per-bolt margins end-to-end (tests/tWorkbook.m).
%   boltSizingSweep - PRELIMINARY sizing screen (Bolt Sizing tab, Phase
%                      4.9): sweeps a bolt array against one PtL/PsL pair
%                      with NO preload -- material strength only. Reports
%                      3 margins of the 15 (tension ult/yield NASA-STD-
%                      5020B Eq. 6/15 terms, shear Eq. 12-14); interaction
%                      (Eq. 20/21 BodyInShear, Eq. 22/23 ThreadsInShear,
%                      R MIRRORED from marginInteraction's direct
%                      evaluation -- not called, since that function needs
%                      a preload this screen deliberately has none of) is
%                      applied as a pass/fail GATE folded into Status, with
%                      NO number reported for it anywhere (no R, no
%                      margin, not the file's own former "solve-for-a"
%                      convention) -- a row that fails the gate alone
%                      carries the reason in its Notes column so the
%                      rejection is never unexplained. Never a substitute
%                      for engine.analyze. Tension-ultimate defaults to the
%                      bolt-only Ptu_allow = At*Ftu (labelled as such in the
%                      new TensionUltBasis column) but, given optional
%                      Library+NutSpec or a fixed ThreadedMember template,
%                      resolves EACH candidate size's own nut/insert and
%                      uses systemTensileAllowable instead -- the same
%                      §4.4.1 system minimum marginTensionUlt uses -- so a
%                      size can no longer Pass here and then fail
%                      Tension-Ultimate in a full analyze() run. Yield,
%                      shear, and interaction stay bolt-only always.
%                      ✍️ Phase 4.9 — hand-derived pins (tests/tBoltSizing.m).
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phases 2-3.
