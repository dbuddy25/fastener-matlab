function g = separationBeforeRuptureGate(joint, preload)
%SEPARATIONBEFORERUPTUREGATE  NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) gate.
%   g = separationBeforeRuptureGate(joint, preload) is the SINGLE
%   implementation of the separation-before-rupture decision tree, shared
%   by engine.marginTensionUlt (which reports it as the Tension-Ultimate /
%   Separation-before-rupture rows) and engine.boltDesignLoad (which uses
%   it to choose the Phase 3.3 thread-check design-load form) — one
%   evaluation of the gate, so the tension row and the four thread rows
%   can never disagree about which branch applies.
%
%   ASSURED when ALL of (NASA-STD-5020B Fig. 8 / DABJ Fig. 9-9 — the figure
%   prints "Ec>Eb/3", "Pp-max<=0.75*Ptu-allow", "n<=0.9", and "e/D>=1.5";
%   the boundary is inclusive on all three of the latter, strict on the
%   first):
%     1. Ec > Eb/3 — the softest clamped-member modulus (min E over the
%        FlangeStack, conservative) exceeds one third of the bolt modulus
%        (figure prints a strict ">").
%     2. PpMax <= 0.75*Ptu_allow — max in-service preload is at or below
%        the low end of the intermediate band ([0.75, 0.85]*Ptu_allow,
%        above 0.75 conservatively treated as NOT assured; figure prints
%        "<=", inclusive).
%     3. LoadingPlaneFactor n <= 0.9 (figure prints "<=", inclusive).
%     4. Edge distance e/D >= 1.5 — NASA-STD-5020B Appendix A.5: "for any
%        practical design with Ec > Eb/3, e/D >= 1.5, and n <= 0.9, the
%        bolt load increases by no more than 25 percent of the applied
%        tensile load prior to separation" — e/D is a PRECONDITION on that
%        FE-study conclusion, not a separate 5020B design requirement.
%        e/D = min(FlangeLayer.EdgeDistance over joint.FlangeStack) /
%        joint.Bolt.NominalDiameter (figure prints ">=", inclusive):
%          - EVERY layer's EdgeDistance is NaN (unset) -> the condition is
%            ASSUMED satisfied (not verified) — Trace says "ASSUMED".
%          - AT LEAST ONE layer has EdgeDistance set -> tested against the
%            KNOWN layers' minimum. If that known minimum already fails
%            (< 1.5), the condition FAILS outright (a lower unknown layer
%            cannot un-fail it) — Trace says "VERIFIED failing". If the
%            known minimum passes but some layers remain unset, the result
%            is only PARTIALLY verified (an unrecorded layer could be the
%            tight one) — Trace says "ASSUMED" for the overall stack. Only
%            when EVERY layer has EdgeDistance set does a passing result
%            read "VERIFIED".
%        A reader must be able to tell a verified e/D from an assumed one
%        from Trace alone; that wording survives unchanged into
%        engine.marginTensionUlt's Decision and the Detail of every
%        consumer that forwards this gate's Trace.
%   Ptu_allow is the FASTENING SYSTEM's allowable (NASA-STD-5020B §4.4.1),
%   from engine.systemTensileAllowable.
%
%   NEVER THROWS. When the gate cannot be evaluated at all — an empty
%   Joint.FlangeStack (Ec needs a clamped-member modulus) or NO tensile
%   failure mode of the fastening system assessable at all (Ptu_allow
%   itself NaN — engine.systemTensileAllowable, which now falls back to a
%   derived bolt allowable via boltTensileAllowable when the spec rating is
%   unset, so this is rare) — Assessed is false and Assured is false; the
%   reason is in Trace. Callers must check Assessed before trusting
%   Assured, per the "no silent branch pick" rule (see engine.boltDesignLoad).
%
%   Returned struct fields:
%       Assessed        logical: true if the gate could be evaluated
%       Assured         logical: gate result (false when not Assessed)
%       PtuAllow        system allowable used, lbf (NaN unless Assessed)
%       SystemAllowable engine.systemTensileAllowable struct (empty struct
%                       only when FlangeStack is empty, before Ptu_allow
%                       could even be attempted; the real struct, with its
%                       per-mode trace, whenever it was computed — including
%                       the Ptu_allow-unassessable not-Assessed case)
%       Trace           string: condition-by-condition trace (the assured
%                       description, or the failing-condition list, or the
%                       not-assessed reason)
%
%   Call graph:
%       Precedents (calls)      engine.systemTensileAllowable.
%       Dependents (called by)  engine.marginTensionUlt, engine.boltDesignLoad,
%                               engine.marginBearingUnderHead.
%       Tests                   tests/tSystemAllowable.m — weakNutFlipsFig8Gate
%                               (system vs. bolt Ptu_allow flips Assured);
%                               tests/tStiffness.m — tensionRuptureBranch,
%                               boltYieldRuptureBranch (preload condition
%                               fails -> not Assured, ultimate + yield sides);
%                               edgeDistanceVerifiedAssuresGate,
%                               edgeDistanceVerifiedFailingBreaksGate,
%                               edgeDistanceUnknownIsAssumedNotVerified (the
%                               e/D condition itself: verified pass, verified
%                               fail, unknown-so-assumed);
%                               tests/tDabjCase.m — tensionUltMarginMatchesDABJ,
%                               dabjAnswerKeyUnchanged (DABJ §9, all conditions
%                               hold -> Assured) — all exercised indirectly
%                               through the calling margin functions; no test
%                               calls this private helper directly.
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 12).

arguments
    joint   (1,1) model.Joint
    preload (1,1) struct
end

