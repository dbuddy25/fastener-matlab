function r = marginInteraction(joint, designLoads)
%MARGININTERACTION  Combined tension-shear margin (NASA-STD-5020A Eq. 20-23).
%   r = engine.marginInteraction(joint, designLoads) computes the
%   tension-shear interaction margin for one joint by the NASA-STD-5020A
%   "solve-for-a" method. designLoads is the struct from
%   engine.designLoads. All loads in lbf (see UNITS.md).
%
%   Load ratios at the design loads:
%       Rt = Ptu / Ptu_allow          (Ptu_allow = joint.BoltRatedUltimateLoad)
%       Rs = Psu / Psu_allow          (Psu_allow from engine.marginShearUlt,
%                                      reused so both checks share one allowable)
%   The margin comes from the load factor a > 0 that scales BOTH design
%   loads to the interaction envelope:
%       (a*Rt)^et + (a*Rs)^es = 1,    MS = a - 1
%   with exponents by shear-plane condition:
%       BodyInShear    — et = 1.5, es = 2.5 (NASA-STD-5020A Eq. 20/21; validated)
%       ThreadsInShear — the NASA-STD-5020A exponents differ and no validation
%                        case exercises them yet, so this path ERRORS
%                        rather than return an unvalidated number
%                        (Phase 3.4).
%   The root is found with fzero from a starting guess of 1: g(a) is
%   -1 at a = 0 and strictly increasing, so the root is unique.
%
%   Returned struct fields:
%       MS      margin of safety (double)
%       a       the solved load factor (MS = a - 1)
%       Method  string: governing equation + exponents
%
%   Validated against the DABJ Section 9 class problem (Solutions-20..21,
%   via validation.dabjSection9): Rt = 9,000/15,200 = 0.592,
%   Rs = 2,511.6/10,492.4 = 0.239 -> a = 1.59, MS = +0.59.

arguments
    joint       (1,1) model.Joint
    designLoads (1,1) struct
end

PtuAllow = joint.BoltRatedUltimateLoad;
if isnan(PtuAllow)
    error("engine:marginInteraction:allowableRequired", ...
        "BoltRatedUltimateLoad required for interaction margin; At*Ftu fallback is Phase 3.");
end

switch joint.ShearPlane
    case model.ShearPlaneCondition.BodyInShear
        % NASA-STD-5020A Eq. 20/21 (body in shear) — envelope Rt^1.5 + Rs^2.5 = 1
        et = 1.5;                               % tension exponent
        es = 2.5;                               % shear exponent
    case model.ShearPlaneCondition.ThreadsInShear
        % NASA-STD-5020A Eq. 22/23 (threads in shear) — exponents differ from
        % Eq. 20/21; unvalidated here, so this path errors (Phase 3.4)
        error("engine:marginInteraction:threadsInShearUnvalidated", ...
            "Threads-in-shear interaction exponents need a validation case (Phase 3.4)");
    otherwise
        error("engine:marginInteraction:unknownShearPlane", ...
            "Unsupported shear-plane condition: %s", string(joint.ShearPlane));
end

shearUlt = engine.marginShearUlt(joint, designLoads);   % reuse its allowable
% NASA-STD-5020A Eq. 20-23 load ratios — Rt = Ptu / Ptu_allow
Rt = designLoads.Ptu / PtuAllow;
% NASA-STD-5020A Eq. 20-23 load ratios — Rs = Psu / Psu_allow
Rs = designLoads.Psu / shearUlt.ShearAllowable;

% NASA-STD-5020A Eq. 20/21 solve-for-a — (a·Rt)^et + (a·Rs)^es = 1.
% g(0) = -1 and g is strictly increasing for a > 0, so the root is unique;
% guess 1 (root ~1.59 here).
g = @(a) (a*Rt)^et + (a*Rs)^es - 1;
a = fzero(g, 1);

% NASA-STD-5020A Eq. 20/21 solve-for-a margin — MS = a - 1
MS = a - 1;

r = struct( ...
    "MS",     MS, ...
    "a",      a, ...
    "Method", "NASA-STD-5020A Eq. 20/21 solve-for-a (body in shear, exp 1.5/2.5)");
end
