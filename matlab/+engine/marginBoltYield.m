function r = marginBoltYield(joint, designLoads)
%MARGINBOLTYIELD  Bolt yield-tension margin of safety (NASA-STD-5020A Eq. 15).
%   r = engine.marginBoltYield(joint, designLoads) computes the bolt yield
%   margin for one joint. designLoads is the struct from
%   engine.designLoads. All loads in lbf (see UNITS.md).
%
%   With separation before rupture assured (the same Fig. 8 logic as the
%   ultimate-tension check — see engine.marginTensionUlt), the bolt sees
%   only the external design load, so the margin is allowable over applied:
%       MS = Pty_allow / Pty - 1                             (Eq. 15)
%   where Pty_allow = joint.BoltRatedYieldLoad (spec yield allowable) and
%   Pty = designLoads.Pty (FSY * FFY * PtL).
%
%   Returned struct fields:
%       MS      margin of safety (double)
%       Method  string: governing equation
%
%   Pty_allow = joint.BoltRatedYieldLoad and is required to be set; the
%   (Fty/Ftu)*Ptu_allow fallback for an unset allowable is Phase 3.
%
%   Validated against the DABJ Section 9 class problem (Solutions-18, via
%   validation.dabjSection9): MS = 11,400/6,987.5 - 1 = +0.63.

arguments
    joint       (1,1) model.Joint
    designLoads (1,1) struct
end

PtyAllow = joint.BoltRatedYieldLoad;
if isnan(PtyAllow)
    error("engine:marginBoltYield:allowableRequired", ...
        "BoltRatedYieldLoad required for bolt yield margin; (Fty/Ftu)*Ptu_allow fallback is Phase 3.");
end

% NASA-STD-5020A Eq. 15 — MS = Pty_allow / Pty - 1
MS = PtyAllow / designLoads.Pty - 1;

r = struct( ...
    "MS",     MS, ...
    "Method", "5020A Eq. 15 (bolt yield)");
end
