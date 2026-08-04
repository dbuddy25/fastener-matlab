function r = preloadWatchdog(joint, preload)
%PRELOADWATCHDOG  Preload-vs-allowable watchdog QUERY (pure, never throws).
%   r = engine.preloadWatchdog(joint, preload) compares the joint's maximum
%   in-service preload (preload.PpMax, from engine.preload —
%   NASA-STD-5020B Eq. 1: PpMax = PpiMax + P_thermal_max) against the
%   BOLT's own tensile yield and ultimate allowables, resolved by the
%   shared private helper boltTensileAllowable (rated-or-derived — the
%   SAME resolution engine.marginTensionYield / engine.systemTensileAllowable
%   / engine.marginInteraction use, so this watchdog can never disagree
%   with those margins about which basis was used or what number
%   resulted). All loads in lbf (see UNITS.md).
%
%   It is a QUERY, not a margin check — like engine.boltLengthCheck, it is
%   NaN-tolerant and NEVER THROWS. preload is the struct ALREADY PRODUCED
%   by engine.preload(joint) (this function does not recompute it): a
%   caller that already has a valid preload struct in hand (e.g.
%   engine.analyze, which computes one anyway) gets a guaranteed
%   non-throwing watchdog call, and this function never inherits
%   engine.preload/engine.stiffness's own error paths for threaded-in or
%   missing-frustum-geometry configs.
%
%   BANDS (worst wins; AT MOST ONE warning emitted):
%       PpMax > ultimate allowable       -> "PreloadExceedsUltimate", Critical
%       else PpMax > yield allowable     -> "PreloadExceedsYield",    Critical
%       else PpMax > 0.85 * yield allow. -> "PreloadNearYield",       Warning
%       otherwise                        -> no warning (Name = "")
%   A band is skipped (never a fabricated warning) when its allowable was
%   not assessed (boltTensileAllowable's Ult/Yld.Assessed = false) or PpMax
%   is NaN — same "not proven inadequate" philosophy as boltLengthCheck.
%
%   PROVENANCE — read this before citing anything from this function:
%   PpMax ITSELF is NASA-STD-5020B Eq. 1 and IS properly citable (see
%   above). THE 85%/100% UTILIZATION BANDS HAVE NO 5020B BASIS.
%   NASA-STD-5020B §4.4.5 / TFSR 12 govern INCLUDING preload in the total
%   tensile load carried into the tension checks (i.e. that PpMax must be
%   added there) — NOT a standalone preload-utilization percentage; 5020B
%   prints no such threshold. The 85% (Warning) and 100% (Critical) bands
%   here are therefore a DERIVED CONVENTION, in the same voice as
%   engine.boltLengthCheck's Le = 1.5·D default — no equation number is
%   cited for them, by design, because none exists to cite.
%
%   Returned struct fields:
%       PpMax             lbf — echoed from the preload struct (may be NaN)
%       UltimateAllowable struct — bt.Ult from boltTensileAllowable
%                         (Value/Basis/Assessed/Note/Reason); reports which
%                         basis (rated vs derived) was used for the ultimate side
%       YieldAllowable    struct — bt.Yld from boltTensileAllowable, same shape,
%                         for the yield side
%       Evaluated         logical — true iff at least one band was actually
%                         checked (PpMax known AND at least one of
%                         Ult/Yld.Assessed); false means "not evaluated",
%                         never a silent pass
%       Name              "" | "PreloadExceedsUltimate" |
%                         "PreloadExceedsYield" | "PreloadNearYield" —
%                         "" means no warning (clean OR not evaluated;
%                         see Evaluated to tell those apart)
%       Severity          "" | "Warning" | "Critical"
%       Method            citation string: PpMax's Eq. 1 provenance, plus
%                         an explicit flag that the utilization thresholds
%                         are a derived convention with no equation number
%       Detail            human-readable explanation with the arithmetic
%                         (or the not-evaluated reason)
%
%   Pinned in tests/tPreloadWatchdog.m: clean / near-yield / exceeds-yield
%   / exceeds-ultimate (worst-wins ordering) on a synthetic rated-load
%   fixture, not-evaluated on a bare joint (no rating, no At/Ftu, and on a
%   NaN PpMax), and the DABJ Section 9 fixture — PpMax ~11,069 lbf vs its
%   rated yield 11,400 lbf is 97% of yield, ABOVE the 85% band, so §9 is
%   EXPECTED to report one PreloadNearYield warning (not a clean joint).
%
%   Call graph:
%       Precedents (calls)      boltTensileAllowable (private helper,
%                               +engine/private/boltTensileAllowable.m).
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tPreloadWatchdog.m — nearYieldWarning,
%                               exceedsYieldCritical,
%                               exceedsUltimateWinsOverYield (worst-wins),
%                               notEvaluatedOnBareJoint,
%                               dabjSection9TripsNearYieldByDesign.
%
%   Validation status/coverage: no VALIDATION.md row — this is a QUERY/
%   warning, not one of its Margin-checks/Preload/Stiffness rows; the
%   fixture coverage is the pinned-tests paragraph above, kept in full
%   rather than pointed at a row that doesn't exist.

arguments
    joint   (1,1) model.Joint
    preload (1,1) struct
end

PpMax = preload.PpMax;
bt    = boltTensileAllowable(joint);
u     = bt.Ult;
y     = bt.Yld;

name      = "";
severity  = "";
evaluated = false;

% ---- Ultimate band (checked first -- worst wins) ---------------------------
if ~isnan(PpMax) && u.Assessed
    evaluated = true;
    if PpMax > u.Value
        name     = "PreloadExceedsUltimate";
        severity = "Critical";
    end
end

% ---- Yield bands (only when Ultimate did not already win) -----------------
if strlength(name) == 0 && ~isnan(PpMax) && y.Assessed
    evaluated = true;
    if PpMax > y.Value
        name     = "PreloadExceedsYield";
        severity = "Critical";
    elseif PpMax > 0.85 * y.Value
        name     = "PreloadNearYield";
        severity = "Warning";
    end
end

method = "NASA-STD-5020B Eq. 1 (PpMax = PpiMax + P_thermal_max) compared " + ...
    "against the bolt's own tensile allowables (boltTensileAllowable, " + ...
    "rated-or-derived) -- the 85% (Warning) / 100% (Critical) UTILIZATION " + ...
    "THRESHOLDS themselves are a DERIVED CONVENTION with NO 5020B equation " + ...
    "number: 5020B Sec 4.4.5/TFSR 12 govern including preload in the " + ...
    "tension checks, not a standalone utilization percentage.";

% ---- Detail ------------------------------------------------------------
if strlength(name) > 0
    if name == "PreloadExceedsUltimate"
        pct = 100 * PpMax / u.Value;
        detail = sprintf( ...
            ['PpMax %.1f lbf EXCEEDS the bolt ultimate tensile allowable ' ...
             '%.1f lbf (%s basis) -- %.1f%% of ultimate. Bolt may fracture. ' ...
             '(Ultimate allowable: %s)'], ...
            PpMax, u.Value, u.Basis, pct, u.Note);
    elseif name == "PreloadExceedsYield"
        pct = 100 * PpMax / y.Value;
        detail = sprintf( ...
            ['PpMax %.1f lbf EXCEEDS the bolt yield tensile allowable ' ...
             '%.1f lbf (%s basis) -- %.1f%% of yield. Bolt may permanently ' ...
             'deform. (Yield allowable: %s)'], ...
            PpMax, y.Value, y.Basis, pct, y.Note);
    else % PreloadNearYield
        pct = 100 * PpMax / y.Value;
        detail = sprintf( ...
            ['PpMax %.1f lbf is %.1f%% of the bolt yield tensile allowable ' ...
             '%.1f lbf (%s basis) -- above the 85%% derived-convention ' ...
             'threshold (no 5020B basis; see Method). (Yield allowable: %s)'], ...
            PpMax, pct, y.Value, y.Basis, y.Note);
    end
elseif evaluated
    % Clean: report against whichever allowable(s) were actually assessed.
    if y.Assessed
        pct = 100 * PpMax / y.Value;
        detail = sprintf( ...
            ['PpMax %.1f lbf is %.1f%% of the bolt yield tensile allowable ' ...
             '%.1f lbf (%s basis) -- below the 85%% derived-convention ' ...
             'threshold.'], ...
            PpMax, pct, y.Value, y.Basis);
    else
        pct = 100 * PpMax / u.Value;
        detail = sprintf( ...
            ['Yield allowable not assessed (%s); PpMax %.1f lbf is %.1f%% ' ...
             'of the bolt ultimate tensile allowable %.1f lbf (%s basis).'], ...
            y.Reason, PpMax, pct, u.Value, u.Basis);
    end
else
    parts = strings(1, 0);
    if isnan(PpMax)
        parts(end+1) = "PpMax (engine.preload result carries no in-service preload)"; %#ok<AGROW>
    end
    if ~u.Assessed && ~y.Assessed
        parts(end+1) = "bolt tensile allowables (ultimate: " + u.Reason + ...
            "; yield: " + y.Reason + ")"; %#ok<AGROW>
    end
    detail = "Preload watchdog not evaluated -- missing: " + ...
        strjoin(parts, "; ") + ".";
end

r = struct( ...
    "PpMax",             PpMax, ...
    "UltimateAllowable", u, ...
    "YieldAllowable",    y, ...
    "Evaluated",         evaluated, ...
    "Name",              name, ...
    "Severity",          severity, ...
    "Method",            method, ...
    "Detail",            string(detail));
end
