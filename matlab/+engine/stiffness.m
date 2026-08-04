function s = stiffness(joint)
%STIFFNESS  Bolt/member stiffness + stiffness factor (30° conical frustum).
%   s = engine.stiffness(joint) computes the axial bolt stiffness Kb, the
%   clamped-member stiffness Kc (Shigley conical-frustum method, 30°
%   half-angle; see also DABJ §8, Eqs. 8.1c / 8.1e-f), and the joint
%   stiffness factor Phi (NASA-STD-5020B Eq. 9).
%   Lengths in inches, moduli in psi, stiffnesses in lbf/in (see UNITS.md).
%
%   The kb/kc frustum equations are NOT in NASA-STD-5020B — 5020B takes the
%   stiffnesses as given inputs to Eq. 9 — so the conical-frustum method
%   (Shigley, 30° half-angle) is the primary source here, with DABJ §8 as
%   the validation-only see-also (Example 8-b is the answer key).
%
%   IMPORTANT — length conventions (the most likely source of error per
%   DABJ §8): the member stiffness kc uses the FITTING stack length
%   (sum of flange thicknesses) as L — plus D/2 on the threaded-in branch —
%   NOT the washer-inclusive clamped length. Washers are rigid in the
%   frustum (see model.Washer): they add clamped length to kb and grow the
%   contact diameter dc for kc, but they contribute no frustum material of
%   their own. The spread matters: starting the cone at the bare head
%   bearing diameter instead reproduces neither DABJ answer key.
%
%   L1 (unthreaded body length in the grip) — three-level precedence:
%     1. An explicit Joint.BodyLengthInGrip is used as-is.
%     2. Otherwise, a supplied overall Bolt.Length gives the shank directly:
%        Ls = Bolt.Length − Bolt.ThreadLength, L1 = min(max(Ls,0), Lb).
%     3. Otherwise, a SIMPLIFIED fallback estimates the bolt length as
%        grip + nut height + 2·pitch (NASA-STD-5020B §4.7.4) and proceeds
%        as in level 2 — see the inline comment. Nut height (Le) is
%        resolved by the shared private helper resolveEngagementLength:
%        ThreadedMember.EngagementRatio x Bolt.NominalDiameter when the
%        ratio is set (overrides EngagementLength), else the unchanged
%        EngagementLength.
%   If the level-2/3 inputs are NaN, stiffness errors with id
%   engine:stiffness:bodyLengthRequired (existing behavior). Bolt.Length
%   defaults to NaN, in which case levels 1 and 3 behave exactly as before.
%
%   BOTH configurations are supported. THROUGH-BOLT (nut) uses the
%   symmetric back-to-back frustum over the fitting stack. THREADED-IN
%   (insert / tapped hole) uses the SAME closed form fed a shortened grip,
%   L = t1 + D/2, per Shigley & Mischke (see also DABJ §8 slide 8-23) —
%   t1 is the through-hole member stack, and D/2 reaches to the midpoint of
%   the engaged threads. Its kb drops the threaded end's +0.4D in favour of
%   h = min(D/2, t2/2); the tapped member thickness t2 is not carried by the
%   model, so h = D/2 is assumed (DABJ's "usually, h = D/2") and recorded in
%   the returned Method. Mixed flange moduli still error with id
%   engine:stiffness:mixedModulusDeferred (per-layer frustum slicing is
%   deferred — see STIFFNESS_PLAN.md Job B).
%
%   Returned struct fields:
%       Kb    bolt stiffness, lbf/in
%       Kc    clamped-member stiffness, lbf/in
%       Phi   stiffness factor kb/(kb+kc), dimensionless (NASA-STD-5020B Eq. 9)
%       L1    unthreaded body length in the grip, in (traceability)
%       L2    threaded length in the grip, in (traceability)
%       Dc    frustum contact diameter at the fitting face, in (traceability)
%       Ec    common member (flange) modulus, psi (traceability)
%       Lc    frustum length actually used for kc, in (traceability —
%             tFit for a nut joint, tFit + D/2 for a threaded-in joint)
%       Method  string: the governing frustum forms used, incl. the
%             h = D/2 assumption on the threaded-in branch
%
%   Call graph:
%       Precedents (calls)      model.Joint, model.Bolt, model.Material,
%                               resolveEngagementLength (private, level-3 L1
%                               fallback only) — otherwise a leaf; no other
%                               engine.* dependencies.
%       Dependents (called by)  engine.preload, engine.boltDesignLoad,
%                               engine.marginTensionUlt,
%                               engine.marginTensionYield,
%                               engine.marginBearingUnderHead. NOT
%                               gui.FastenerApp — the GUI's only engine
%                               entry point is engine.analyze; its several
%                               "engine.stiffness" mentions are tooltip
%                               text, not calls.
%       Tests                   tests/tStiffness.m —
%                               stiffnessMatchesDABJ8b (DABJ Ex 8-b
%                               Kb/Kc/Phi + traceability intermediates);
%                               bodyLengthFallbackComputed (L1 levels 2/3);
%                               threadedInMatchesDabjTable83 (both Table 8-3
%                               rows, Kc + Lb); threadedInShortensGripAndDropsPoint4D
%                               (branch selection vs the nut case);
%                               threadedInThermalPreloadRuns (the path that
%                               used to throw); mixedModulusStillDeferred.
%
%   Validation status/coverage: see VALIDATION.md (Stiffness, rows 1-4).

arguments
    joint (1,1) model.Joint
end

% ---- Configuration ------------------------------------------------------
% Threaded-in = the bolt threads into an insert or a tapped hole rather than
% a nut, so there is no nut-side washer and the far end of the frustum sits
% inside the tapped member (see the kb/kc branches below).
threadedIn = joint.ThreadedMember.Type ~= model.ThreadedMemberType.Nut;

if isempty(joint.FlangeStack)
    error("engine:stiffness:emptyFlangeStack", ...
        "Joint.FlangeStack is empty; the member frustum needs the clamped stack.");
end

D   = joint.Bolt.NominalDiameter;      % major dia, in
As  = joint.Bolt.BodyArea;             % unthreaded shank area pi/4*d^2, in^2
At  = joint.Bolt.TensileStressArea;    % At, in^2
Eb  = joint.BoltMaterial.E;            % bolt modulus, psi
dwf = joint.Bolt.HeadBearingDiameter;  % washer-face / head bearing dia, in
ang = joint.FrustumAngle;              % frustum half-angle, deg (30 default)
tanA = tand(ang);

% ---- Input guards -------------------------------------------------------
if isnan(D) || isnan(At) || isnan(Eb)
    error("engine:stiffness:boltUnderdefined", ...
        "Bolt NominalDiameter, TensileStressArea, and BoltMaterial.E are required for stiffness.");
end
if isnan(dwf)
    error("engine:stiffness:headBearingDiameterRequired", ...
        "Bolt.HeadBearingDiameter (washer-face dia d_wf) is required for the member frustum.");
end

% ---- Clamped lengths ----------------------------------------------------
tFit  = sum([joint.FlangeStack.Thickness]);                     % fitting stack (kc uses THIS as L), in
tWash = joint.HeadWasher.Thickness + joint.NutWasher.Thickness; % total washer thickness, in
Lbolt = tFit + tWash;                                           % washer-inclusive clamped length for kb, in

% ---- Body length in grip (L1) -------------------------------------------
% L1 = unthreaded shank length within the clamp. Three-level precedence:
%   1. An explicit Joint.BodyLengthInGrip ALWAYS wins (e.g. DABJ Example
%      8-b supplies L1 = 0.70 directly).
%   2. Else a supplied overall Bolt.Length is used directly as the bolt
%      length (no estimate needed):
%        shank Ls = Bolt.Length − ThreadLength ;  Lb = clamped length
%        (fittings + washers) ;  L1 = min(max(Ls,0), Lb)
%   3. Else a SIMPLIFIED estimate of the bolt length is used:
%        bolt length ≈ grip + nut height + 2·pitch  (NASA-STD-5020B §4.7.4)
%      then Ls / L1 as in level 2.
% If the required inputs for the active level (Bolt.ThreadLength; plus, for
% level 3, nut height — resolved by resolveEngagementLength from
% ThreadedMember.EngagementRatio x Bolt.NominalDiameter or, when the ratio
% is unset, EngagementLength — and Bolt.Pitch) are NaN, L1 stays NaN and
% stiffness errors as before (callers render NotEvaluated). Bolt.Length
% defaults to NaN -> level 3, the pre-existing behavior, unchanged.
L1 = joint.BodyLengthInGrip;           % unthreaded body length in the clamp, in
if isnan(L1)
    Lthd = joint.Bolt.ThreadLength;                 % threaded length from the tip, in
    if ~isnan(joint.Bolt.Length)
        % Level 2 — supplied overall bolt length replaces the estimate.
        if ~isnan(Lthd)
            Ls = joint.Bolt.Length - Lthd;          % unthreaded shank length, in
            L1 = min(max(Ls, 0), Lbolt);            % clip into the clamp
        end
    else
        % Level 3 — the §4.7.4 estimate (pre-existing fallback, untouched
        % apart from the Le resolution itself). nutH: ratio-or-absolute,
        % single resolution — see resolveEngagementLength (EngagementRatio,
        % when set, OVERRIDES EngagementLength).
        rle  = resolveEngagementLength(joint);
        nutH = rle.Le;                                  % nut height, in
        p    = joint.Bolt.Pitch;                        % thread pitch, in
        if ~isnan(nutH) && ~isnan(p) && ~isnan(Lthd)
            boltLen = Lbolt + nutH + 2*p;           % ≈ grip + nut height + 2·pitch
            Ls      = boltLen - Lthd;               % unthreaded shank length, in
            L1      = min(max(Ls, 0), Lbolt);       % clip into the clamp
        end
    end
end
if isnan(L1)
    error("engine:stiffness:bodyLengthRequired", ...
        "Joint.BodyLengthInGrip (unthreaded body length L1 in the clamp) is required for bolt stiffness " + ...
        "(or supply Bolt.Length and Bolt.ThreadLength; or ThreadedMember.EngagementLength or EngagementRatio " + ...
        "(the latter also needing Bolt.NominalDiameter), " + ...
        "Bolt.Pitch, and Bolt.ThreadLength for the computed fallback).");
end
L2    = Lbolt - L1;                                             % threaded length in the grip, in
if L2 < 0
    error("engine:stiffness:bodyLongerThanGrip", ...
        "BodyLengthInGrip (%.4g) exceeds the clamped length (%.4g).", L1, Lbolt);
end

% ---- Bolt stiffness -----------------------------------------------------
if threadedIn
    % Shigley & Mischke, threaded-in form (see also DABJ §8 Eq. 8.1g;
    % validation only) — the threaded end has no nut to extend into, so it
    % LOSES the +0.4D of the through-bolt form and instead runs h into the
    % engaged threads:
    %   kb = Eb * [ (L1 + 0.4D)/As + (L2 + h)/At ]^-1,  h = min(D/2, t2/2)
    % t2 (tapped member thickness) is not carried by the model — the tapped
    % parent is not a FlangeLayer (see CLAUDE.md) — so h = D/2 is assumed,
    % per DABJ's "usually, h = D/2". The assumption is surfaced in Method
    % below. h = D/2 is the larger of the two candidates, hence the LONGER
    % (more compliant, lower kb) bolt whenever t2 < D; low kb lowers phi,
    % so the assumption is unconservative only for a tapped member thinner
    % than the bolt diameter.
    h  = D/2;                                                   % in
    kb = Eb / ( (L1 + 0.4*D)/As + (L2 + h)/At );
else
    % Shigley conical-frustum method (see also DABJ §8 Eq. 8.1c) — springs
    % in series, each end extended 0.4D into the head/nut:
    %   kb = Eb * [ (L1 + 0.4D)/As + (L2 + 0.4D)/At ]^-1
    kb = Eb / ( (L1 + 0.4*D)/As + (L2 + 0.4*D)/At );
end

% ---- Member (frustum) stiffness ----------------------------------------
% Require a uniform member modulus (per-layer frustum slicing is deferred).
memberE = arrayfun(@(fl) fl.Material.E, joint.FlangeStack);
if any(abs(memberE - memberE(1)) > 1e-9 * abs(memberE(1)))
    error("engine:stiffness:mixedModulusDeferred", ...
        "Flange layers have different moduli; per-layer frustum slicing is deferred — see STIFFNESS_PLAN.md Job B.");
end
Ec = memberE(1);                       % common member modulus, psi

if threadedIn
    % Shigley & Mischke, threaded-in clamp stiffness (see also DABJ §8
    % slide 8-23; validation only) — the SAME symmetric back-to-back
    % frustum closed form as the nut case, fed a SHORTENED grip:
    %   L = t1 + D/2
    % t1 is the through-hole member stack (tFit) and D/2 reaches to the
    % midpoint of the engaged threads, where the far frustum is taken to
    % start. Conditions the method carries: D < t2, one modulus across the
    % clamped members (enforced above), and members deep enough to capture
    % the frustums.
    L  = tFit + D/2;                   % in
    % ONE washer, under the head — a threaded-in joint has no nut washer,
    % so the two-washer average below would understate the spread. DABJ
    % Table 8-3 confirms the full thickness: dc = 0.613 = 0.523 +
    % 2*tan(30 deg)*0.078 for its 3/8 row.
    tw  = joint.HeadWasher.Thickness;  % in
    ods = joint.HeadWasher.OuterDiameter;
else
    L  = tFit;                         % member stack only (NOT washers), in
    tw = tWash / 2;                    % average washer thickness, in
    ods = [joint.HeadWasher.OuterDiameter, joint.NutWasher.OuterDiameter];
end

% Contact diameter at the fitting face: the rigid washer spreads the head
% bearing dia dwf at the frustum angle through the washer thickness, capped
% by the smallest specified washer OD (Shigley frustum geometry; see also
% DABJ §8) — dc = min( dwf + 2*tan(ang)*tw , min washer OD )
dcCone = dwf + 2*tanA*tw;
ods    = ods(~isnan(ods));             % ignore unspecified ODs
if isempty(ods)
    Dc = dcCone;
else
    Dc = min(dcCone, min(ods));
end

% Shigley conical-frustum member stiffness, general half-angle alpha
% (see also DABJ §8 Eq. 8.1f, printed for the 30° case) —
% kc = pi*tan(alpha)*Ec*D / ( 2*ln{ [(tan(alpha)*L + Dc - D)(Dc + D)] /
%                                   [(tan(alpha)*L + Dc + D)(Dc - D)] } )
% At the textbook's default alpha = 30°, pi*tan(30°) = 1.8138 (NOT
% pi*tan(30)/ln(5) = 1.127, which is a different, unrelated number — the
% coefficient is just pi*tan(alpha), with no ln() in it). Using the
% symbolic pi*tanA (rather than a 30°-only constant) makes kc correct at
% any FrustumAngle; joint.FrustumAngle is a validated, GUI-exposed
% property constrained to (0, 90) deg EXCLUSIVE (model.Joint), so other
% angles are reachable but 90° itself (where tand(ang) is singular) and
% angles beyond it (where tand(ang) goes negative, feeding a bogus tanA
% into kc below) are rejected before they ever reach this function.
arg = ((tanA*L + Dc - D)*(Dc + D)) / ((tanA*L + Dc + D)*(Dc - D));
kc  = pi*tanA*Ec*D / (2*log(arg));     % log() is natural log

