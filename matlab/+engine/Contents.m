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
%                      ✅ Phase 2.5 — validated against DABJ §9 (+0.69).
%   marginSeparation - Joint-separation margin, min preload vs separation
%                      load (NASA-STD-5020B Eq. 19).
%                      ✅ Phase 2.6 — validated against DABJ §9 (+0.16).
%   marginBoltYield  - Bolt yield margin, spec yield allowable vs design
%                      yield load (NASA-STD-5020B Eq. 15).
%                      ✅ Phase 2.6 — validated against DABJ §9 (+0.63).
%   marginShearUlt   - Bolt ultimate-shear margin, Fsu x area by
%                      shear-plane condition (NASA-STD-5020B Eq. 14).
%                      ✅ Phase 2.7 — validated against DABJ §9 (+3.18).
%   marginInteraction- Combined tension-shear margin, solve-for-a
%                      (NASA-STD-5020B Eq. 20-23; threads-in-shear exponents
%                      deferred to Phase 3.4).
%                      ✅ Phase 2.7 — validated against DABJ §9 (+0.59).
%   marginSlip       - Slip margin, switched on Joint.SlipMode:
%                      single-fastener (default, per-bolt loads, NASA-STD-5020B
%                      Eq. 86), joint (nf·μ·PpMin vs joint totals, NASA-STD-5020B
%                      Eq. 84), or disabled (NotEvaluated).
%                      ✅ Phase 2.8 — validated against DABJ §9 (-0.65, joint mode).
%   analyze          - Single-joint solver: preload + design loads + every
%                      margin check in one call -> engine.Result.
%                      ✅ Phase 2.9 — one call reproduces all 6 DABJ §9 margins.
%   Result           - Standard result object: Preload, DesignLoads, the
%                      15-check Margins table (Pass|Fail|NotEvaluated),
%                      WorstMargin/GoverningCheck, Fig. 8 Narrative, asTable().
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
%                      axial load Pb = PpMax + n·phi·PtL (NASA TM-106943
%                      Eq. 75 area + Eq. 74 MS form; Pb per NASA-STD-5020B
%                      Eq. 8; required by 5020B §4.4.2).
%                      ✍️ Phase 3.2 — hand-derived pin on the Ex 8-b
%                      geometry (tests/tBearing.m).
%   boltDesignLoad   - Design bolt load for the thread checks,
%                      Pb = PpMax + FFU·FSU·n·phi·PtL (NASA-STD-5020B Eq. 8
%                      form; phi = 1 assumed for threaded-in configs where
%                      the stiffness frustum is deferred — conservative).
%                      ✍️ Phase 3.3 — exercised through the thread checks
%                      (tests/tThreadShear.m).
%   marginBoltThreadShear - Bolt external-thread shear over the engagement,
%                      the GROUP'S area form As = 0.75·pi·E·Le (E = pitch
%                      dia, Le = engagement; TM-106943 Eq. 63 basis) with
%                      Pult = Fsu·As, MS = Pult/Pb - 1 (Eq. 64/65).
%                      ✍️ Phase 3.3 — hand-derived pin (tests/tThreadShear.m).
%   marginNutStrength - Nut internal-thread shear (Nut config only), same
%                      group 0.75·pi·E·Le area with the NUT material Fsu
%                      (TM-106943 Eq. 76/77 basis + Eq. 65 MS).
%                      ✍️ Phase 3.3 — hand-derived pin (tests/tThreadShear.m).
%   marginInsert     - Insert pull-out from the MANUFACTURER rated load
%                      (Heli-Coil spec value on ThreadedMember.
%                      RatedUltimateLoad; NASA-STD-5020B §4.4.1) —
%                      MS = rating/Pb - 1; Insert config only.
%                      ✍️ Phase 3.3 — hand-derived pin (tests/tThreadShear.m).
%   marginTappedParentThread - Tapped-hole PARENT-material thread shear
%                      (TappedHole config only), group 0.75·pi·E·Le area
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
%                      (Shigley 30° conical frustum, see also DABJ §8;
%                      phi per NASA-STD-5020B Eq. 9). Through-bolt (nut)
%                      only; insert/tapped frustum deferred.
%                      ✅ Phase 3.1a — validated against DABJ Example 8-b
%                      (Kb 2.39e6, Kc 4.73e6, Phi 0.336; tests/tStiffness.m).
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
%                      (identity, resolved per-bolt Axial/Shear, the 15
%                      margin MS columns, WorstMargin/GoverningCheck,
%                      Error). Bad rows are error-marked, never abort the
%                      batch; Joint-mode slip is NotEvaluated in bulk
%                      (per-bolt loads only — joint totals need pattern
%                      aggregation, future).
%                      ✅ Phase 3.5c — end-to-end reproduces the DABJ §9
%                      per-bolt margins from the template CSV
%                      (tests/tBulk.m).
%   runBulk          - One-call headless workflow: library load ->
%                      data.loadJointLibrary + data.loadElements ->
%                      analyzeBulk -> optional report.exportResults.
%                      Factors optional (default model.Factors());
%                      orchestration only. The Headless Release entry
%                      point — see matlab/examples/run_bulk_example.m.
%                      ✅ Phase 3.6 (tests/tExport.m).
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phases 2-3.
