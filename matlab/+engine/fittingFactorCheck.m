function r = fittingFactorCheck(joint, factors)
%FITTINGFACTORCHECK  Is the separation fitting factor one NASA-STD-5020B expects?
%   r = engine.fittingFactorCheck(joint, factors) screens factors.FFSep
%   against NASA-STD-5020B §4.2.2 (p19):
%
%     "Separation analysis of joints that are separation-critical should
%      include a fitting factor of at least 1.15 as a multiplier of the
%      required separation factor of safety."
%
%   THE TOOL ALREADY KNOWS THE ANSWER TO THE CONDITION. Separation-critical
%   is not something the analyst has to be asked about a second time — it
%   is joint.PreloadSpec.SeparationCritical, and engine.preload already
%   acts on it, selecting the NASA-STD-5020B Eq. 4 minimum initial preload
%   (full Gamma) over Eq. 5 (Gamma/sqrt(nf)) per §4.3.1 p22. §4.2.2 levies
%   a SECOND obligation from the same flag, on the fitting factor, and
%   nothing connected the two: a separation-critical joint analyzed at
%   defaults got the Eq. 4 preload and an FFSep of 1.0, silently.
%
%   A WARNING, NOT A FLOOR, and not a changed factor. §4.2.2 is a "should"
%   with explicit carve-outs — a fitting factor of 1.0 "may be adequate"
%   when the joint's functionality is verified by test to limit load or
%   greater, or when its load paths and stresses come from detailed FEA
%   correlated against tests of similar systems. Both are real conditions
%   this project's joints meet routinely, and neither is visible to the
%   tool. Quietly promoting FFSep to 1.15 would also move every separation
%   margin without the analyst asking for it. So the tool names the
%   section and leaves the number alone.
%
%   THE OTHER §4.2.2 FITTING-FACTOR RULES ARE NOT CHECKED, deliberately:
%     - "Yield strength analysis of threaded fastening systems whose
%        performance is PARTICULARLY SENSITIVE TO LOCAL YIELDING should
%        include a fitting factor of at least 1.15" — the condition is an
%        engineering judgment about the joint's behaviour, not a modelled
%        property. Nothing to test against.
%     - "A shear-critical joint typically warrants a larger fitting
%        factor" — "typically" and "larger", with no number.
%   Only the separation rule states a threshold AND keys off a condition
%   the joint model already carries.
%
%   FIGURE 1 (TFSR 4, §4.2.3) IS A DIFFERENT QUESTION AND STAYS UNENCODED.
%   It sets FS_sep — not FF — from the HAZARD CLASS of a separation
%   (catastrophic -> the program's FS_u; critical -> greater of 1.2 and the
%   program's FS_y; neither -> greater of 1.0 and the program's test
%   factor). Hazard class is a program classification this project does not
%   work in and the joint model deliberately does not carry, so there is no
%   input from which to evaluate the tree. FSSep stays a value the analyst
%   supplies. See COMPLIANCE.md (TFSR 4).
%
%   Returned struct fields (same shape engine.preloadWatchdog and
%   engine.frictionCheck return, so engine.analyze appends all three
%   through the identical idiom):
%       FFSep      the fitting factor screened
%       Critical   logical: is the joint separation-critical
%       Name       "" when nothing to report, else
%                  "SeparationFittingFactorLow"
%       Severity   "" | "Warning"
%       Method     the citation
%       Detail     one line naming the value, the threshold and the
%                  section to review
%
%   Call graph:
%       Precedents (calls)      none.
%       Dependents (called by)  engine.analyze (Result.Warnings).
%       Tests                   tests/tDabjCase.m —
%                               separationCriticalWithLowFittingFactorWarns,
%                               separationCriticalAtOnePointOneFiveIsSilent,
%                               nonSeparationCriticalNeverWarnsOnFittingFactor.
%
%   Validation status/coverage: see COMPLIANCE.md (TFSR 4 / §4.2.2).

arguments
    joint   (1,1) model.Joint
    factors (1,1) model.Factors
end

FF_SEPARATION_CRITICAL = 1.15;   % NASA-STD-5020B §4.2.2 p19

method = "NASA-STD-5020B §4.2.2 (p19) — separation analysis of " + ...
    "separation-critical joints should include a fitting factor of at " + ...
    "least 1.15 as a multiplier of the required separation factor of safety";

critical = joint.PreloadSpec.SeparationCritical;
FFSep    = factors.FFSep;

name     = "";
severity = "";
detail   = "";

if critical && FFSep < FF_SEPARATION_CRITICAL
    name     = "SeparationFittingFactorLow";
    severity = "Warning";
    detail   = sprintf("This joint is marked separation-critical and the " + ...
        "separation fitting factor is FFSep = %.3g. NASA-STD-5020B " + ...
        "4.2.2 (p19) says separation analysis of separation-critical " + ...
        "joints should use at least 1.15. Review NASA-STD-5020B 4.2.2: " + ...
        "1.0 may be adequate where the joint's functionality is verified " + ...
        "by test to limit load or greater, or where its load paths and " + ...
        "stresses come from detailed FEA correlated with tests of " + ...
        "similar systems. The factor has NOT been changed.", FFSep);
end

r = struct( ...
    "FFSep",    FFSep, ...
    "Critical", critical, ...
    "Name",     name, ...
    "Severity", severity, ...
    "Method",   method, ...
    "Detail",   string(detail));
end
