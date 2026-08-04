function r = shearYieldStrength(material)
%SHEARYIELDSTRENGTH  Shear yield strength Fsy — supplied value or von Mises estimate.
%   r = engine.shearYieldStrength(material) resolves the shear yield
%   strength for a model.Material, in psi:
%     - Material.Fsy set (finite)  -> used as given (test/handbook data wins).
%     - Material.Fsy NaN, Fty set  -> ESTIMATED from the von Mises
%       (distortion-energy) yield criterion:
%           Fsy = Fty / sqrt(3)
%       (von Mises: shear yielding occurs at 1/sqrt(3) ~ 0.577 of the
%       tensile yield stress — a constitutive assumption, not test data).
%     - Both NaN -> Fsy = NaN (the caller reports NotEvaluated).
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

% von Mises (distortion-energy) yield criterion — Fsy = Fty / sqrt(3)
Fsy = material.Fty / sqrt(3);
r = struct("Fsy", Fsy, "Derived", true, ...
    "Basis", string(sprintf("Fsy %.0f psi estimated as Fty/sqrt(3) (von Mises)", ...
                            Fsy)));
end
