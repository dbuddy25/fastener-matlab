% +ENGINE  Analysis math — the core (GUI-independent, headless-capable).
%
%   preload          - Min/max bolt preload incl. thermal (5020A Eq. 25/26 + 1/2).
%                      ✅ Phase 2.4 — validated against DABJ §9 (tests/tDabjCase.m).
%   designLoads      - Design ultimate/yield/separation loads from limit loads
%                      x safety/fitting factors.
%                      ✅ Phase 2.5 — validated against DABJ §9.
%   marginTensionUlt - Ultimate-tension margin with the 5020A Fig. 8
%                      separation-before-rupture gate (Eq. 6; rupture path
%                      deferred to Phase 3.1 stiffness).
%                      ✅ Phase 2.5 — validated against DABJ §9 (+0.69).
%   marginSeparation - Joint-separation margin, min preload vs separation
%                      load (5020A Eq. 19).
%                      ✅ Phase 2.6 — validated against DABJ §9 (+0.16).
%   marginBoltYield  - Bolt yield margin, spec yield allowable vs design
%                      yield load (5020A Eq. 15).
%                      ✅ Phase 2.6 — validated against DABJ §9 (+0.63).
%   marginShearUlt   - Bolt ultimate-shear margin, Fsu x area by
%                      shear-plane condition (5020A Eq. 14).
%                      ✅ Phase 2.7 — validated against DABJ §9 (+3.18).
%   marginInteraction- Combined tension-shear margin, solve-for-a
%                      (5020A Eq. 20-23; threads-in-shear exponents
%                      deferred to Phase 3.4).
%                      ✅ Phase 2.7 — validated against DABJ §9 (+0.59).
%   marginSlip       - Joint-slip margin, nf·μ·PpMin friction capacity vs
%                      joint-level shear demand (DABJ Eq. 84).
%                      ✅ Phase 2.8 — validated against DABJ §9 (-0.65).
%   analyze          - Single-joint solver: preload + design loads + every
%                      margin check in one call -> engine.Result.
%                      ✅ Phase 2.9 — one call reproduces all 6 DABJ §9 margins.
%   Result           - Standard result object: Preload, DesignLoads, the
%                      15-check Margins table (Pass|Fail|NotEvaluated),
%                      WorstMargin/GoverningCheck, Fig. 8 Narrative, asTable().
%                      ✅ Phase 2.9 — the engine interface contract.
%
%   Will also hold: bolt/member stiffness + stiffness factor, applied-load
%   resolution, and the remaining margin checks (bearing, thread/nut/insert,
%   tapped-hole parent-thread — Phases 3.1-3.3).
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phases 2-3.
