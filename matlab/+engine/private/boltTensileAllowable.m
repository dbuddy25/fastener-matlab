function a = boltTensileAllowable(joint)
%BOLTTENSILEALLOWABLE  Bolt ultimate + yield tensile allowables, rated-or-derived.
%   a = boltTensileAllowable(joint) resolves the BOLT's (not the
%   internal-thread member's — see memberTensileUltAllowable) ultimate and
%   yield tensile allowables, consulting the joint's spec rating first and
%   falling back to a derived value only when the rating is unset. It is
%   the SINGLE implementation of that precedence, shared by
%   engine.systemTensileAllowable (the bolt-tension mode of the
%   NASA-STD-5020B §4.4.1 fastening-system minimum),
%   engine.marginTensionUlt (via the Fig. 8 gate's system allowable),
%   engine.marginTensionYield, and engine.marginInteraction (which
%   deliberately uses the BOLT's own allowable, not the system minimum —
%   see that function's header) — one resolution means none of those sites
%   can disagree about which basis was used or what number resulted.
%
%   PRECEDENCE (spec rating wins; the derived value is used only when the
%   rating is unset):
%
%   Ultimate:
%     "rated"   — joint.BoltRatedUltimateLoad, when set (not NaN).
%     "derived" — Ptu_allow = At * Ftu, where At = joint.Bolt.TensileStressArea
%       and Ftu = joint.BoltMaterial.Ftu. THIS IS A DERIVED CONVENTION, NOT
%       A NUMBERED NASA-STD-5020B EQUATION: 5020B prints no ultimate-
%       allowable formula. NASA-STD-5020B §4.4.2 says only that Ptu-allow
%       "will have considerations for the fastener geometric features and
%       will typically be the capability of the threaded section of the
%       fastener" — the same paragraph that introduces Eq. 15/16 and flags
%       them as "not applicable to all load conditions and are provided as
%       examples only." At*Ftu is this codebase's derived reading of that
%       §4.4.2 sentence (the threaded section's capability = stress area x
%       ultimate strength), in the same voice as the other derived
%       conventions in engine.boltLengthCheck / engine.marginNutStrength —
%       not a citation to an equation 5020B does not give.
%
%   Yield — NASA-STD-5020B Eq. 18:
%       Pty_allow = (Fty / Ftu) * Ptu_allow
%     introduced by: "The allowable yield tensile load can be estimated
%     using the equation below when a value is not explicitly defined in
%     the corresponding fastener specification or relevant test data is
%     unavailable" — exactly this situation, so the yield fallback IS
%     standard-sanctioned (unlike the ultimate fallback above).
%     "rated"   — joint.BoltRatedYieldLoad, when set (not NaN).
%     "derived" — Eq. 18 applied to the ULTIMATE ALLOWABLE ACTUALLY IN USE
%       (the rated ultimate when set, else the derived At*Ftu above) — NOT
%       At*Fty directly. Eq. 18 needs Fty AND Ftu (the ratio) regardless of
%       which ultimate basis is in play, so the yield derived path needs
%       Ftu even when the ultimate itself came from the spec rating. The
%       two forms coincide only when the ultimate in use is itself At*Ftu
%       (Eq. 18 then reduces to (Fty/Ftu)*(At*Ftu) = At*Fty).
%
%   NO SILENT FALLBACK: when even the derived path cannot be formed —
%   missing At, Ftu, or (for yield) Fty, or the ultimate itself is
%   unassessable — the corresponding side reports Assessed = false with a
%   Reason naming the specific missing input. Never throws.
%
%   Returned struct fields:
%     Ult   struct — the bolt ultimate tensile allowable:
%             Value     lbf (NaN unless Assessed)
%             Basis     "rated" | "derived" | "none"
%             Assessed  logical
%             Note      string: which basis, with the arithmetic (Assessed only)
%             Reason    string: why not assessed ("" when Assessed)
%     Yld   struct — the bolt yield tensile allowable, same shape:
%             Value, Basis, Assessed, Note, Reason
%
%   Call graph:
%       Precedents (calls)      (leaf — model.Joint fields only, no
%                               engine.* / private-helper dependencies).
%       Dependents (called by)  engine.marginTensionYield, engine.marginInteraction,
%                               engine.preloadWatchdog, engine.systemTensileAllowable.
%       Tests                   tests/tBoltAllowable.m —
%                               ratedOnlyUsesSpecRatingEverywhere (rated basis,
%                               both Ult/Yld); derivedOnlyUsesAtFtuAndEq18
%                               (At*Ftu + Eq. 18 fallback); mixedBasisYieldUsesRatedUltimateNotAtFty
%                               (rated ultimate + derived yield — Eq. 18 must
%                               use the RATED ultimate, not At*Fty);
%                               unavailableAtNaNIsNotEvaluatedNotThrown,
%                               unavailableFtuNaNIsNotEvaluatedNotThrown,
%                               unavailableFtyNaNLeavesYieldNotEvaluatedButUltimateFine
%                               (missing-input NotEvaluated paths, no throw).
%
%   Validation status/coverage: no dedicated VALIDATION.md row — exercised as
%   an input to Margin-checks rows 1/1r/2/7/8/9/12 (each row's Ptu_allow/
%   Pty_allow figure is this function's output on that fixture).

arguments
    joint (1,1) model.Joint
end

At  = joint.Bolt.TensileStressArea;
Ftu = joint.BoltMaterial.Ftu;
Fty = joint.BoltMaterial.Fty;

% =========================================================================
% Ultimate
% =========================================================================
u = struct("Value", NaN, "Basis", "none", "Assessed", false, ...
    "Note", "", "Reason", "");

ratedUlt = joint.BoltRatedUltimateLoad;
if ~isnan(ratedUlt)
    u.Value    = ratedUlt;
    u.Basis    = "rated";
    u.Assessed = true;
    u.Note     = string(sprintf("spec-rated bolt Ptu-allow %.0f lbf", ratedUlt));
else
    missing = strings(1, 0);
    if isnan(At),  missing(end+1) = "Bolt.TensileStressArea (At)"; end %#ok<AGROW>
    if isnan(Ftu), missing(end+1) = "BoltMaterial.Ftu";            end %#ok<AGROW>
    if isempty(missing)
        % Derived convention (NOT a numbered 5020B equation — see header):
        % Ptu_allow = At * Ftu
        u.Value    = At * Ftu;
        u.Basis    = "derived";
        u.Assessed = true;
        u.Note     = string(sprintf( ...
            ['derived Ptu_allow = At*Ftu = %.4f*%.0f = %.0f lbf ' ...
             '(BoltRatedUltimateLoad not set; NASA-STD-5020B gives no ultimate-' ...
             'allowable equation -- At*Ftu is a derived convention per 5020B ' ...
             '§4.4.2''s reference to the capability of the threaded section, ' ...
             'not a numbered equation)'], ...
            At, Ftu, u.Value));
    else
        u.Reason = "BoltRatedUltimateLoad not set and the derived Ptu_allow = At*Ftu " + ...
            "fallback needs " + join(missing, " and ") + " (NaN)";
    end
end

% =========================================================================
% Yield — NASA-STD-5020B Eq. 18
% =========================================================================
y = struct("Value", NaN, "Basis", "none", "Assessed", false, ...
    "Note", "", "Reason", "");

ratedYld = joint.BoltRatedYieldLoad;
if ~isnan(ratedYld)
    y.Value    = ratedYld;
    y.Basis    = "rated";
    y.Assessed = true;
    y.Note     = string(sprintf("spec-rated bolt Pty-allow %.0f lbf", ratedYld));
else
    if ~u.Assessed
        y.Reason = "BoltRatedYieldLoad not set and NASA-STD-5020B Eq. 18 needs " + ...
            "Ptu_allow, which is unavailable: " + u.Reason;
    elseif isnan(Fty)
        y.Reason = "BoltRatedYieldLoad not set and the NASA-STD-5020B Eq. 18 fallback " + ...
            "needs BoltMaterial.Fty (NaN)";
    elseif isnan(Ftu)
        % Only reachable when Ult came from the RATED path (a derived Ult
        % already required Ftu) — Eq. 18 still needs the Fty/Ftu ratio.
        y.Reason = "BoltRatedYieldLoad not set and the NASA-STD-5020B Eq. 18 fallback " + ...
            "needs BoltMaterial.Ftu for the Fty/Ftu ratio (NaN)";
    else
        % NASA-STD-5020B Eq. 18 — Pty_allow = (Fty/Ftu) * Ptu_allow, applied
        % to the ultimate ACTUALLY IN USE (rated or derived) per u.Basis.
        y.Value    = (Fty / Ftu) * u.Value;
        y.Basis    = "derived";
        y.Assessed = true;
        y.Note     = string(sprintf( ...
            ['NASA-STD-5020B Eq. 18 -- Pty_allow = (Fty/Ftu)*Ptu_allow = ' ...
             '(%.0f/%.0f)*%.0f = %.0f lbf, using the %s Ptu_allow'], ...
            Fty, Ftu, u.Value, y.Value, u.Basis));
    end
end

a = struct("Ult", u, "Yld", y);
end
