function lc = loadCaseFromForces(F, axis, opts)
%LOADCASEFROMFORCES  Build a model.LoadCase from one FEM element force vector.
%   lc = engine.loadCaseFromForces(F, axis) resolves the element forces onto
%   the bolt axis (engine.resolveForces — single-fastener CBUSH projection,
%   no bolt-pattern moment distribution) and returns a model.LoadCase with
%   the PER-BOLT limit loads set:
%       BoltTensileLimitLoad (PtL) — from the signed axial force
%       BoltShearLimitLoad   (PsL) — the transverse RSS shear
%   Joint-level loads are left NaN (per-bolt only here; joint-level totals
%   for multi-bolt slip come from the mapping table later).
%
%   lc = engine.loadCaseFromForces(F, axis, Name=..., Reversible=...,
%                                  ScaleFactor=...) options:
%       Name         (string)  LoadCase name (default "")
%       Reversible   (logical) load case can act in either direction
%                    (default false)
%       ScaleFactor  (double)  multiplier applied to the forces BEFORE
%                    resolution (default 1) — e.g. an uncertainty factor
%
%   Sign convention: Axial is signed with + = tension along the bolt axis.
%       Reversible = false → PtL = max(Axial, 0). Compression does not load
%                    the bolt in tension, so a compressive (negative) axial
%                    force yields PtL = 0.
%       Reversible = true  → PtL = abs(Axial). The load may reverse, so a
%                    compressive case must also be carried as tension.
%   Shear (an RSS, direction-free) passes through as PsL either way.

arguments
    F                (1,1) struct
    axis             (1,1) model.BoltAxis
    opts.Name        (1,1) string = ""
    opts.Reversible  (1,1) logical = false
    opts.ScaleFactor (1,1) double {mustBeNonnegative} = 1
end

% Scale the forces first, then resolve onto the bolt axis
fields = ["FX", "FY", "FZ", "MX", "MY", "MZ"];
for f = fields
    if isfield(F, f)
        F.(f) = opts.ScaleFactor * F.(f);
    end
end
r = engine.resolveForces(F, axis);

% Tension only when not reversible — compression doesn't load the bolt in tension
if opts.Reversible
    PtL = abs(r.Axial);
else
    PtL = max(r.Axial, 0);
end

lc = model.LoadCase(Name = opts.Name, ...
    BoltTensileLimitLoad = PtL, ...
    BoltShearLimitLoad   = r.Shear);
end
