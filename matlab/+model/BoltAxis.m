classdef BoltAxis
    %BOLTAXIS  Global axis along which the fastener acts axially.
    %   Used to split a FEM element's 6-DOF force vector into per-bolt
    %   tension (the component along this axis) vs shear (RSS of the two
    %   transverse components) — see engine.resolveForces.
    %   X — bolt axial direction is global X (FY/FZ are shear).
    %   Y — bolt axial direction is global Y (FX/FZ are shear).
    %   Z — bolt axial direction is global Z (FX/FY are shear). The DEFAULT
    %       on model.Joint (typical for a bolt normal to an XY interface).
    enumeration
        X
        Y
        Z
    end
end
