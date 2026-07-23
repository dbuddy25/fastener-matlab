function r = resolveForces(F, axis)
%RESOLVEFORCES  Resolve a FEM element's 6-DOF force vector onto the bolt axis.
%   r = engine.resolveForces(F, axis) splits one element force vector into
%   per-bolt axial tension and shear. Force resolution per single-fastener
%   (CBUSH) projection — axial = F along the bolt axis, shear = RSS of the
%   two transverse forces (mirrors NASTRAN CBUSH element output); no
%   bolt-pattern moment distribution. This is a geometric projection, not a
%   NASA-STD-5020B equation — no equation number applies.
%
%   Inputs:
%       F      struct with force fields FX, FY, FZ (lbf, required) and
%              moment fields MX, MY, MZ (in-lbf, optional — default 0)
%       axis   model.BoltAxis — the global axis the fastener acts along
%
%   Returned struct fields:
%       Axial    signed force along the bolt axis, lbf (+ = tension)
%       Shear    RSS of the two transverse forces, lbf (always >= 0)
%       Bending  RSS of the two transverse moments, in-lbf (informational —
%                the LoadCase carries no bending field)
%   Torsion (the moment ABOUT the bolt axis) is ignored.
%
%   For axis = Z:  Axial = FZ, Shear = hypot(FX,FY), Bending = hypot(MX,MY).
%   Axis X and Y are analogous.

arguments
    F    (1,1) struct
    axis (1,1) model.BoltAxis
end

MX = getMoment(F, "MX");
MY = getMoment(F, "MY");
MZ = getMoment(F, "MZ");

switch axis
    case model.BoltAxis.X
        % Axial FX; transverse FY/FZ, MY/MZ; torsion MX ignored
        r = struct("Axial", F.FX, "Shear", hypot(F.FY, F.FZ), "Bending", hypot(MY, MZ));
    case model.BoltAxis.Y
        % Axial FY; transverse FX/FZ, MX/MZ; torsion MY ignored
        r = struct("Axial", F.FY, "Shear", hypot(F.FX, F.FZ), "Bending", hypot(MX, MZ));
    case model.BoltAxis.Z
        % Axial FZ; transverse FX/FY, MX/MY; torsion MZ ignored
        r = struct("Axial", F.FZ, "Shear", hypot(F.FX, F.FY), "Bending", hypot(MX, MY));
end
end

function m = getMoment(F, name)
%GETMOMENT  Moment component, defaulting to 0 when the field is absent.
if isfield(F, name)
    m = F.(name);
else
    m = 0;
end
end
