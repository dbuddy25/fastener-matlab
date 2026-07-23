function s = stiffness(joint)
%STIFFNESS  Bolt/member stiffness + stiffness factor (30° conical frustum).
%   s = engine.stiffness(joint) computes the axial bolt stiffness Kb, the
%   clamped-member stiffness Kc (Shigley conical-frustum method, 30°
%   half-angle; see also DABJ §8, Eqs. 8.1c / 8.1e-f — matches the group
%   spreadsheet), and the joint stiffness factor Phi (NASA-STD-5020A Eq. 9).
%   Lengths in inches, moduli in psi, stiffnesses in lbf/in (see UNITS.md).
%
%   The kb/kc frustum equations are NOT in NASA-STD-5020A — 5020A takes the
%   stiffnesses as given inputs to Eq. 9 — so the conical-frustum method
%   (Shigley, 30° half-angle) is the primary source here, with DABJ §8 as
%   the validation-only see-also (Example 8-b is the answer key).
%
%   IMPORTANT — length conventions (the most likely source of error per
%   DABJ §8): the member stiffness kc uses the FITTING stack length
%   (sum of flange thicknesses) as L, NOT the washer-inclusive clamped
%   length. Washers are rigid in the frustum (see model.Washer): they add
%   clamped length to kb and grow the contact diameter dc for kc, but they
%   contribute no frustum material of their own.
%
%   THROUGH-BOLT (nut) configuration only in this phase. Insert/tapped-hole
%   joints error with id engine:stiffness:threadedInDeferred; mixed flange
%   moduli error with id engine:stiffness:mixedModulusDeferred (frustum
%   slicing per-layer is deferred).
%
%   Returned struct fields:
%       Kb    bolt stiffness, lbf/in
%       Kc    clamped-member stiffness, lbf/in
%       Phi   stiffness factor kb/(kb+kc), dimensionless (NASA-STD-5020A Eq. 9)
%       L1    unthreaded body length in the grip, in (traceability)
%       L2    threaded length in the grip, in (traceability)
%       Dc    frustum contact diameter at the fitting face, in (traceability)
%       Ec    common member (flange) modulus, psi (traceability)
%
%   Validated against DABJ Example 8-b (pp. 8-18..8-21, via
%   validation.dabjExample8b): Kb = 2.39e6, Kc = 4.73e6, Phi = 0.336.

arguments
    joint (1,1) model.Joint
end

% ---- Configuration guards ----------------------------------------------
if joint.ThreadedMember.Type ~= model.ThreadedMemberType.Nut
    error("engine:stiffness:threadedInDeferred", ...
        "threaded-into (insert/tapped) frustum form is deferred — Phase 3.1 later");
end
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
L1 = joint.BodyLengthInGrip;           % unthreaded body length in the clamp, in
if isnan(L1)
    error("engine:stiffness:bodyLengthRequired", ...
        "Joint.BodyLengthInGrip (unthreaded body length L1 in the clamp) is required for bolt stiffness.");
end

% ---- Clamped lengths ----------------------------------------------------
tFit  = sum([joint.FlangeStack.Thickness]);                     % fitting stack (kc uses THIS as L), in
tWash = joint.HeadWasher.Thickness + joint.NutWasher.Thickness; % total washer thickness, in
Lbolt = tFit + tWash;                                           % washer-inclusive clamped length for kb, in
L2    = Lbolt - L1;                                             % threaded length in the grip, in
if L2 < 0
    error("engine:stiffness:bodyLongerThanGrip", ...
        "BodyLengthInGrip (%.4g) exceeds the clamped length (%.4g).", L1, Lbolt);
end

% ---- Bolt stiffness -----------------------------------------------------
% Shigley conical-frustum method (see also DABJ §8 Eq. 8.1c; matches the
% group spreadsheet) — springs in series, each end extended 0.4D into the
% head/nut: kb = Eb * [ (L1 + 0.4D)/As + (L2 + 0.4D)/At ]^-1
kb = Eb / ( (L1 + 0.4*D)/As + (L2 + 0.4*D)/At );

% ---- Member (frustum) stiffness ----------------------------------------
% Require a uniform member modulus (per-layer frustum slicing is deferred).
memberE = arrayfun(@(fl) fl.Material.E, joint.FlangeStack);
if any(abs(memberE - memberE(1)) > 1e-9 * abs(memberE(1)))
    error("engine:stiffness:mixedModulusDeferred", ...
        "Flange layers have different moduli; per-layer frustum slicing is deferred — Phase 3.1 later.");
end
Ec = memberE(1);                       % common member modulus, psi
L  = tFit;                             % member stack only (NOT washers), in
tw = tWash / 2;                        % average washer thickness, in

% Contact diameter at the fitting face: the rigid washer spreads the head
% bearing dia dwf at the frustum angle through the washer thickness, capped
% by the smallest specified washer OD (Shigley frustum geometry; see also
% DABJ §8) — dc = min( dwf + 2*tan(ang)*tw , min washer OD )
dcCone = dwf + 2*tanA*tw;
ods    = [joint.HeadWasher.OuterDiameter, joint.NutWasher.OuterDiameter];
ods    = ods(~isnan(ods));             % ignore unspecified ODs
if isempty(ods)
    Dc = dcCone;
else
    Dc = min(dcCone, min(ods));
end

% Shigley 30° conical-frustum member stiffness (see also DABJ §8 Eq. 8.1f;
% matches the group spreadsheet) —
% kc = 1.81*Ec*D / ( 2*ln{ [(tan(ang)*L + Dc - D)(Dc + D)] /
%                          [(tan(ang)*L + Dc + D)(Dc - D)] } )
% (the 1.81 = pi*tan(30)/ln(5) constant is specific to the 30° half-angle)
arg = ((tanA*L + Dc - D)*(Dc + D)) / ((tanA*L + Dc + D)*(Dc - D));
kc  = 1.81*Ec*D / (2*log(arg));        % log() is natural log

% ---- Stiffness factor ---------------------------------------------------
% NASA-STD-5020A Eq. 9 — phi = kb/(kb + kc)
% (DABJ prints it as 5020B Eq. 9 — identical equation.)
phi = kb / (kb + kc);

s = struct( ...
    "Kb",  kb, ...
    "Kc",  kc, ...
    "Phi", phi, ...
    "L1",  L1, ...
    "L2",  L2, ...
    "Dc",  Dc, ...
    "Ec",  Ec);
end
