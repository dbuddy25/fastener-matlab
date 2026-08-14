function r = frictionCheck(joint)
%FRICTIONCHECK  Is the slip friction coefficient one NASA-STD-5020B allows?
%   r = engine.frictionCheck(joint) screens joint.FrictionCoefficient
%   against NASA-STD-5020B §4.4.6b [TFSR 14], which is a SHALL, not
%   guidance:
%
%     "Unless otherwise substantiated by test, the coefficient of friction
%      for joint-slip analysis shall be no greater than:
%        (1) 0.20 for uncoated, non-lubricated metal surfaces that are
%            cleaned by a qualified process and visibly clean at and after
%            assembly.
%        (2) 0.10 for all other surfaces, including nonmetallic (coated or
%            uncoated) surfaces and metallic surfaces that are coated with
%            any substance, including lubricant, paint, and conversion
%            coating."
%
%   WHY THIS IS A WARNING AND NOT A HARD LIMIT. TFSR 14's ceiling is
%   conditional — "unless otherwise substantiated by test" — and 5020B
%   explicitly contemplates higher values with "program- or
%   project-approved testing in a relevant environment". A tool that
%   refused mu > 0.20 would refuse a legitimate, substantiated input, and
%   the analyst is the one holding the test report. So the tool says what
%   the standard requires and lets the analyst answer for it. That is the
%   same stance engine.preloadWatchdog takes.
%
%   WHY IT IS NOT SILENT EITHER. The slip margin scales DIRECTLY with mu:
%   a joint entered at 0.35 reports a margin 75% higher than the same
%   joint at 0.20, and nothing anywhere else in the tool would mention
%   that the number rests on a coefficient the standard does not permit
%   without test data. Every other TFSR the engine can see, it reports on.
%
%   TWO TIERS, AND THE TOOL CANNOT TELL THEM APART. Which limit applies
%   depends on surface condition — coating, lubricant, cleanliness at AND
%   AFTER assembly — none of which the joint model carries, and none of
%   which is inferable from a material name (the same alloy is 0.20 bare
%   and 0.10 anodized). So:
%       mu > 0.20   EXCEEDS BOTH TIERS -> Warning, unconditionally wrong
%                   without test substantiation, whatever the surface.
%       0.10 < mu   permitted ONLY on the tier-(1) surface -> Warning
%        <= 0.20    naming the condition, so the analyst confirms it
%                   rather than inheriting it from a default.
%       mu <= 0.10  permitted on any surface -> nothing to say.
%   The middle tier is deliberately NOT silent: 0.20 is the value someone
%   reaches for as "the 5020B number", and it is the number that is wrong
%   on any coated, painted, lubricated or nonmetallic faying surface —
%   which is most flight hardware.
%
%   ONLY WHEN SLIP IS ACTUALLY EVALUATED. mu feeds nothing but
%   engine.marginSlip, so a joint with SlipMode.Ignored (or mu = 0, which
%   is the same "not evaluated" outcome) has no friction claim to answer
%   for, and a warning there would be noise about a number in an unused
%   field.
%
%   RELATED REQUIREMENT NOT CHECKED HERE: §4.4.6a [TFSR 13] permits
%   friction at limit or yield load only, never ultimate. The engine
%   satisfies that structurally rather than by a check — slip is its own
%   Margins row and feeds no ultimate allowable; engine.marginShearUlt and
%   engine.marginBearing take the applied shear directly with no friction
%   credit. There is no configuration in which a user can route friction
%   into an ultimate margin, so there is nothing to warn about.
%
%   Returned struct fields (same shape engine.preloadWatchdog returns, so
%   engine.analyze appends both through the identical idiom):
%       Mu         the coefficient screened (NaN when not evaluated)
%       Evaluated  logical: was the slip check live at all
%       Name       "" when nothing to report, else "FrictionAboveTFSR14"
%                  or "FrictionRequiresBareMetal"
%       Severity   "" | "Warning"
%       Method     the citation
%       Detail     one line naming the value, the limit and the condition
%
%   Call graph:
%       Precedents (calls)      none.
%       Dependents (called by)  engine.analyze (Result.Warnings).
%       Tests                   tests/tDabjCase.m — muAboveTheCeilingWarns,
%                               muInTheBareMetalBandNamesTheCondition,
%                               muAtOrBelowPointOneIsSilent,
%                               ignoredSlipNeverWarnsAboutFriction.
%
%   Validation status/coverage: see COMPLIANCE.md (TFSR 14).

arguments
    joint (1,1) model.Joint
end

MU_ANY_SURFACE  = 0.10;   % NASA-STD-5020B §4.4.6b(2) — all other surfaces
MU_BARE_METAL   = 0.20;   % NASA-STD-5020B §4.4.6b(1) — uncoated, non-lubricated, cleaned metal

method = "NASA-STD-5020B §4.4.6b [TFSR 14] — mu <= 0.20 (uncoated, " + ...
    "non-lubricated metal, cleaned by a qualified process and visibly " + ...
    "clean at and after assembly) or mu <= 0.10 (all other surfaces), " + ...
    "unless substantiated by test";

mu        = joint.FrictionCoefficient;
evaluated = joint.SlipMode ~= model.SlipMode.Ignored && mu > 0;

name     = "";
severity = "";
detail   = "";

if ~evaluated
    mu = NaN;
elseif mu > MU_BARE_METAL
    name     = "FrictionAboveTFSR14";
    severity = "Warning";
    % NOTE the "+" concatenation. ["a" "b"] builds a string ARRAY, not a
    % joined string, and sprintf then sees a 5-element format and throws
    % MATLAB:badformat_mx. The method string above uses "+" for the same
    % reason.
    detail   = sprintf("Slip friction coefficient mu = %.3g exceeds the " + ...
        "0.20 maximum NASA-STD-5020B 4.4.6b [TFSR 14] permits for ANY " + ...
        "surface without test substantiation. The slip margin scales " + ...
        "directly with mu. Substantiate by program- or project-approved " + ...
        "test in a relevant environment, or reduce mu.", mu);
elseif mu > MU_ANY_SURFACE
    name     = "FrictionRequiresBareMetal";
    severity = "Warning";
    detail   = sprintf("Slip friction coefficient mu = %.3g is permitted " + ...
        "by NASA-STD-5020B 4.4.6b [TFSR 14] ONLY for uncoated, " + ...
        "non-lubricated metal surfaces cleaned by a qualified process and " + ...
        "visibly clean at and after assembly. Any coating, paint, " + ...
        "conversion coating, lubricant or nonmetallic faying surface caps " + ...
        "mu at 0.10 without test substantiation.", mu);
end

r = struct( ...
    "Mu",        mu, ...
    "Evaluated", evaluated, ...
    "Name",      name, ...
    "Severity",  severity, ...
    "Method",    method, ...
    "Detail",    string(detail));
end