if isempty(joint.FlangeStack)
    g = notAssessed("Joint.FlangeStack is empty (Ec needed for the member-stiffness gate condition)");
    return
end

% NASA-STD-5020B §4.4.1 — Ptu_allow = min over the fastening system's
% tensile failure modes (engine.systemTensileAllowable; shared so the gate
% and the tension row always agree on Ptu_allow). The bolt-tension mode
% now falls back to a derived allowable (boltTensileAllowable) when the
% spec rating is unset, so PtuAllow is NaN only if NO tensile mode of the
% system — bolt included — can be assessed at all.
sys = engine.systemTensileAllowable(joint);
PtuAllow = sys.PtuAllow;
if isnan(PtuAllow)
    g = notAssessed("Ptu_allow not assessable (NASA-STD-5020B §4.4.1): " + sys.Note, sys);
    return
end

Eb = joint.BoltMaterial.E;
flangeMats = [joint.FlangeStack.Material];
Ec = min([flangeMats.E]);                       % softest member (conservative)
n  = joint.LoadingPlaneFactor;

% NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) — Ec > Eb/3 (member-stiffness gate)
condStiffness = Ec > Eb/3;
% NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) — PpMax <= 0.75*Ptu_allow (preload
% gate; figure prints "<=", inclusive; [0.75, 0.85]*Ptu_allow band above it
% conservatively treated as rupture)
condPreload   = preload.PpMax <= 0.75 * PtuAllow;
% NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) — n <= 0.9 (loading-plane-factor gate)
condPlane     = n <= 0.9;

% NASA-STD-5020B Appendix A.5 — e/D >= 1.5 (edge-distance PRECONDITION on
% the Fig. 8 conclusion, not a design requirement in its own right). e/D is
% the minimum EdgeDistance over the FlangeStack, over the bolt's nominal
% diameter D. EdgeDistance defaults NaN ("unconfigured") on model.FlangeLayer;
% see the header for the ASSUMED / VERIFIED / partially-ASSUMED distinction.
D = joint.Bolt.NominalDiameter;
edgeDistances = [joint.FlangeStack.EdgeDistance];
knownEdges    = edgeDistances(~isnan(edgeDistances));
if isempty(knownEdges)
    % No layer records EdgeDistance at all -> ASSUMED satisfied, not verified.
    condEdge = true;
    edgeTrace = "e/D >= 1.5 ASSUMED (no FlangeLayer.EdgeDistance set)";
else
    eOverD   = min(knownEdges) / D;
    condEdge = eOverD >= 1.5;
    allKnown = numel(knownEdges) == numel(edgeDistances);
    if condEdge
        if allKnown
            edgeTrace = sprintf("e/D(%.2f) >= 1.5 VERIFIED (all layers set)", eOverD);
        else
            % Known layers clear 1.5, but an unrecorded layer could still be
            % the tight one -- decide to test what is known, but mark the
            % overall result assumed rather than fully verified.
            edgeTrace = sprintf( ...
                "e/D(%.2f, known layers) >= 1.5, ASSUMED for the full stack (some layers' EdgeDistance unset)", ...
                eOverD);
        end
    else
        % A known layer already fails -- the true stack minimum can only be
        % <= this value, so the condition fails regardless of any unknown
        % layer. This is decisive evidence, not an assumption.
        edgeTrace = sprintf("e/D(%.2f) < 1.5 VERIFIED failing", eOverD);
    end
end

assured = condStiffness && condPreload && condPlane && condEdge;

if assured
    trace = string(sprintf( ...
        ['Separation before rupture assured: Ec(%.3g) > Eb/3(%.3g); ' ...
         'PpMax(%.0f) <= 0.75*Ptu_allow(%.0f); n(%.2f) <= 0.9; '], ...
        Ec, Eb/3, preload.PpMax, 0.75*PtuAllow, n)) + edgeTrace + ".";
else
    fails = strings(1, 0);
    if ~condStiffness
        fails(end+1) = sprintf("Ec(%.3g) <= Eb/3(%.3g)", Ec, Eb/3); %#ok<AGROW>
    end
    if ~condPreload
        fails(end+1) = sprintf("PpMax(%.0f) > 0.75*Ptu_allow(%.0f)", ...
            preload.PpMax, 0.75*PtuAllow); %#ok<AGROW>
    end
    if ~condPlane
        fails(end+1) = sprintf("n(%.2f) > 0.9", n); %#ok<AGROW>
    end
    if ~condEdge
        fails(end+1) = edgeTrace; %#ok<AGROW>
    end
    trace = "Separation before rupture NOT assured (rupture assumed): " + ...
        strjoin(fails, "; ");
    if condEdge
        % Edge condition itself passed (assumed or verified) but some other
        % condition failed -- still record its status for the reader.
        trace = trace + " (" + edgeTrace + ")";
    end
end

g = struct("Assessed", true, "Assured", assured, "PtuAllow", PtuAllow, ...
    "SystemAllowable", sys, "Trace", trace);
end

% ---- Local helpers --------------------------------------------------------
function g = notAssessed(reason, sys)
%NOTASSESSED  The gate could not be evaluated at all.
%   sys (optional) carries the engine.systemTensileAllowable struct when it
%   was computed before the not-assessed decision (the Ptu_allow-NaN path),
%   so callers still see the per-mode trace; struct() when it was never
%   computed (the FlangeStack-empty path, before sys can even be tried).
if nargin < 2
    sys = struct();
end
g = struct("Assessed", false, "Assured", false, "PtuAllow", NaN, ...
    "SystemAllowable", sys, "Trace", "Fig. 8 gate not assessed: " + string(reason));
end
