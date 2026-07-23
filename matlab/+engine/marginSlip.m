function r = marginSlip(joint, loadCase, preload, factors)
%MARGINSLIP  Joint-slip margin of safety (NASA-STD-5020A Eq. 86).
%   r = engine.marginSlip(joint, loadCase, preload, factors) computes the
%   friction (slip) margin for one joint. preload is the struct from
%   engine.preload. All loads in lbf (see UNITS.md).
%
%   Slip is a JOINT-LEVEL check: it compares the total friction resistance
%   from clamp-up across all nf bolts against the total applied joint shear,
%   using JOINT limit loads (loadCase.JointShear/TensileLimitLoad), NOT
%   nf x per-bolt loads (bolt-pattern distribution makes those differ):
%       MS = (nf*mu*PpMin) / (FSslip*FFslip*(PsL_joint + mu*PtL_joint)) - 1  (Eq. 86)
%   where nf = joint.BoltCount, mu = joint.FrictionCoefficient,
%   PpMin = preload.PpMin (worst-case min preload), and applied joint
%   tension erodes the clamp (hence the mu*PtL_joint demand term).
%
%   If mu = 0 the check is not evaluated: MS = NaN with an explanatory
%   Method string. If either joint-level limit load is NaN, errors with id
%   engine:marginSlip:jointLoadsRequired.
%
%   Returned struct fields:
%       MS      margin of safety (double; NaN when mu = 0)
%       Method  string: governing equation
%
%   Validated against the DABJ Section 9 class problem (Solutions-23, via
%   validation.dabjSection9): MS = 2,587.9/7,299 - 1 = -0.65 (a deliberate
%   failing margin -- the book's joint slips at limit load).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    preload  (1,1) struct
    factors  (1,1) model.Factors
end

mu = joint.FrictionCoefficient;
if mu == 0
    r = struct( ...
        "MS",     NaN, ...
        "Method", "NASA-STD-5020A Eq. 86 (joint slip) — not evaluated, μ = 0");
    return
end

PsLjoint = loadCase.JointShearLimitLoad;
PtLjoint = loadCase.JointTensileLimitLoad;
if isnan(PsLjoint) || isnan(PtLjoint)
    error("engine:marginSlip:jointLoadsRequired", ...
        "Joint slip (NASA-STD-5020A Eq. 86) requires joint-level limit loads " + ...
        "(LoadCase.JointShearLimitLoad / JointTensileLimitLoad). They are " + ...
        "NOT simply BoltCount x per-bolt loads because of bolt-pattern " + ...
        "load distribution — set them explicitly on the LoadCase.");
end

nf     = joint.BoltCount;
FSslip = factors.FSSlip;

% NASA-STD-5020A Eq. 86 (numerator) — Capacity = nf·μ·PpMin (friction resistance from clamp-up)
Capacity = nf * mu * preload.PpMin;
% NASA-STD-5020A Eq. 86 (denominator) — Demand = FSslip·FFslip·(PsL_joint + μ·PtL_joint)
% (applied joint shear + friction lost to applied joint tension)
Demand = FSslip * factors.FFSlip * (PsLjoint + mu * PtLjoint);
% NASA-STD-5020A Eq. 86 — MS = (nf·μ·PpMin) / (FSslip·FFslip·(PsL_joint + μ·PtL_joint)) - 1
MS = Capacity / Demand - 1;

r = struct( ...
    "MS",     MS, ...
    "Method", "NASA-STD-5020A Eq. 86 (joint slip)");
end
