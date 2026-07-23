function r = marginSlip(joint, loadCase, preload, factors)
%MARGINSLIP  Slip (friction) margin of safety (NASA-STD-5020B Eq. 84 / Eq. 86).
%   r = engine.marginSlip(joint, loadCase, preload, factors) computes the
%   friction (slip) margin, switched on joint.SlipMode. preload is the
%   struct from engine.preload. All loads in lbf (see UNITS.md).
%
%   Modes (model.SlipMode; mirrors the reference Python tool's selector):
%
%   SingleFastener (DEFAULT) — per-fastener slip using PER-BOLT limit loads
%   (loadCase.BoltShear/TensileLimitLoad), per NASA-STD-5020B Eq. 86
%   (Appendix A.10, assess slip individually at each fastener location):
%       MS = (mu*PpMin) / (FS*FF*(PsL + mu*PtL)) - 1                 (Eq. 86)
%
%   Joint — joint-level slip: total friction capacity from clamp-up across
%   all nf bolts vs JOINT-TOTAL limit loads
%   (loadCase.JointShear/TensileLimitLoad), NOT nf x per-bolt (bolt-pattern
%   distribution makes those differ), per NASA-STD-5020B Eq. 84:
%       MS = (nf*mu*PpMin) / (FS*FF*(PsL_joint + mu*PtL_joint)) - 1  (Eq. 84)
%   (The standard's Eq. 84 carries FS only; the slip fitting factor FFslip
%   is applied as well for consistency with Eq. 86 — its default is 1.0.)
%
%   Ignored — check not evaluated: MS = NaN (analyze renders NotEvaluated).
%
%   In both evaluated modes mu = joint.FrictionCoefficient, PpMin =
%   preload.PpMin (worst-case min preload), and applied tension erodes the
%   clamp (hence the mu*PtL demand term). If mu = 0 the check is not
%   evaluated: MS = NaN with an explanatory Method string. NaN required
%   loads error with id engine:marginSlip:boltLoadsRequired
%   (single-fastener) or engine:marginSlip:jointLoadsRequired (joint).
%
%   Returned struct fields:
%       MS      margin of safety (double; NaN when ignored or mu = 0)
%       Method  string: governing equation
%
%   Validated against the DABJ Section 9 class problem (Solutions-23, via
%   validation.dabjSection9, pinned to Joint mode): MS = 2,587.9/7,299 - 1
%   = -0.65 (a deliberate failing margin -- the book's joint slips at limit
%   load).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    preload  (1,1) struct
    factors  (1,1) model.Factors
end

mode = joint.SlipMode;
if mode == model.SlipMode.Ignored
    r = struct( ...
        "MS",     NaN, ...
        "Method", "NASA-STD-5020B Eq. 84/86 (slip) — ignored");
    return
end

mu = joint.FrictionCoefficient;
if mu == 0
    if mode == model.SlipMode.Joint
        label = "NASA-STD-5020B Eq. 84 (joint slip)";
    else
        label = "NASA-STD-5020B Eq. 86 (single-fastener slip)";
    end
    r = struct( ...
        "MS",     NaN, ...
        "Method", label + " — not evaluated, μ = 0");
    return
end

FSslip = factors.FSSlip;
FFslip = factors.FFSlip;

if mode == model.SlipMode.Joint
    PsLjoint = loadCase.JointShearLimitLoad;
    PtLjoint = loadCase.JointTensileLimitLoad;
    if isnan(PsLjoint) || isnan(PtLjoint)
        error("engine:marginSlip:jointLoadsRequired", ...
            "Joint slip (NASA-STD-5020B Eq. 84) requires joint-level limit loads " + ...
            "(LoadCase.JointShearLimitLoad / JointTensileLimitLoad). They are " + ...
            "NOT simply BoltCount x per-bolt loads because of bolt-pattern " + ...
            "load distribution — set them explicitly on the LoadCase.");
    end

    nf = joint.BoltCount;
    % NASA-STD-5020B Eq. 84 (numerator) — Capacity = nf·μ·PpMin (friction resistance from clamp-up, all nf bolts)
    Capacity = nf * mu * preload.PpMin;
    % NASA-STD-5020B Eq. 84 (denominator) — Demand = FSslip·FFslip·(PsL_joint + μ·PtL_joint)
    % (applied joint shear + friction lost to applied joint tension; FFslip
    % applied beyond the standard's FS for consistency with Eq. 86)
    Demand = FSslip * FFslip * (PsLjoint + mu * PtLjoint);
    % NASA-STD-5020B Eq. 84 — MS = (nf·μ·PpMin) / (FSslip·FFslip·(PsL_joint + μ·PtL_joint)) - 1
    MS = Capacity / Demand - 1;

    r = struct( ...
        "MS",     MS, ...
        "Method", sprintf("NASA-STD-5020B Eq. 84 (joint slip, %g bolts)", nf));
else  % model.SlipMode.SingleFastener (the default)
    PsL = loadCase.BoltShearLimitLoad;
    PtL = loadCase.BoltTensileLimitLoad;
    if isnan(PsL) || isnan(PtL)
        error("engine:marginSlip:boltLoadsRequired", ...
            "Single-fastener slip (NASA-STD-5020B Eq. 86) requires per-bolt limit " + ...
            "loads (LoadCase.BoltShearLimitLoad / BoltTensileLimitLoad) — set " + ...
            "them on the LoadCase.");
    end

    % NASA-STD-5020B Eq. 86 (numerator) — Capacity = μ·PpMin (one fastener's friction resistance from clamp-up)
    Capacity = mu * preload.PpMin;
    % NASA-STD-5020B Eq. 86 (denominator) — Demand = FSslip·FFslip·(PsL + μ·PtL)
    % (this fastener's applied shear + friction lost to its applied tension)
    Demand = FSslip * FFslip * (PsL + mu * PtL);
    % NASA-STD-5020B Eq. 86 — MS = (μ·PpMin) / (FSslip·FFslip·(PsL + μ·PtL)) - 1
    MS = Capacity / Demand - 1;

    r = struct( ...
        "MS",     MS, ...
        "Method", "NASA-STD-5020B Eq. 86 (single-fastener slip)");
end
end
