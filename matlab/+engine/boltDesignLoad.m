function r = boltDesignLoad(joint, loadCase, factors, preload)
%BOLTDESIGNLOAD  Bolt tensile design load Pb for the thread-strength checks.
%   r = engine.boltDesignLoad(joint, loadCase, factors, preload) computes
%   the design bolt load the Phase 3.3 thread checks (bolt-thread shear,
%   nut strength, insert pull-out, tapped-hole parent thread) compare their
%   allowables against:
%
%       Pb = PpMax + FFU·FSU·n·phi·PtL       (NASA-STD-5020B Eq. 8 form)
%
%   where PpMax is the max in-service preload (engine.preload), n is
%   joint.LoadingPlaneFactor, phi = kb/(kb+kc) is the stiffness factor
%   (NASA-STD-5020B Eq. 9, from engine.stiffness), and PtL is
%   loadCase.BoltTensileLimitLoad. The FFU·FSU ultimate factors multiply
%   only the EXTERNAL-load term (preload is not factored) — this is the
%   group's thread-check design load; note engine.marginBearingUnderHead
%   deliberately uses the more conservative whole-Pb-factored convention.
%
%   phi handling (the stiffness call is wrapped, never allowed to crash):
%     - Through-bolt (Nut) configuration: phi from engine.stiffness. If the
%       frustum geometry is missing (HeadBearingDiameter, BodyLengthInGrip,
%       ...), Pb = NaN and Note carries the reason — the caller reports
%       NotEvaluated.
%     - Threaded-in configuration (Insert / TappedHole): engine.stiffness
%       defers that frustum form, so phi = 1 is assumed — CONSERVATIVE,
%       since phi = kb/(kb+kc) <= 1 means the full external load is charged
%       to the bolt. Note says so. (Without this, the insert and
%       tapped-hole checks could never evaluate.)
%
%   Returned struct fields:
%       Pb    design bolt load, lbf (NaN = not computable; see Note)
%       Phi   stiffness factor used (1 for the threaded-in assumption;
%             NaN when Pb is NaN)
%       Note  string: "" normally; the phi = 1 assumption note; or the
%             reason Pb is NaN
%
%   All loads in lbf (see UNITS.md).

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

PtL = loadCase.BoltTensileLimitLoad;   % most-loaded-bolt tensile limit load, lbf
if isnan(PtL)
    r = struct("Pb", NaN, "Phi", NaN, ...
        "Note", "bolt tensile limit load undefined (NaN)");
    return
end

% ---- Stiffness factor phi (NASA-STD-5020B Eq. 9) -------------------------
try
    s    = engine.stiffness(joint);    % errors for threaded-in / missing geometry
    phi  = s.Phi;
    note = "";
catch stiffErr
    if strcmp(stiffErr.identifier, "engine:stiffness:threadedInDeferred")
        % Threaded-in (insert/tapped) frustum is deferred in engine.stiffness;
        % assume phi = 1 — conservative, phi = kb/(kb+kc) <= 1 always.
        phi  = 1;
        note = "phi = 1 assumed (threaded-in stiffness deferred; conservative since phi <= 1)";
    else
        r = struct("Pb", NaN, "Phi", NaN, ...
            "Note", "Pb needs phi from engine.stiffness, which could not run: " + ...
                    string(stiffErr.message));
        return
    end
end

% ---- Design bolt load ----------------------------------------------------
% NASA-STD-5020B Eq. 8 — Pb = PpMax + FFU·FSU·n·phi·PtL (design bolt load
% for the thread checks; ultimate factors on the external term only)
Pb = preload.PpMax + factors.FFU * factors.FSU * joint.LoadingPlaneFactor * phi * PtL;

r = struct("Pb", Pb, "Phi", phi, "Note", string(note));
end
