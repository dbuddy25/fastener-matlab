function r = boltLengthCheck(joint)
%BOLTLENGTHCHECK  Bolt-length adequacy query (pure, never throws).
%   r = engine.boltLengthCheck(joint) compares the supplied overall bolt
%   length (joint.Bolt.Length) against the minimum length the joint
%   geometry requires. It is a QUERY, not a margin check: it writes no
%   Margins row and never affects WorstMargin/GoverningCheck. engine.analyze
%   DOES call it on every run, though -- a Shortfall > 0 result is mapped
%   to a "BoltLengthShort" row on Result.Warnings (see engine.analyze's
%   WARNINGS note), reusing this function's own Method/Detail verbatim.
%   The GUI also calls it directly on every relevant edit to drive the live
%   bolt-length label (GUI_PORT_SPEC.md Section 3), which is why it must
%   tolerate a half-filled joint: ANY missing (NaN) input degrades to NaN
%   outputs and an explanatory Detail — this function never errors on
%   inputs. Lengths in inches (see UNITS.md).
%
%   Grip (clamped length) counts the washers:
%       grip = sum(FlangeStack.Thickness) + head washer + nut washer
%   (an EMPTY flange stack means the grip is not yet defined -> NaN).
%
%   Required minimum bolt length, by threaded-member configuration. In all
%   three, Le itself is resolved by the shared private helper
%   resolveEngagementLength: ThreadedMember.EngagementRatio x
%   Bolt.NominalDiameter when the ratio is set (OVERRIDING EngagementLength
%   — Detail says so), else the unchanged ThreadedMember.EngagementLength,
%   else (Insert/TappedHole only, below) this function's own 1.5·D
%   fallback.
%     - Nut (through-bolt):
%         NASA-STD-5020B §4.7.4 — Lmin = grip + nut height + 2·pitch
%       with nut height = Le (see above) and pitch = Bolt.Pitch (the same
%       relation engine.stiffness uses to estimate the bolt length when one
%       is not supplied).
%     - Insert:
%         NASA-STD-5020B §4.7.4 names inserts explicitly, in the SAME
%         sentence as nut/nut plate: "the length of each fastener used
%         with a nut, nut plate, or insert should be selected to extend a
%         distance of at least twice the thread pitch, p, past the
%         outboard end of the nut, nut plate, or insert." So the 2·pitch
%         protrusion term applies to Insert exactly as it does to Nut —
%         Lmin = grip + Le + 2·pitch. 5020B does NOT give a formula for
%         Le itself (the insert's own engagement/thread depth), so that
%         term stays this tool's own DERIVED CONVENTION, not a cited
%         standard relation: Le per resolveEngagementLength above when
%         either EngagementRatio or EngagementLength is set,
%         else Le = 1.5·D (Bolt.NominalDiameter) when neither is.
%     - Tapped hole:
%         §4.7.4's 2·pitch sentence stops at "nut, nut plate, or insert" —
%         a directly-tapped hole is not in that list. The very next
%         paragraph covers it instead with a non-formulaic, strength-based
%         criterion: thread engagement "should be selected to ensure the
%         minimum number of engaged complete threads such that the
%         fastener would fail in tension before threads would strip" —
%         i.e. engine.marginTappedParentThread's job, not a length
%         relation. So TappedHole correctly keeps allowance = 0 here;
%         RequiredLength for TappedHole is grip + Le only, deliberately
%         NOT validated against any 5020B bolt-length formula.
%
%   Returned struct fields:
%       GripLength      clamped stack + washers, in (NaN if stack empty)
%       Engagement      nut height / thread engagement Le used, in
%       ThreadAllowance 2·pitch thread protrusion (Nut and Insert per
%                       §4.7.4; 0 for TappedHole -- see header), in
%       EngagementBasis "nut height" | "engagement ratio" |
%                       "specified engagement" | "1.5D default" | "unknown"
%                       — where Engagement came from ("engagement ratio" —
%                       EngagementRatio x NominalDiameter, resolver-governed
%                       — applies to all three configurations; "nut height"
%                       is Nut's EngagementLength-only label). Lets the GUI
%                       label the line without arithmetic.
%       RequiredLength  minimum bolt length, in (NaN when underdefined)
%       SuppliedLength  joint.Bolt.Length, in (NaN = not supplied)
%       IsAdequate      logical. FALSE only when the check affirmatively
%                       shows a shortfall (supplied AND required both known
%                       AND supplied < required). TRUE otherwise — including
%                       when the length is unknown: "not proven inadequate".
%                       Callers must key alarm styling off Shortfall > 0
%                       (or Evaluated), never off IsAdequate alone.
%       Evaluated       logical: both SuppliedLength and RequiredLength known
%       Shortfall       RequiredLength - SuppliedLength when short (> 0);
%                       0 when evaluated and adequate; NaN when not evaluated
%       Method          citation string for the RequiredLength relation
%       Detail          human-readable explanation
%
%   Call graph:
%       Precedents (calls)      resolveEngagementLength (private) — the ONLY
%                               engine dependency; otherwise a leaf, reading
%                               model.Joint / model.Bolt / model.ThreadedMember
%                               getters directly. Never calls, and is never
%                               called by, engine.stiffness — that function
%                               independently estimates a bolt length
%                               internally (same §4.7.4 relation, Nut config
%                               only) when one is not supplied; the two
%                               never call each other, so a bug in either
%                               function's OWN Lmin arithmetic would not
%                               surface in the other — they now share only
%                               the Le RESOLUTION step (resolveEngagementLength),
%                               not the surrounding formula.
%       Dependents (called by)  engine.analyze (every run — a Shortfall > 0
%                               result becomes Result.Warnings'
%                               "BoltLengthShort" row, see that function's
%                               WARNINGS note); the GUI, directly, on every
%                               relevant edit (GUI_PORT_SPEC.md Section 3).
%       Tests                   tests/tBoltLength.m nutConfigAdequateAndShort,
%                               threadedInConfig (Insert 2·pitch + TappedHole
%                               no-allowance), nanInputsNeverThrow.
%
%   Validation status/coverage: no dedicated VALIDATION.md row — hand-
%   derived pins on the DABJ Example 8-b geometry (tests/tBoltLength.m).
%   The L1 bolt-length ESTIMATE this function's Nut-config formula shares
%   with engine.stiffness's own internal fallback is pinned separately, in
%   VALIDATION.md's "L1 fallback" row.

arguments
    joint (1,1) model.Joint
end

% ---- Grip: clamped stack + washers (washers count toward grip) -----------
if isempty(joint.FlangeStack)
    grip = NaN;                        % no clamped stack yet -> grip unknown
else
    grip = sum([joint.FlangeStack.Thickness]) + ...
        joint.HeadWasher.Thickness + joint.NutWasher.Thickness;
end

D = joint.Bolt.NominalDiameter;        % major dia, in

% Le: ratio-or-absolute, single resolution (resolveEngagementLength) —
% EngagementRatio, when set, OVERRIDES EngagementLength (Note says which).
% Applies identically to all three configurations below; the 1.5·D
% derived-convention default (Insert/TappedHole only) is a SEPARATE, lower-
% precedence fallback that only fires when the resolver itself returns NaN
% (neither EngagementRatio nor EngagementLength set).
rle = resolveEngagementLength(joint);

% ---- Required length, by configuration -----------------------------------
if joint.ThreadedMember.Type == model.ThreadedMemberType.Nut
    % NASA-STD-5020B §4.7.4 — Lmin = grip + nut height + 2·pitch
    engagement = rle.Le;                                  % nut height (or ratio x D), in
    allowance  = 2 * joint.Bolt.Pitch;                    % 2·pitch protrusion, in
    if rle.Basis == "ratio"
        basis = "engagement ratio";
    elseif rle.Basis == "length"
        basis = "nut height";
    else
        basis = "unknown";
    end
    required = grip + engagement + allowance;   % NaN-propagating by design
    method   = "NASA-STD-5020B §4.7.4 — Lmin = grip + nut height + 2·pitch" + ...
        " (nut height = EngagementRatio x NominalDiameter when the ratio " + ...
        "is set, else EngagementLength)";
elseif joint.ThreadedMember.Type == model.ThreadedMemberType.Insert
    % NASA-STD-5020B §4.7.4 names inserts alongside nut/nut plate for the
    % SAME 2·pitch protrusion requirement (see header) — Lmin = grip + Le
    % + 2·pitch. Le itself is not given a formula by 5020B, so it stays
    % the pre-existing derived convention: EngagementRatio x
    % NominalDiameter, else supplied EngagementLength, else Le = 1.5·D
    % (resolveEngagementLength handles the first two; the 1.5·D default
    % below is this function's own separate fallback).
    engagement = rle.Le;                                  % insert Le, in
    allowance  = 2 * joint.Bolt.Pitch;                    % 2·pitch protrusion, in
    if rle.Basis == "ratio"
        basis = "engagement ratio";
    elseif rle.Basis == "length"
        basis = "specified engagement";
    elseif ~isnan(D)
        engagement = 1.5 * D;          % derived convention: Le = 1.5·D
        basis = "1.5D default";
    else
        basis = "unknown";
    end
    required = grip + engagement + allowance;   % NaN-propagating by design
    method   = "NASA-STD-5020B §4.7.4 — Lmin = grip + Le + 2·pitch " + ...
        "(Le = EngagementRatio x NominalDiameter, else engagement length, " + ...
        "or 1.5·D derived-convention default when unspecified)";
else
    % Tapped hole — §4.7.4's 2·pitch sentence names only nut/nut plate/
    % insert; a directly-tapped hole is covered instead by the standard's
    % non-formulaic thread-stripping criterion (see header), so NO
    % protrusion allowance applies here. Lmin = grip + Le, full thread
    % engagement into the parent material, with the derived-convention
    % Le = 1.5·D default when no engagement (ratio or length) is supplied.
    % Not a cited standard equation.
    engagement = rle.Le;                                  % tapped-hole Le, in
    allowance  = 0;                                       % no protrusion term (see header)
    if rle.Basis == "ratio"
        basis = "engagement ratio";
    elseif rle.Basis == "length"
        basis = "specified engagement";
    elseif ~isnan(D)
        engagement = 1.5 * D;          % derived convention: Le = 1.5·D
        basis = "1.5D default";
    else
        basis = "unknown";
    end
    required = grip + engagement;      % NaN-propagating by design
    method   = "Derived convention (5020B's §4.7.4 2·pitch rule does not " + ...
        "name tapped holes — see header) — Lmin = grip + Le (Le = " + ...
        "EngagementRatio x NominalDiameter, else engagement length, or " + ...
        "1.5·D when unspecified)";
end

supplied  = joint.Bolt.Length;         % overall bolt length, in (NaN = not supplied)
evaluated = ~isnan(supplied) && ~isnan(required);

% ---- Verdict --------------------------------------------------------------
% IsAdequate is false ONLY on a demonstrated shortfall; with any input
% unknown it stays true ("not proven inadequate") and Shortfall stays NaN so
% callers can distinguish "OK" from "not evaluated".
if evaluated
    shortfall  = max(required - supplied, 0);
    isAdequate = shortfall <= 0;
    if isAdequate
        detail = sprintf( ...
            "Supplied bolt length %.4f in meets the required minimum %.4f in (grip %.4f in).", ...
            supplied, required, grip);
    else
        detail = sprintf( ...
            "Supplied bolt length %.4f in is SHORT of the required minimum %.4f in by %.4f in (grip %.4f in).", ...
            supplied, required, shortfall, grip);
    end
    if rle.Basis == "ratio"
        % Ratio governs the engagement term — make that visible here too,
        % not just via EngagementBasis, so a reviewer reading Detail alone
        % (e.g. the "BoltLengthShort" warning row, which reuses this
        % string verbatim) can never be misled about which number was used.
        detail = detail + " " + rle.Note + ".";
    end
else
    shortfall  = NaN;
    isAdequate = true;                 % not proven inadequate (see header)
    parts = strings(1, 0);
    if isnan(grip)
        parts(end+1) = "grip (flange stack is empty)"; %#ok<AGROW>
    end
    if isnan(required) && ~isnan(grip)
        switch joint.ThreadedMember.Type
            case model.ThreadedMemberType.Nut
                if isnan(rle.Le)
                    parts(end+1) = "nut height (ThreadedMember.EngagementLength or EngagementRatio, " + ...
                        "the latter also needing Bolt.NominalDiameter)"; %#ok<AGROW>
                end
                if isnan(joint.Bolt.Pitch)
                    parts(end+1) = "thread pitch (Bolt.ThreadsPerInch)"; %#ok<AGROW>
                end
            case model.ThreadedMemberType.Insert
                % Insert also carries the §4.7.4 2·pitch term (see header),
                % so a missing pitch can block RequiredLength here too --
                % unlike TappedHole, which has no pitch dependency.
                if isnan(rle.Le) && isnan(D)
                    parts(end+1) = "engagement length or ratio (and no nominal diameter for the 1.5·D default)"; %#ok<AGROW>
                end
                if isnan(joint.Bolt.Pitch)
                    parts(end+1) = "thread pitch (Bolt.ThreadsPerInch)"; %#ok<AGROW>
                end
            otherwise % TappedHole -- no allowance term, no pitch dependency
                parts(end+1) = "engagement length or ratio (and no nominal diameter for the 1.5·D default)"; %#ok<AGROW>
        end
    end
    if isnan(supplied)
        parts(end+1) = "supplied bolt length (Bolt.Length)"; %#ok<AGROW>
    end
    detail = "Bolt-length adequacy not evaluated — missing: " + ...
        strjoin(parts, "; ") + ".";
end

r = struct( ...
    "GripLength",      grip, ...
    "Engagement",      engagement, ...
    "ThreadAllowance", allowance, ...
    "EngagementBasis", basis, ...
    "RequiredLength",  required, ...
    "SuppliedLength",  supplied, ...
    "IsAdequate",      isAdequate, ...
    "Evaluated",       evaluated, ...
    "Shortfall",       shortfall, ...
    "Method",          method, ...
    "Detail",          detail);
end
