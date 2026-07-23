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
%   summary          - Analysis inputs + computed preload band as one
%                      display table (Group/Item/Value/Unit, one row per
%                      item) — a human-readable record of what went in.
%   stiffness        - Bolt/member stiffness + stiffness factor phi
%                      (Shigley 30° conical frustum, see also DABJ §8;
%                      phi per NASA-STD-5020B Eq. 9). Through-bolt (nut)
%                      only; insert/tapped frustum deferred.
%                      ✅ Phase 3.1a — validated against DABJ Example 8-b
%                      (Kb 2.39e6, Kc 4.73e6, Phi 0.336; tests/tStiffness.m).
%
%   Will also hold: applied-load resolution and the remaining margin checks
%   (thread/nut/insert, tapped-hole parent-thread — Phase 3.3).
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phases 2-3.
