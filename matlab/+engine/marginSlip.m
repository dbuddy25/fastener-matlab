function r = marginSlip(joint, loadCase, preload, factors)
%MARGINSLIP  Slip (friction) margin of safety (NASA-STD-5020B Eq. 84 / Eq. 86).
%   r = engine.marginSlip(joint, loadCase, preload, factors) computes the
%   friction (slip) margin, switched on joint.SlipMode. preload is the
%   struct from engine.preload. All loads in lbf (see UNITS.md).
%
%   Modes (model.SlipMode) — 5020B gives two criteria answering different
%   questions, so the analyst selects:
%
%   SingleFastener (DEFAULT) — per-fastener slip on PER-BOLT limit loads,
%   NASA-STD-5020B Eq. 86 (Appendix A.10):
%       MS = (mu*PpMin) / (FS*FF*(PsL + mu*PtL)) - 1                 (Eq. 86)
%
%   Joint — total friction capacity across all nf bolts vs JOINT-TOTAL
%   limit loads (NOT nf x per-bolt: the pattern distributes load unevenly),
%   NASA-STD-5020B Eq. 84:
%       MS = (nf*mu*PpMin) / (FS*FF*(PsL_joint + mu*PtL_joint)) - 1  (Eq. 84)
%   Eq. 84 carries FS only; the slip fitting factor FFslip (default 1.0)
%   is applied as well for consistency with Eq. 86.
%
%   Ignored — MS = NaN (analyze renders NotEvaluated).
%
%   mu = joint.FrictionCoefficient; if mu = 0 the check is not evaluated
%   (MS = NaN, explanatory Method). Applied tension erodes the clamp,
%   hence the mu*PtL demand term. NaN required loads error with
%   engine:marginSlip:boltLoadsRequired / jointLoadsRequired.
%
%   WHICH MINIMUM PRELOAD. Eq. 84 takes preload.PpMinSlip (the Eq. 5 form,
%   1 - Γ/√nf) on every joint, separation-critical or not: §4.3.1 assigns
%   the two minimum-preload forms BY ANALYSIS, not by joint — p23 gives
%   Eq. 5 to "joint-slip analysis" unconditionally, p22 gives Eq. 4 (1 - Γ)
%   to separation analysis of separation-critical joints. The physics
%   (A.2.1, p50): slip resists on the SUMMED friction of nf fasteners, so
%   the joint's mean preload is the right statistic and installation
%   scatter averages down by √nf; separation is a per-fastener event, so
%   the full Γ applies to the single worst bolt.
%
%   Eq. 86 takes the joint-scoped preload.PpMin and NOT the √nf form.
%   A.2.1 ties the √nf to "the variation in TOTAL preload for the joint",
%   which Eq. 86's single-fastener capacity mu*PpMin is not; crediting the
%   averaging there is non-conservative. On a non-separation-critical joint
%   PpMin is itself the Eq. 5 form, so Eq. 86 still sees a √nf; a full-Γ
%   single-fastener minimum is a form 5020B never prints for slip, so this
%   is left as is and recorded in COMPLIANCE.md as an open question.
%
%   Returned struct fields:
%       MS      margin of safety (double; NaN when ignored or mu = 0)
%       Method  string: governing equation
%       Inputs  engine.eqInput array: every term, with its source
%
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
        "Method", "NASA-STD-5020B Eq. 84/86 (slip) — ignored", ...
        "Inputs", engine.eqInput());
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
        "Method", label + " — not evaluated, μ = 0", ...
        "Inputs", engine.eqInput());
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
    % PpMinSlip, NOT PpMin — see WHICH MINIMUM PRELOAD in the header.
    Capacity = nf * mu * preload.PpMinSlip;
    % NASA-STD-5020B Eq. 84 (denominator) — Demand = FSslip·FFslip·(PsL_joint + μ·PtL_joint)
    % (applied joint shear + friction lost to applied joint tension; FFslip
    % applied beyond the standard's FS for consistency with Eq. 86)
    Demand = FSslip * FFslip * (PsLjoint + mu * PtLjoint);
    % NASA-STD-5020B Eq. 84 — MS = (nf·μ·PpMinSlip) / (FSslip·FFslip·(PsL_joint + μ·PtL_joint)) - 1
    MS = Capacity / Demand - 1;

    r = struct( ...
        "MS",     MS, ...
        "Method", sprintf("NASA-STD-5020B Eq. 84 (joint slip, %g bolts) - MS = (nf*mu*PpMinSlip)/(FSslip*FFslip*(PsL_joint + mu*PtL_joint)) - 1", nf), ...
        "Inputs", [ ...
            engine.eqInput("nf", nf, "", "Joint.BoltCount"), ...
            engine.eqInput("mu", mu, "", "Joint.FrictionCoefficient"), ...
            engine.eqInput("PpMinSlip", preload.PpMinSlip, "lbf", ...
                "engine.preload, Eq. 5 joint minimum (NOT PpMin)"), ...
            engine.eqInput("FSslip", FSslip, "", "Factors.FSSlip"), ...
            engine.eqInput("FFslip", FFslip, "", "Factors.FFSlip"), ...
            engine.eqInput("PsL_joint", PsLjoint, "lbf", ...
                "LoadCase.JointShearLimitLoad"), ...
            engine.eqInput("PtL_joint", PtLjoint, "lbf", ...
                "LoadCase.JointTensileLimitLoad"), ...
            engine.eqInput("Capacity", Capacity, "lbf", ...
                "Eq. 84 numerator = nf*mu*PpMinSlip"), ...
            engine.eqInput("Demand", Demand, "lbf", ...
                "Eq. 84 denom = FSslip*FFslip*(PsL_joint+mu*PtL_joint)")]);
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
    % PpMin, NOT PpMinSlip — the joint-scoped minimum; see WHICH MINIMUM
    % PRELOAD in the header.
    Capacity = mu * preload.PpMin;
    % NASA-STD-5020B Eq. 86 (denominator) — Demand = FSslip·FFslip·(PsL + μ·PtL)
    % (this fastener's applied shear + friction lost to its applied tension)
    Demand = FSslip * FFslip * (PsL + mu * PtL);
    % NASA-STD-5020B Eq. 86 — MS = (μ·PpMin) / (FSslip·FFslip·(PsL + μ·PtL)) - 1
    MS = Capacity / Demand - 1;

    r = struct( ...
        "MS",     MS, ...
        "Method", "NASA-STD-5020B Eq. 86 (single-fastener slip) - MS = (mu*PpMin)/(FSslip*FFslip*(PsL + mu*PtL)) - 1", ...
        "Inputs", [ ...
            engine.eqInput("mu", mu, "", "Joint.FrictionCoefficient"), ...
            engine.eqInput("PpMin", preload.PpMin, "lbf", ...
                "engine.preload, 5020B Eq. 2 (Eq. 86 gets no sqrt(nf))"), ...
            engine.eqInput("FSslip", FSslip, "", "Factors.FSSlip"), ...
            engine.eqInput("FFslip", FFslip, "", "Factors.FFSlip"), ...
            engine.eqInput("PsL", PsL, "lbf", "LoadCase.BoltShearLimitLoad"), ...
            engine.eqInput("PtL", PtL, "lbf", "LoadCase.BoltTensileLimitLoad"), ...
            engine.eqInput("Capacity", Capacity, "lbf", ...
                "Eq. 86 numerator = mu*PpMin"), ...
            engine.eqInput("Demand", Demand, "lbf", ...
                "Eq. 86 denom = FSslip*FFslip*(PsL+mu*PtL)")]);
end
end
