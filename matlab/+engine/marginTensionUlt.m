function r = marginTensionUlt(joint, preload, designLoads)
%MARGINTENSIONULT  Ultimate-tension margin with separation-before-rupture gate.
%   r = engine.marginTensionUlt(joint, preload, designLoads) evaluates the
%   NASA-STD-5020A Figure 8 (DABJ Fig. 9-9) separation-before-rupture
%   decision tree, then computes the bolt ultimate-tension margin of
%   safety. preload is the struct from engine.preload; designLoads is the
%   struct from engine.designLoads. All loads in lbf (see UNITS.md).
%
%   Returned struct fields:
%       MS                      margin of safety (double; NaN if rupture
%                               path — see below)
%       SeparationBeforeRupture logical: gate result
%       Decision                string trace of the gate evaluation
%       Method                  string: governing equation
%
%   Separation-before-rupture is ASSURED when ALL of (Fig. 8 / Fig. 9-9):
%     1. Ec > Eb/3 — the softest clamped-member modulus (min E over the
%        FlangeStack, conservative) exceeds one third of the bolt modulus.
%     2. PpMax < 0.75*Ptu_allow — max in-service preload is below the low
%        end of the intermediate band. Preloads in [0.75, 0.85]*Ptu_allow
%        (and above) conservatively assume rupture (gate NOT assured).
%     3. LoadingPlaneFactor n <= 0.9.
%     4. Edge distance e/D >= 1.5 — the model has no edge-distance field
%        yet (arrives with Phase 3.2 bearing), so this condition is
%        ASSUMED TRUE and noted in Decision.
%
%   If assured:  MS = Ptu_allow / designLoads.Ptu - 1   (5020A Eq. 6 —
%   the bolt only sees the external design load). If NOT assured, the
%   rupture equations (5020A Eq. 10/11) need the joint-stiffness factor
%   phi, which is Phase 3.1; rather than fake it, MS = NaN with the
%   reason in Decision.
%
%   Ptu_allow = joint.BoltRatedUltimateLoad and is required to be set;
%   the At*Ftu fallback for an unset allowable is Phase 3.
%
%   Validated against the DABJ Section 9 class problem (Solutions-16, via
%   validation.dabjSection9): gate assured, MS = 15,200/9,000 - 1 = +0.69.

arguments
    joint       (1,1) model.Joint
    preload     (1,1) struct
    designLoads (1,1) struct
end

PtuAllow = joint.BoltRatedUltimateLoad;
if isnan(PtuAllow)
    error("engine:marginTensionUlt:allowableRequired", ...
        "BoltRatedUltimateLoad required for tension margin; At*Ftu fallback is Phase 3.");
end
if isempty(joint.FlangeStack)
    error("engine:marginTensionUlt:emptyFlangeStack", ...
        "Joint.FlangeStack is empty; the member modulus Ec is needed for the separation-before-rupture check.");
end

% ---- Separation-before-rupture gate (5020A Fig. 8 / DABJ Fig. 9-9) -----
Eb = joint.BoltMaterial.E;
flangeMats = [joint.FlangeStack.Material];
Ec = min([flangeMats.E]);                       % softest member (conservative)
n  = joint.LoadingPlaneFactor;

condStiffness = Ec > Eb/3;
condPreload   = preload.PpMax < 0.75 * PtuAllow;
condPlane     = n <= 0.9;
condEdge      = true;   % e/D >= 1.5 ASSUMED (no edge-distance field until Phase 3.2)

assured = condStiffness && condPreload && condPlane && condEdge;

% ---- Margin ------------------------------------------------------------
if assured
    MS = PtuAllow / designLoads.Ptu - 1;        % 5020A Eq. 6
    Method = "5020A Eq. 6 (separation before rupture)";
    Decision = string(sprintf( ...
        ['Separation before rupture assured: Ec(%.3g) > Eb/3(%.3g); ' ...
         'PpMax(%.0f) < 0.75*Ptu_allow(%.0f); n(%.2f) <= 0.9; ' ...
         'e/D >= 1.5 assumed. -> Eq. 6.'], ...
        Ec, Eb/3, preload.PpMax, 0.75*PtuAllow, n));
else
    fails = strings(1, 0);
    if ~condStiffness
        fails(end+1) = sprintf("Ec(%.3g) <= Eb/3(%.3g)", Ec, Eb/3); %#ok<AGROW>
    end
    if ~condPreload
        fails(end+1) = sprintf("PpMax(%.0f) >= 0.75*Ptu_allow(%.0f)", ...
            preload.PpMax, 0.75*PtuAllow); %#ok<AGROW>
    end
    if ~condPlane
        fails(end+1) = sprintf("n(%.2f) > 0.9", n); %#ok<AGROW>
    end
    MS = NaN;
    Method = "5020A Eq. 10/11 (rupture) — requires stiffness, Phase 3.1";
    Decision = "Separation before rupture NOT assured (rupture assumed): " + ...
        strjoin(fails, "; ") + ...
        ". Eq. 10/11 needs the joint-stiffness factor phi (Phase 3.1); MS = NaN until then.";
end

r = struct( ...
    "MS",                      MS, ...
    "SeparationBeforeRupture", assured, ...
    "Decision",                Decision, ...
    "Method",                  Method);
end
