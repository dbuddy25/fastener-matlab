function r = shearYieldStrength(material)
%SHEARYIELDSTRENGTH  Shear yield strength Fsy — supplied value or von Mises estimate.
%   r = engine.shearYieldStrength(material) resolves the shear yield
%   strength for a model.Material, in psi:
%     - Material.Fsy set (finite)  -> used as given (test/handbook data wins).
%     - Material.Fsy NaN, Fty set  -> ESTIMATED via NASA-STD-5020B Eq. 63:
%           Fsy = Fty / sqrt(3)
%       (von Mises: shear yielding occurs at 1/sqrt(3) ~ 0.577 of the
%       tensile yield stress — a constitutive assumption, not test data).
%
%   ⚠️ TWO DIFFERENT "Eq. 63" LIVE IN THIS ENGINE. NASA-STD-5020B Eq. 63 is
%   this one, Fsy = Fty/sqrt(3). NASA TM-106943 Eq. 63 is the BOLT
%   THREAD-SHEAR AREA, As = 5·pi·Le·D_minor,int/8 (engine.marginBoltThreadShear).
%   They are unrelated, they appear in neighbouring code, and both are
%   cited as "Eq. 63" — always name the document.
%     - Both NaN -> Fsy = NaN (the caller reports NotEvaluated).
%
%   WHERE THE EQUATION COMES FROM — corrected 2026-08-13. This function
%   used to cite only "the von Mises (distortion-energy) yield criterion"
%   as though 5020B printed no equation for it, and three callers stated
%   that no equation number was claimed. NASA-STD-5020B DOES print it, as
%   Eq. 63 on p66, Appendix A.8 ("Theoretical Treatment of Interaction
%   Equations"), derived there from Eq. 61 and Eq. 62. Under CLAUDE.md's
%   document hierarchy — "Where 5020B provides the equation, cite 5020B" —
%   citing prose while the standard prints the equation is exactly the
%   failure the rule exists to catch. Found by the 2026-08-13 equation
%   audit.
%
%   The REQUIREMENT to use a failure theory at all is separate, and both
%   citations belong together. NASA-STD-5020B §4.4.2, p31 (NOT p30, as
%   several call sites said): "Because shear yield strength is not a
%   standard material property, when evaluating the margin of safety under
%   yield design loads and performing combined loads analysis, the normal
%   and shear components of stress should be transformed into principal
%   stresses; and a failure theory (e.g., von Mises or Tresca) should be
%   used that is compatible with the concept of tensile yield strength."
%   So: §4.4.2 p31 is the authority to derive Fsy at all; A.8 Eq. 63 is
%   5020B's own printed form of the von Mises result.
%
%   TRESCA IS OFFERED EQUALLY BY THE STANDARD and would give Fsy = Fty/2
%   — about 13% lower, i.e. more conservative. This tool takes von Mises,
%   the less conservative of the two the standard names, because that is
%   the one 5020B itself derives and prints (Eq. 63); Tresca appears only
%   in the parenthetical list. The choice is recorded here rather than
%   left implicit, and Basis always says which relation produced a derived
%   Fsy so it can never pass as test data.
%
%   THE ESTIMATE MUST STAY VISIBLE: any margin computed from a derived Fsy
%   must carry r.Basis in its Detail/Method string so a reader can tell a
%   von-Mises estimate from a supplied allowable — unknown must never look
%   like fine. That visibility requirement is why this lives as ONE named
%   engine function called at the point of use (returning the Basis string
%   alongside the number) rather than as a Dependent property on
%   model.Material, which would resolve silently and make the estimate
%   invisible where the margin is formed.
%
%   Cross-checked against the reference tool's own data: A286 Fty 85.0 ksi
%   -> Fsy 49.1 ksi, and 300-series CRES Fty 30.0 ksi -> Fsy 17.3 ksi,
%   both matching Fty/sqrt(3) to the stored precision (tests/tThreadShear.m).
%
%   Returned struct fields:
%       Fsy      shear yield strength, psi (NaN when unresolvable)
%       Derived  logical: true when estimated as Fty/sqrt(3), false when
%                supplied (or unresolvable)
%       Basis    string for Detail/Method surfacing: says supplied vs
%                "estimated as Fty/sqrt(3) (von Mises)" with the number,
%                or why it is unavailable
%
%   Call graph:
%       Precedents (calls)      model.Material — a leaf; no engine.*
%                               dependencies.
%       Dependents (called by)  engine.marginInsert, engine.marginNutStrength.
%       Tests                   tests/tThreadShear.m —
%                               shearYieldSuppliedAndDerived (direct,
%                               supplied/derived/unavailable); exercised
%                               indirectly by nutDerivedFsyFlagged and
%                               insertAreaDerivedFsyFlagged.
%
%   Validation status/coverage: no dedicated VALIDATION.md row — the
%   cross-check above is kept in full rather than pointed at a row that
%   doesn't exist.

arguments
    material (1,1) model.Material
end

if ~isnan(material.Fsy)
    r = struct("Fsy", material.Fsy, "Derived", false, ...
        "Basis", string(sprintf("Fsy %.0f psi supplied (Material.Fsy)", ...
                                material.Fsy)));
    return
end

if isnan(material.Fty)
    r = struct("Fsy", NaN, "Derived", false, ...
        "Basis", "Fsy unavailable (Material.Fsy and Material.Fty both NaN)");
    return
end

% NASA-STD-5020B Eq. 63 — Fsy = Fty / sqrt(3)
%   Appendix A.8 derives it: Eq. 61 gives the principal stresses of a pure
%   shear state (S1 = 0, S2 = tau, S3 = -tau), Eq. 62 is the von Mises
%   criterion (S1-S2)^2 + (S2-S3)^2 + (S3-S1)^2 <= 2·Fty^2, and "Using
%   Eqs. 61 and 62 yields" Eq. 63.
Fsy = material.Fty / sqrt(3);
r = struct("Fsy", Fsy, "Derived", true, ...
    "Basis", string(sprintf( ...
        "Fsy %.0f psi estimated as Fty/sqrt(3) (NASA-STD-5020B Eq. 63, von Mises)", ...
        Fsy)));
end
