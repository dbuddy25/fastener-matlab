function b = boltBendingStress(joint, Mbu)
%BOLTBENDINGSTRESS  Design ultimate bending stress fbu for the Eq. 20/22 term.
%   b = boltBendingStress(joint, Mbu) converts the design ultimate bending
%   MOMENT Mbu (in-lbf, from engine.designLoads) into the design ultimate
%   bending STRESS fbu (psi) that NASA-STD-5020B Eq. 20/22 adds inside the
%   tension bracket. Private to +engine.
%
%   NASA-STD-5020B §4.4.4 defines fbu as "the design ultimate bending
%   stress based on linear-elastic theory" but does NOT state which cross
%   section to take it on. Linear-elastic bending of a circular section:
%       fbu = M*c/I,  c = d/2,  I = pi*d^4/64   ->   fbu = 32*Mbu/(pi*d^3)
%
%   WHICH d — THE SECTION FOLLOWS THE SHEAR PLANE. This is a DERIVED
%   CONVENTION, not a 5020B relation, and it mirrors the sectioning the
%   standard already applies to the shear allowable in the very same
%   criteria: Eq. 12 takes the shank area when the body is in the shear
%   plane, Eq. 13 the minor-diameter area when the threads are. 5020B's own
%   reason for the different Eq. 20/21 vs Eq. 22/23 exponents is that
%   "tensile and shear stresses peak at the same cross section when the
%   threads are in the shear plane", so taking bending on the nominal
%   diameter there would put the bending stress on a section the standard
%   has just said is not the critical one — unconservative in exactly the
%   configuration 5020B singles out.
%       BodyInShear    -> Bolt.BodyDiameter, NaN falling back to
%                         Bolt.NominalDiameter (the same fallback
%                         model.Bolt.get.BodyArea already uses)
%       ThreadsInShear -> Bolt.MinorDiameter
%
%   NO MOMENT IS NOT AN ERROR. Mbu NaN (nothing supplied) or 0 returns
%   HasMoment = false and Value = 0 — exactly zero, so a joint with no
%   bending moment reproduces its pre-bending R bit for bit. Whether that
%   silence is legitimate is NOT this function's business: it is
%   Joint.ShearTransferCondition's, and engine.marginInteraction reads it.
%   This function reports what the geometry and the moment support and
%   leaves the §4.4.4 determination to the caller.
%
%   Returned struct fields:
%       Value      fbu, psi. 0 when no moment; NaN when not assessable.
%       HasMoment  logical: a nonzero bending moment was supplied.
%       Assessed   logical: Value is usable (true when HasMoment is false).
%       Diameter   d used, in (NaN when not assessable).
%       Basis      "body" | "minor" | "none"
%       Note       string: the arithmetic, for the margin Detail.
%       Reason     string: why not assessed ("" when Assessed).
%
%   Call graph:
%       Precedents (calls)      none — reads model.Bolt / model.Joint
%                               getters directly.
%       Dependents (called by)  engine.marginInteraction.
%       Tests                   tests/tDabjCase.m (the bending trio),
%                               tests/tBoltAllowable.m (Ftu/geometry
%                               unavailable paths).
%
%   Validation status/coverage: VALIDATION.md, Margin checks row 13b
%   (hand-calc — 5020B prints no worked bending example).

arguments
    joint (1,1) model.Joint
    Mbu   (1,1) double
end

b = struct("Value", 0, "HasMoment", false, "Assessed", true, ...
    "Diameter", NaN, "Basis", "none", ...
    "Note", "no bending moment supplied (fbu = 0)", "Reason", "");

if isnan(Mbu) || Mbu == 0
    return
end
b.HasMoment = true;

% Section per the shear plane — see the header.
switch joint.ShearPlane
    case model.ShearPlaneCondition.ThreadsInShear
        d       = joint.Bolt.MinorDiameter;
        b.Basis = "minor";
    otherwise   % BodyInShear
        d = joint.Bolt.BodyDiameter;
        if isnan(d)
            d = joint.Bolt.NominalDiameter;
        end
        b.Basis = "body";
end

if ~isfinite(d) || d <= 0
    b.Value    = NaN;
    b.Assessed = false;
    b.Basis    = "none";
    b.Note     = "";
    b.Reason   = "bending stress needs a bolt " + ...
        ternary(joint.ShearPlane == model.ShearPlaneCondition.ThreadsInShear, ...
            "MinorDiameter (threads in the shear plane)", ...
            "BodyDiameter or NominalDiameter (body in the shear plane)") + ...
        ", which is not set";
    return
end

% NASA-STD-5020B §4.4.4 fbu (linear-elastic) — fbu = M*c/I with c = d/2 and
% I = pi*d^4/64, i.e. fbu = 32*Mbu/(pi*d^3)
b.Value    = 32 * Mbu / (pi * d^3);
b.Diameter = d;
b.Note     = string(sprintf( ...
    "fbu = 32*%.4g/(pi*%.4f^3) = %.1f psi (%s-diameter section, linear-elastic)", ...
    Mbu, d, b.Value, b.Basis));
end

% ---- Local helpers --------------------------------------------------------
function s = ternary(cond, a, b)
%TERNARY  Pick one of two strings. Keeps the Reason line above readable.
if cond
    s = a;
else
    s = b;
end
end
