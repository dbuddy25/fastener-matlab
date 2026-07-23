function r = marginNutStrength(joint, loadCase, factors, preload)
%MARGINNUTSTRENGTH  Nut internal-thread shear margin (Nut configuration only).
%   r = engine.marginNutStrength(joint, loadCase, factors, preload) checks
%   shear failure of the NUT's internal threads — the internal side of the
%   thread-stripping pair (the bolt-external side is
%   engine.marginBoltThreadShear; the weaker side governs via analyze()'s
%   worst-margin pick). Only evaluated when
%   joint.ThreadedMember.Type == Nut; otherwise MS = NaN (NotEvaluated).
%   preload is the struct from engine.preload. Loads in lbf, lengths in
%   inches, strengths in psi (see UNITS.md).
%
%   THE GROUP'S METHOD (deliberate): internal-thread shear area in the
%   pitch-diameter form used by the group's practice,
%       As = 0.75·pi·E·Le
%   with E = thread pitch diameter (joint.Bolt.PitchDiameter) and
%   Le = engagement length (joint.ThreadedMember.EngagementLength — the
%   nut thread height). This is NASA TM-106943 (Chambers) Eq. 76's
%   internal-thread shear area (3/4·pi coefficient) with the group's
%   pitch-diameter substitution (TM's printed Eq. 76 uses the mating
%   external-thread MAJOR diameter). NASA-STD-5020B prints no
%   thread-shear-area equation. Then, per TM-106943 Eq. 77 + Eq. 65:
%       Pult = Fsu·As            (Eq. 77)
%       MS   = Pult/Pb - 1       (Eq. 65 MS form)
%   with Fsu = joint.ThreadedMember.Material.Fsu (the NUT material) and
%       Pb = PpMax + FFU·FSU·n·phi·PtL     (NASA-STD-5020B Eq. 8 form,
%   via engine.boltDesignLoad).
%
%   NOTE: this material-based thread-shear check complements (does not
%   replace) the spec-rated nut Pult carried on
%   joint.ThreadedMember.RatedUltimateLoad (NASA-STD-5020B §4.2.2.8),
%   which the DABJ §9 case uses via BoltRatedUltimateLoad ("nuts as strong
%   as the bolts").
%
%   NotEvaluated (MS = NaN) when the configuration is not a nut, when
%   PitchDiameter / EngagementLength / nut Fsu is NaN, or when Pb cannot
%   be computed — reason in Detail; never crashes.
%
%   Returned struct fields:
%       MS      margin of safety (NaN = not evaluated)
%       Method  string: governing equation citation
%       Detail  string: the numbers used (or the not-evaluated reason)
%       As      thread-shear area 0.75·pi·E·Le, in^2 (NaN if not evaluated)
%       Pult    thread-shear allowable Fsu·As, lbf (NaN if not evaluated)
%       Pb      design bolt load, lbf (NaN if not computable)
%
%   Pinned by HAND-DERIVED arithmetic in tests/tThreadShear.m
%   (nutStrengthHandDerived).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "TM-106943 Eq. 76 (nut internal thread shear) via the group's As = 0.75·pi·E·Le pitch-diameter form + Eq. 77 allowable, Eq. 65 MS; Pb per NASA-STD-5020B Eq. 8";

if joint.ThreadedMember.Type ~= model.ThreadedMemberType.Nut
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: threaded member is not a nut (" + ...
                  string(joint.ThreadedMember.Type) + ").", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

E   = joint.Bolt.PitchDiameter;               % thread pitch diameter, in
Le  = joint.ThreadedMember.EngagementLength;  % nut thread engagement, in
Fsu = joint.ThreadedMember.Material.Fsu;      % NUT-material ultimate shear strength, psi
if isnan(E) || isnan(Le) || isnan(Fsu)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: needs Bolt.PitchDiameter, ThreadedMember.EngagementLength, and the nut Material.Fsu (one or more NaN).", ...
        "As", NaN, "Pult", NaN, "Pb", NaN);
    return
end

% TM-106943 Eq. 76, group pitch-diameter form — As = 0.75·pi·E·Le
As = 0.75 * pi * E * Le;                      % internal-thread shear area, in^2
% TM-106943 Eq. 77 — Pult = Fsu·As
Pult = Fsu * As;                              % nut thread-shear allowable, lbf

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
