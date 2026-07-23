function r = marginBoltThreadShear(joint, loadCase, factors, preload)
%MARGINBOLTTHREADSHEAR  Bolt external-thread shear (pull-out) margin.
%   r = engine.marginBoltThreadShear(joint, loadCase, factors, preload)
%   checks shear failure of the BOLT's external threads over the engaged
%   length — the bolt-side of the thread-stripping pair (the mating
%   internal-thread side is engine.marginNutStrength or
%   engine.marginTappedParentThread; the weaker side governs via
%   analyze()'s worst-margin pick). preload is the struct from
%   engine.preload. Loads in lbf, lengths in inches, strengths in psi
%   (see UNITS.md).
%
%   THE GROUP'S METHOD (deliberate): the thread-shear area is the
%   pitch-diameter form used by the group's practice,
%       As = 0.75·pi·E·Le
%   with E = thread pitch diameter (joint.Bolt.PitchDiameter) and
%   Le = engagement length (joint.ThreadedMember.EngagementLength).
%   This is NASA TM-106943 (Chambers) Eq. 63's external-thread shear area
%   with the group's 3/4 coefficient and pitch-diameter substitution (TM's
%   printed Eq. 63 uses 5/8·pi·d_minor,int·Le; the 3/4·pi coefficient is
%   TM Eq. 76's internal-thread form — the group applies 0.75·pi·E·Le to
%   BOTH sides). NASA-STD-5020B prints no thread-shear-area equation.
%   Then, per TM-106943 Eq. 64/65:
%       Pult = Fsu·As            (Eq. 64)
%       MS   = Pult/Pb - 1       (Eq. 65)
%   with Fsu = joint.BoltMaterial.Fsu and the design bolt load
%       Pb = PpMax + FFU·FSU·n·phi·PtL     (NASA-STD-5020B Eq. 8 form,
%   via engine.boltDesignLoad — see its help for the phi handling).
%
%   NotEvaluated (MS = NaN) when PitchDiameter, EngagementLength, or the
%   bolt Fsu is NaN, or when Pb cannot be computed (missing stiffness
%   geometry) — the reason is in Detail; never crashes.
%
%   Returned struct fields:
%       MS      margin of safety (NaN = not evaluated)
%       Method  string: governing equation citation
%       Detail  string: the numbers used (or the not-evaluated reason)
%       As      thread-shear area 0.75·pi·E·Le, in^2 (NaN if inputs missing)
%       Pult    thread-shear allowable Fsu·As, lbf (NaN if inputs missing)
%       Pb      design bolt load, lbf (NaN if not computable)
%
%   No public worked example works the bolt-external side with this area
%   form; pinned by HAND-DERIVED arithmetic in tests/tThreadShear.m
%   (boltThreadShearHandDerived).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "TM-106943 Eq. 63 (bolt thread shear) via the group's As = 0.75·pi·E·Le pitch-diameter form + Eq. 64/65 MS; Pb per NASA-STD-5020B Eq. 8";

E   = joint.Bolt.PitchDiameter;               % thread pitch diameter, in
Le  = joint.ThreadedMember.EngagementLength;  % thread engagement, in
Fsu = joint.BoltMaterial.Fsu;                 % bolt-material ultimate shear strength, psi
if isnan(E) || isnan(Le) || isnan(Fsu)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: needs Bolt.PitchDiameter, ThreadedMember.EngagementLength, and BoltMaterial.Fsu (one or more NaN).", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

% TM-106943 Eq. 63, group pitch-diameter form — As = 0.75·pi·E·Le
As = 0.75 * pi * E * Le;                      % external-thread shear area, in^2
% TM-106943 Eq. 64 — Pult = Fsu·As
Pult = Fsu * As;                              % thread-shear allowable, lbf

d = engine.boltDesignLoad(joint, loadCase, factors, preload);  % NASA-STD-5020B Eq. 8 — Pb = PpMax + FFU·FSU·n·phi·PtL
if isnan(d.Pb)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: " + d.Note + ".", ...
        "As", As, "Pult", Pult, "Pb", NaN);
    return
end

% TM-106943 Eq. 65 — MS = Pult/Pb - 1
MS = Pult / d.Pb - 1;

detail = string(sprintf("E %.4f in, Le %.3f in, As %.4f in^2, Pult %.0f lbf, Pb %.0f lbf", ...
    E, Le, As, Pult, d.Pb));
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end
r = struct("MS", MS, "Method", method, "Detail", detail + ".", ...
    "As", As, "Pult", Pult, "Pb", d.Pb);
end
