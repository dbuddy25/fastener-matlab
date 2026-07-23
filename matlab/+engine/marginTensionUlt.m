function r = marginTensionUlt(joint, preload, designLoads)
%MARGINTENSIONULT  Ultimate-tension margin with separation-before-rupture gate.
%   r = engine.marginTensionUlt(joint, preload, designLoads) evaluates the
%   NASA-STD-5020B Figure 8 (DABJ Fig. 9-9) separation-before-rupture
%   decision tree, then computes the bolt ultimate-tension margin of
%   safety. preload is the struct from engine.preload; designLoads is the
%   struct from engine.designLoads. All loads in lbf (see UNITS.md).
%
%   Returned struct fields:
%       MS                      margin of safety (double; NaN only if the
%                               rupture path needs stiffness geometry the
%                               joint does not carry — see below)
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
%   If assured:  MS = Ptu_allow / designLoads.Ptu - 1   (NASA-STD-5020B Eq. 6 —
%   the bolt only sees the external design load). If NOT assured, rupture
%   governs: the bolt carries the max preload PLUS its share of the applied
%   load, so the margin uses the joint-stiffness factor phi from
%   engine.stiffness (NASA-STD-5020B Eq. 9) and the loading-plane factor n:
%       P'tu = (Ptu_allow - Pp_max)/(n·phi),  MS = P'tu/Ptu - 1
%   (NASA-STD-5020B Eq. 10). If engine.stiffness cannot run (threaded-in
%   configuration or missing frustum geometry), the check reports MS = NaN
%   with the reason in Decision rather than crashing the analysis. The
%   yield-side rupture form (NASA-STD-5020B Eq. 11) is deferred — see
%   engine.marginBoltYield.
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

% ---- Separation-before-rupture gate (NASA-STD-5020B Fig. 8 / DABJ Fig. 9-9) -----
Eb = joint.BoltMaterial.E;
flangeMats = [joint.FlangeStack.Material];
Ec = min([flangeMats.E]);                       % softest member (conservative)
n  = joint.LoadingPlaneFactor;

% NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) — Ec > Eb/3 (member-stiffness gate)
condStiffness = Ec > Eb/3;
% NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) — PpMax < 0.75·Ptu_allow (preload gate;
% [0.75, 0.85]·Ptu_allow band conservatively treated as rupture)
condPreload   = preload.PpMax < 0.75 * PtuAllow;
% NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) — n <= 0.9 (loading-plane-factor gate)
condPlane     = n <= 0.9;
% NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) — e/D >= 1.5 (edge-distance gate);
% ASSUMED TRUE (no edge-distance field until Phase 3.2)
condEdge      = true;

assured = condStiffness && condPreload && condPlane && condEdge;

% ---- Margin ------------------------------------------------------------
if assured
    % NASA-STD-5020B Eq. 6 — MS = Ptu_allow / Ptu - 1
    MS = PtuAllow / designLoads.Ptu - 1;
    Method = "NASA-STD-5020B Eq. 6 (separation before rupture)";
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
    gateTrace = "Separation before rupture NOT assured (rupture assumed): " + ...
        strjoin(fails, "; ");
    try
        s   = engine.stiffness(joint);   % errors for threaded-in / missing geometry
        phi = s.Phi;                     % NASA-STD-5020B Eq. 9 — phi = kb/(kb + kc)
        % NASA-STD-5020B Eq. 10 — P'tu = (Ptu_allow - Pp_max)/(n·phi);
        % MS = P'tu/Ptu - 1 (bolt carries the preload plus n·phi of the load)
        Pprime = (PtuAllow - preload.PpMax) / (n * phi);
        MS = Pprime / designLoads.Ptu - 1;
        Method = "NASA-STD-5020B Eq. 10 (rupture — bolt sees preload + n·phi·load)";
        Decision = gateTrace + string(sprintf( ...
            ". -> Eq. 10 with phi = %.4g (NASA-STD-5020B Eq. 9), n = %.2f.", phi, n));
    catch stiffErr
        % Stiffness unavailable (threaded-in configuration or missing
        % frustum geometry) — report NotEvaluated, do not crash analyze.
        MS = NaN;
        Method = "NASA-STD-5020B Eq. 10 (rupture) — stiffness geometry required";
        Decision = gateTrace + ...
            ". Eq. 10 needs phi from engine.stiffness, which could not run: " + ...
            string(stiffErr.message);
    end
end

r = struct( ...
    "MS",                      MS, ...
    "SeparationBeforeRupture", assured, ...
    "Decision",                Decision, ...
    "Method",                  Method);
end
