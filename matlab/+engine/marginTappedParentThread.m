function r = marginTappedParentThread(joint, loadCase, factors, preload)
%MARGINTAPPEDPARENTTHREAD  Tapped-hole parent-material thread shear margin.
%   r = engine.marginTappedParentThread(joint, loadCase, factors, preload)
%   checks shear failure (stripping) of the PARENT material's internal
%   threads in a tapped-hole joint — the check that governs when a strong
%   bolt threads into a soft parent (e.g. A-286 into aluminum). Only
%   evaluated when joint.ThreadedMember.Type == TappedHole; otherwise
%   MS = NaN (NotEvaluated). preload is the struct from engine.preload.
%   Loads in lbf, lengths in inches, strengths in psi (see UNITS.md).
%
%   THE GROUP'S METHOD (deliberate): internal-thread shear area in the
%   pitch-diameter form used by the group's practice,
%       As = 0.75·pi·E·Le
%   with E = thread pitch diameter (joint.Bolt.PitchDiameter) and
%   Le = engagement length (joint.ThreadedMember.EngagementLength — the
%   tapped thread depth). NASA-STD-5020B prints no thread-shear-area
%   equation; the working reference is NASA TM-106943 (Chambers), whose
%   Eq. 79 gives the tapped-parent pull-out strength Pult = Fsu·As (the
%   group supplies the 0.75·pi·E·Le area; TM's own Eq. 78/79 area uses a
%   5/8 coefficient, and DABJ §6 uses the H28 tolerance form with a
%   judgment knockdown — see the validation note below). Then:
%       Pult = Fsu·As            (TM-106943 Eq. 79)
%       MS   = Pult/Pb - 1       (TM-106943 Eq. 65 MS form)
%   with Fsu = joint.ThreadedMember.Material.Fsu (the PARENT material) and
%       Pb = PpMax + FFU·FSU·n·phi·PtL     (NASA-STD-5020B Eq. 8 form,
%   via engine.boltDesignLoad — phi = 1 assumed for this threaded-in
%   configuration; conservative).
%
%   VALIDATION (DABJ Example 6-a, pp. 6-6..6-8): #10-32 A-286 screw fully
%   engaged in 0.250-in 6061-T651 plate. DABJ's tolerance-extreme internal
%   shear area Asi-min = 0.0986 in^2 and allowable 27,000·0.0986 = 2,660 lb;
%   this function's 0.75·pi·0.1697·0.250 = 0.0999 in^2 and 2,698 lb agree
%   within 1.5%. DABJ then applies a 0.70 judgment knockdown (-> 1,860 lb);
%   the GROUP'S METHOD DOES NOT KNOCK DOWN — the cross-check is against the
%   un-knocked area/allowable (tests/tThreadShear.m).
%
%   NotEvaluated (MS = NaN) when the configuration is not a tapped hole,
%   when PitchDiameter / EngagementLength / parent Fsu is NaN, or when Pb
%   cannot be computed — reason in Detail; never crashes.
%
%   Returned struct fields:
%       MS      margin of safety (NaN = not evaluated)
%       Method  string: governing equation citation
%       Detail  string: the numbers used (or the not-evaluated reason)
%       As      thread-shear area 0.75·pi·E·Le, in^2 (NaN if not evaluated)
%       Pult    parent thread-shear allowable Fsu·As, lbf (NaN if not evaluated)
%       Pb      design bolt load, lbf (NaN if not computable)

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "TM-106943 Eq. 79 (tapped-hole parent thread shear) via the group's As = 0.75·pi·E·Le pitch-diameter form + Eq. 65 MS; Pb per NASA-STD-5020B Eq. 8";

if joint.ThreadedMember.Type ~= model.ThreadedMemberType.TappedHole
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: threaded member is not a tapped hole (" + ...
                  string(joint.ThreadedMember.Type) + ").", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

E   = joint.Bolt.PitchDiameter;               % thread pitch diameter, in
Le  = joint.ThreadedMember.EngagementLength;  % tapped thread engagement (depth), in
Fsu = joint.ThreadedMember.Material.Fsu;      % PARENT-material ultimate shear strength, psi
if isnan(E) || isnan(Le) || isnan(Fsu)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: needs Bolt.PitchDiameter, ThreadedMember.EngagementLength, and the parent Material.Fsu (one or more NaN).", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

% Group pitch-diameter thread-shear area — As = 0.75·pi·E·Le
As = 0.75 * pi * E * Le;                      % parent internal-thread shear area, in^2
% TM-106943 Eq. 79 — Pult = Fsu·As (parent pull-out strength)
Pult = Fsu * As;                              % lbf

d = engine.boltDesignLoad(joint, loadCase, factors, preload);  % NASA-STD-5020B Eq. 8 — Pb = PpMax + FFU·FSU·n·phi·PtL
if isnan(d.Pb)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: " + d.Note + ".", ...
        "As", As, "Pult", Pult, "Pb", NaN);
    return
end

% TM-106943 Eq. 65 MS form — MS = Pult/Pb - 1
MS = Pult / d.Pb - 1;

detail = string(sprintf("E %.4f in, Le %.3f in, As %.4f in^2, Pult %.0f lbf, Pb %.0f lbf", ...
    E, Le, As, Pult, d.Pb));
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end
r = struct("MS", MS, "Method", method, "Detail", detail + ".", ...
    "As", As, "Pult", Pult, "Pb", d.Pb);
end