% ---- Stiffness factor ---------------------------------------------------
% NASA-STD-5020B Eq. 9 — phi = kb/(kb + kc)
% (DABJ prints it as 5020B Eq. 9 — identical equation.)
phi = kb / (kb + kc);

% ---- Method (traceability; flows into Result/reports/GUI) ----------------
if threadedIn
    method = string(sprintf( ...
        "Shigley conical frustum, %.4g deg half-angle (threaded-in): " + ...
        "kb = Eb*[(L1+0.4D)/As + (L2+h)/At]^-1 with h = D/2 ASSUMED " + ...
        "(h = min(D/2, t2/2); tapped member thickness t2 not modelled); " + ...
        "kc over the shortened grip L = t1 + D/2 = %.4g in; " + ...
        "phi = kb/(kb+kc) per NASA-STD-5020B Eq. 9. " + ...
        "Validated against DABJ Table 8-3 (slide 8-26).", ang, L));
else
    method = string(sprintf( ...
        "Shigley conical frustum, %.4g deg half-angle (through-bolt): " + ...
        "kb = Eb*[(L1+0.4D)/As + (L2+0.4D)/At]^-1; " + ...
        "kc symmetric back-to-back over the fitting stack L = %.4g in; " + ...
        "phi = kb/(kb+kc) per NASA-STD-5020B Eq. 9. " + ...
        "Validated against DABJ Example 8-b.", ang, L));
end

s = struct( ...
    "Kb",     kb, ...
    "Kc",     kc, ...
    "Phi",    phi, ...
    "L1",     L1, ...
    "L2",     L2, ...
    "Dc",     Dc, ...
    "Ec",     Ec, ...
    "Lc",     L, ...
    "Method", method);
end
