function r = marginShearUlt(joint, designLoads)
%MARGINSHEARULT  Bolt ultimate-shear margin of safety (NASA-STD-5020B Eq. 14).
%   r = engine.marginShearUlt(joint, designLoads) computes the bolt
%   ultimate-shear margin for one joint. designLoads is the struct from
%   engine.designLoads. All loads in lbf (see UNITS.md).
%
%   The shear allowable is Fsu times the area cut by the shear plane,
%   chosen by joint.ShearPlane:
%       BodyInShear    — full-diameter shank area (joint.Bolt.BodyArea)
%       ThreadsInShear — minor (thread-root) area (joint.Bolt.MinorArea)
%   Then:
%       Psu_allow = Fsu * A_shear
%       MS = Psu_allow / Psu - 1                             (Eq. 14)
%   where Fsu = joint.BoltMaterial.Fsu and Psu = designLoads.Psu
%   (FSU * FFU * PsL).
%
%   NaN GUARD: Fsu (joint.BoltMaterial.Fsu), the shear-plane area
%   (BodyArea/MinorArea per joint.ShearPlane), and designLoads.Psu must
%   all be set; if any is NaN the check reports MS = NaN (NotEvaluated)
%   with the specific missing input named in Detail, rather than letting
%   an unset input propagate to a silent NaN with no explanation (Detail
%   used to be hardcoded "" here -- the only one of the fifteen checks
%   with no Detail at all; engine.marginInteraction reuses this
%   function's ShearAllowable, so a silent NaN here would silently
%   propagate there too).
%
%   Returned struct fields:
%       MS              margin of safety (double; NaN = not evaluated)
%       ShearAllowable  Psu_allow, lbf (reused by engine.marginInteraction;
%                       NaN when not evaluated)
%       Method          string: governing equation
%       Detail          string: governing arithmetic (Fsu, area, Psu_allow,
%                       Psu) on a normal evaluation, or the named missing
%                       input when not evaluated
%
%   Call graph:
%       Precedents (calls)      (leaf — joint/model getters and the
%                               designLoads struct only; no engine.*
%                               dependencies).
%       Dependents (called by)  engine.analyze, engine.marginInteraction
%                               (reuses ShearAllowable so both checks share
%                               one shear allowable).
%       Tests                   tests/tDabjCase.m —
%                               shearUltMarginMatchesDABJ (DABJ §9
%                               body-in-shear MS pin),
%                               threadsInShearUsesMinorAreaForShearAllowable
%                               (direct call; pins the MinorArea-based
%                               ShearAllowable/MS on the threads-in-shear
%                               branch), shearUltNaNGuardNamesMissingInput
%                               (Fsu / area / Psu each NaN in turn ->
%                               NotEvaluated with the specific input named,
%                               no crash; confirms the guard never fires on
%                               the two pins above).
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, row 3).

arguments
    joint       (1,1) model.Joint
    designLoads (1,1) struct
end

method = "NASA-STD-5020B Eq. 12/13 allowable + Eq. 14 (ultimate shear, area by shear-plane condition)";

switch joint.ShearPlane
    case model.ShearPlaneCondition.BodyInShear
        % NASA-STD-5020B Eq. 12 (body in shear) — Psu_allow = Fsu · A_body
        % AREA NOTE (D, comment-only -- behavior unchanged): the area used
        % here is joint.Bolt.BodyArea, whose getter falls back to
        % BodyDiameter when set (see model.Bolt), while Eq. 12 itself
        % prints D as the NOMINAL fastener diameter. For an undercut or
        % necked-down shank the body (reduced) diameter is SMALLER than
        % the nominal major diameter, so BodyArea < the Eq. 12 nominal
        % area. Using BodyArea is the physically correct choice for a
        % necked shank -- it is the actual material the shear plane cuts
        % through, not the nominal thread-major diameter the fastener
        % happens to be specified by -- and it is CONSERVATIVE whenever
        % the two differ (a smaller area gives a smaller, more
        % conservative Psu_allow). This is a silent substitution under a
        % citation that prints "Eq. 12" with D as nominal diameter; stated
        % here so it is not silent to a reader.
        area = joint.Bolt.BodyArea;
        areaName = "Bolt.BodyArea";
    case model.ShearPlaneCondition.ThreadsInShear
        % NASA-STD-5020B Eq. 13 (threads in shear) — Psu_allow = Fsu · A_minor
        area = joint.Bolt.MinorArea;
        areaName = "Bolt.MinorArea";
    otherwise
        error("engine:marginShearUlt:unknownShearPlane", ...
            "Unsupported shear-plane condition: %s", string(joint.ShearPlane));
end

Fsu = joint.BoltMaterial.Fsu;
Psu = designLoads.Psu;

% NaN GUARD (B/C): Fsu, the shear-plane area, and the design shear load
% must all be set, or Psu_allow/MS silently comes out NaN with no
% explanation -- and engine.marginInteraction, which reuses ShearAllowable
% below, would inherit that silence too. Name exactly what is missing.
if isnan(Fsu) || isnan(area) || isnan(Psu)
    missing = strings(1, 0);
    if isnan(Fsu),  missing(end+1) = "BoltMaterial.Fsu"; end             %#ok<AGROW>
    if isnan(area), missing(end+1) = areaName + " (shear-plane area)";   end %#ok<AGROW>
    if isnan(Psu),  missing(end+1) = "designLoads.Psu (design shear load)"; end %#ok<AGROW>
    r = struct("MS", NaN, "ShearAllowable", NaN, "Method", method, ...
        "Detail", "Not evaluated: " + join(missing, " and ") + " undefined (NaN).");
    return
end

% NASA-STD-5020B Eq. 12/13 — Psu_allow = Fsu · A_shear (A_shear selected by
% shear-plane condition above)
ShearAllowable = Fsu * area;                                 % Psu_allow, lbf
% NASA-STD-5020B Eq. 14 — MS = Psu_allow / Psu - 1
MS = ShearAllowable / Psu - 1;

r = struct( ...
    "MS",             MS, ...
    "ShearAllowable", ShearAllowable, ...
    "Method",         method, ...
    "Detail",         string(sprintf( ...
        "Psu_allow = Fsu(%.0f)*A(%.4f) = %.1f lbf vs Psu = %.1f lbf", ...
        Fsu, area, ShearAllowable, Psu)));
end
