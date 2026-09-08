function r = marginSlip(joint, loadCase, preload, factors)
%MARGINSLIP  Slip (friction) margin of safety (NASA-STD-5020B Eq. 84 / Eq. 86).
%   r = engine.marginSlip(joint, loadCase, preload, factors) computes the
%   friction (slip) margin, switched on joint.SlipMode. preload is the
%   struct from engine.preload. All loads in lbf (see UNITS.md).
%
%   Modes (model.SlipMode) — the analyst selects which slip criterion
%   applies, because 5020B gives two and they answer different questions:
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
%   the worst-case min preload — preload.PpMinSlip for Eq. 84, preload.PpMin
%   for Eq. 86 (see below) — and applied tension erodes the
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

%   SLIP TAKES Eq. 5, ALWAYS — it does not follow the joint's
%   separation-critical flag. NASA-STD-5020B §4.3.1 assigns the two
%   minimum-initial-preload forms BY ANALYSIS, not by joint, and says so
%   twice:
%       p22: "For use in separation analysis of separation-critical joints
%             and for fatigue analysis..."            (Eq. 4, 1 - Γ)
%       p23: "For use in JOINT-SLIP ANALYSIS and separation analysis of
%             joints that are not separation-critical..."
%                                                     (Eq. 5, 1 - Γ/√nf)
%   and again at p47 (Eq. 26b) for the thermal-adjusted form. So joint-slip
%   analysis takes Eq. 5 unconditionally, even on a joint the analyst has
%   flagged separation-critical.
%
%   The physics behind the √nf (Appendix A.2's rationale) is why the split
%   is by analysis: slip resists on the SUMMED friction of all nf
%   fasteners, so the joint's AVERAGE minimum preload is the right
%   statistic and the installation variation averages down. Separation of a
%   separation-critical joint is a per-fastener event — one bolt letting go
%   is the failure — so the full Γ applies to the single worst bolt.
%
%   The Eq. 84 branch used the joint-scoped preload.PpMin until
%   2026-08-13, which fed it the Eq. 4 value on separation-critical
%   joints. Conservative (Eq. 4 is the lower preload, so slip capacity was
%   understated — about 14%% at Γ = 0.25, nf = 4) but not what §4.3.1
%   assigns. On a non-separation-critical joint the two forms coincide, so
%   nothing there ever moved.
%
%   EQ. 86 DOES NOT GET THE √nf, and this is the one place the text and the
%   rationale pull apart. §4.3.1 says "joint-slip analysis" without
%   distinguishing the two equations, and Eq. 86 is introduced (p74) as
%   "another acceptable approach" to the same analysis — so on the text
%   alone it would take Eq. 5. But A.2.1, "Rationale for Eqs. 5 and 26b"
%   (p50), states the premise the factor rests on:
%
%     "When performing slip analysis, the concern related to preload is
%      NOT the variation in preload for a single fastener, it is the
%      variation in TOTAL preload for the joint... the probability
%      distribution for total preload is the same as the probability
%      distribution for the MEAN preload for the bolts in the pattern...
%      a standard deviation equal to the standard deviation of the
%      population divided by the SQUARE ROOT OF THE NUMBER OF BOLTS."
%
%   Eq. 84's capacity is nf·μ·PpMin — the joint total, exactly the
%   quantity A.2.1 describes, so the √nf applies. Eq. 86's is μ·PpMin for
%   ONE fastener, which is the case A.2.1 explicitly excludes. Applying
%   the averaging there would credit a variance reduction that the
%   single-fastener check never earns, and it is non-conservative.
%
%   So this branch keeps the joint-scoped PpMin. NOTE that is not
%   obviously right either: on a joint that is not separation-critical,
%   PpMin is itself the Eq. 5 form, so Eq. 86 still sees a √nf there.
%   Taking A.2.1 literally would want a third, full-Γ single-fastener
%   minimum — a form 5020B never prints for slip. Left as the
%   pre-existing behaviour rather than invented; recorded in
%   COMPLIANCE.md as an open question.
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
    % PpMinSlip, NOT PpMin — see the SLIP TAKES Eq. 5 note in the header.
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
                "engine.preload - the Eq. 5 joint-scoped minimum, NOT PpMin " + ...
                "(see the SLIP TAKES Eq. 5 note)"), ...
            engine.eqInput("FSslip", FSslip, "", "Factors.FSSlip"), ...
            engine.eqInput("FFslip", FFslip, "", "Factors.FFSlip"), ...
            engine.eqInput("PsL_joint", PsLjoint, "lbf", ...
                "LoadCase.JointShearLimitLoad"), ...
            engine.eqInput("PtL_joint", PtLjoint, "lbf", ...
                "LoadCase.JointTensileLimitLoad"), ...
            engine.eqInput("Capacity", Capacity, "lbf", ...
                "NASA-STD-5020B Eq. 84 numerator - nf*mu*PpMinSlip"), ...
            engine.eqInput("Demand", Demand, "lbf", ...
                "NASA-STD-5020B Eq. 84 denominator - " + ...
                "FSslip*FFslip*(PsL_joint + mu*PtL_joint)")]);
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
    % PpMin, NOT PpMinSlip — the joint-scoped minimum. See EQ. 86 DOES NOT
    % GET THE √nf in the header: A.2.1 ties that factor to the joint TOTAL,
    % which is not what this branch computes.
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
                "engine.preload - NASA-STD-5020B Eq. 2, the joint-scoped " + ...
                "minimum (Eq. 86 gets no sqrt(nf) - see the header)"), ...
            engine.eqInput("FSslip", FSslip, "", "Factors.FSSlip"), ...
            engine.eqInput("FFslip", FFslip, "", "Factors.FFSlip"), ...
            engine.eqInput("PsL", PsL, "lbf", "LoadCase.BoltShearLimitLoad"), ...
            engine.eqInput("PtL", PtL, "lbf", "LoadCase.BoltTensileLimitLoad"), ...
            engine.eqInput("Capacity", Capacity, "lbf", ...
                "NASA-STD-5020B Eq. 86 numerator - mu*PpMin"), ...
            engine.eqInput("Demand", Demand, "lbf", ...
                "NASA-STD-5020B Eq. 86 denominator - FSslip*FFslip*(PsL + mu*PtL)")]);
end
end
