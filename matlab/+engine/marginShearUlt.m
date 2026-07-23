function r = marginShearUlt(joint, designLoads)
%MARGINSHEARULT  Bolt ultimate-shear margin of safety (NASA-STD-5020A Eq. 14).
%   r = engine.marginShearUlt(joint, designLoads) computes the bolt
%   ultimate-shear margin for one joint. designLoads is the struct from
%   engine.designLoads. All loads in lbf (see UNITS.md).
%
%   The shear allowable is Fsu times the area cut by the shear plane,
%   chosen by joint.ShearPlane:
%       BodyInShear    — full-diameter shank area (joint.Bolt.BodyArea)
%       ThreadsInShear — minor (thread-root) area (joint.Bolt.MinorArea)
%   Then:
%       Psu_allow = Fsu * A_shear
%       MS = Psu_allow / Psu - 1                             (Eq. 14)
%   where Fsu = joint.BoltMaterial.Fsu and Psu = designLoads.Psu
%   (FSU * FFU * PsL).
%
%   Returned struct fields:
%       MS              margin of safety (double)
%       ShearAllowable  Psu_allow, lbf (reused by engine.marginInteraction)
%       Method          string: governing equation
%
%   Validated against the DABJ Section 9 class problem (Solutions-19, via
%   validation.dabjSection9): threads NOT in the shear plane, so
%   Psu_allow = 95,000 * (pi/4)*0.375^2 = 10,492 lbf and
%   MS = 10,492.4/2,511.6 - 1 = +3.18.

arguments
    joint       (1,1) model.Joint
    designLoads (1,1) struct
end

switch joint.ShearPlane
    case model.ShearPlaneCondition.BodyInShear
        % NASA-STD-5020A Eq. 12 (body in shear) — Psu_allow = Fsu · A_body
        area = joint.Bolt.BodyArea;
    case model.ShearPlaneCondition.ThreadsInShear
        % NASA-STD-5020A Eq. 13 (threads in shear) — Psu_allow = Fsu · A_minor
        area = joint.Bolt.MinorArea;
    otherwise
        error("engine:marginShearUlt:unknownShearPlane", ...
            "Unsupported shear-plane condition: %s", string(joint.ShearPlane));
end

Fsu = joint.BoltMaterial.Fsu;
% NASA-STD-5020A Eq. 12/13 — Psu_allow = Fsu · A_shear (A_shear selected by
% shear-plane condition above)
ShearAllowable = Fsu * area;                                 % Psu_allow, lbf
% NASA-STD-5020A Eq. 14 — MS = Psu_allow / Psu - 1
MS = ShearAllowable / designLoads.Psu - 1;

r = struct( ...
    "MS",             MS, ...
    "ShearAllowable", ShearAllowable, ...
    "Method",         "5020A Eq. 12/13 allowable + Eq. 14 (ultimate shear, area by shear-plane condition)");
end
