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
%
%   Will also hold: bolt/member stiffness + stiffness factor, applied-load
%   resolution, the remaining margin checks, interaction (5020A Eq. 20-23),
%   separation/slip, tapped-hole parent-thread check, and the single-joint
%   solver.
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phases 2-3.
