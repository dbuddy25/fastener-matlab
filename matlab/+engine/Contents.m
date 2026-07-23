% +ENGINE  Analysis math — the core (GUI-independent, headless-capable).
%
%   preload  - Min/max bolt preload incl. thermal (5020A Eq. 25/26 + 1/2).
%              ✅ Phase 2.4 — validated against DABJ §9 (tests/tDabjCase.m).
%
%   Will also hold: bolt/member stiffness + stiffness factor, applied-load
%   resolution, the 15 margin checks, interaction (5020A Eq. 20-23),
%   separation/slip, tapped-hole parent-thread check, and the single-joint
%   solver.
%
%   Reference for structure: MATLAB_BUILD_GUIDE.md, Phases 2-3.
