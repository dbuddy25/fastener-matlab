function s = systemTensileAllowable(joint)
%SYSTEMTENSILEALLOWABLE  Allowable ultimate tensile load of the FASTENING SYSTEM.
%   s = engine.systemTensileAllowable(joint) returns Ptu-allow as
%   NASA-STD-5020B §4.4.1 defines it: "Ptu-allow is the allowable ultimate
%   load for the FASTENING SYSTEM" — not the bolt alone. The system fails
%   in tension at its weakest tensile mode, so
%       Ptu-allow = min over the system's tensile failure modes:
%           bolt tension               (spec-rated Joint.BoltRatedUltimateLoad,
%                                       else derived At*Ftu — boltTensileAllowable)
%           nut thread shear / rating  (Nut configuration)
%           insert pull-out            (Insert configuration)
%           tapped-hole parent thread  (TappedHole configuration)
%   The member-mode arithmetic is shared with the per-mode margin checks
%   via memberTensileUltAllowable (one implementation, identical numbers).
%   engine.marginTensionUlt consumes this Ptu-allow everywhere §4.4.1 uses
%   it:
%       NASA-STD-5020B Eq. 6  — MS = Ptu_allow/Ptu − 1 (separation before
%                               rupture), and the Fig. 8 preload gate
%                               PpMax <= 0.75·Ptu_allow (figure prints
%                               "<=", inclusive);
%       NASA-STD-5020B Eq. 10 — P'tu = (Ptu_allow − Pp_max)/(n·phi),
%                               MS = P'tu/Ptu − 1 (rupture governs).
%
%   INCOMPLETE ASSESSMENTS ARE REPORTED, NOT HIDDEN: a minimum can only be
%   taken over modes that produce a number. When an applicable mode cannot
%   be assessed (no engagement length, no member strength, no rating), the
%   returned minimum covers an INCOMPLETE set and is therefore OPTIMISTIC —
%   Complete is false, the mode is listed in Unassessed with its reason,
%   and Note says so plainly so the tension margin's Detail carries the
%   warning. PtuAllow is NaN only when NO mode at all can be assessed.
%
%   The bolt EXTERNAL-thread shear mode is deliberately NOT in this
%   minimum — a CLOSED decision, not an open question. NASA-STD-5020B
%   §4.7.4 handles thread stripping by DESIGN RULE, not by a computed
%   margin: it directs that thread engagement "should be selected to
%   ensure the minimum number of engaged complete threads such that the
%   fastener would fail in tension before threads would strip." Combined
%   with §4.4.1 directing spec ratings for procured items, and the fact
%   that 5020B prints no thread-shear-area equation anywhere, the standard
%   never asks for a computed thread-shear margin, so there is nothing to
%   fold into Ptu-allow. It is still carried as its own reported check
%   (engine.marginBoltThreadShear, governing via analyze()'s worst-margin
%   pick — a deliberate supplemental check beyond the standard, kept
%   because a computed stripping margin can only be more conservative than
%   the design rule; see engine.boltDesignLoad),
%   and for a procured nut §4.4.1 directs the spec rating — which
%   characterizes the assembly's stripping strength — rather than a
%   thread-stripping analysis.
%
%   Returned struct fields:
%     PtuAllow      system allowable ultimate tensile load, lbf (minimum
%                   over the ASSESSED modes; NaN if none could be assessed)
%     GoverningMode name of the mode that set the minimum ("" if none;
%                   ties go to the first-listed mode, the bolt)
%     Modes         struct array (Name, Allowable, Assessed, Note) — every
%                   mode applicable to this configuration
%     Unassessed    string array: applicable modes that could NOT be
%                   assessed (empty when Complete)
%     Complete      logical: true only if EVERY applicable mode was assessed
%     Note          one-line trace for Detail/Decision strings — names the
%                   governing mode and flags an incomplete assessment
%
%   Call graph:
%       Precedents (calls)      boltTensileAllowable, memberTensileUltAllowable
%                               (both private helpers, +engine/private/).
%       Dependents (called by)  separationBeforeRuptureGate (private helper).
%       Tests                   tests/tSystemAllowable.m —
%                               dabjSystemIsBoltGoverned / dabjAnswerKeyUnchanged
%                               (DABJ §9, bolt governs, COMPLETE),
%                               nutAreaGovernsSystem, nutRatingCapsSystem,
%                               insertGovernsSystem, tappedParentGovernsSystem
%                               (each member mode governing in turn),
%                               incompleteAssessmentFlagged (unassessable mode
%                               -> Complete=false, optimistic minimum reported),
%                               areaWithoutFsuIsNotSilentlyRated,
%                               noBoltRatingFallsBackToDerivedAllowable,
%                               noAllowableAtAllStaysNotEvaluated.
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, rows 1, 1r, 12
%   consume this as an input; no dedicated row of its own).

arguments
    joint (1,1) model.Joint
end

% ---- Mode 1: bolt tension ------------------------------------------------
% NASA-STD-5020B §4.4.1 / Eq. 6 — the bolt's allowable ultimate tensile
% load: the spec rating (joint.BoltRatedUltimateLoad) when set, else the
% derived Ptu_allow = At*Ftu (a derived convention, not a numbered 5020B
% equation — see boltTensileAllowable, shared with engine.marginTensionUlt
% via the Fig. 8 gate, engine.marginTensionYield, and engine.marginInteraction
% so all four sites agree on the basis and the number).
bt = boltTensileAllowable(joint);
if bt.Ult.Assessed
    modes = modeEntry("bolt tension", bt.Ult.Value, true, bt.Ult.Note);
else
    modes = modeEntry("bolt tension", NaN, false, bt.Ult.Reason);
end

% ---- Mode 2: the internal-thread member (nut / insert / tapped hole) -----
ua = memberTensileUltAllowable(joint);   % shared with the per-mode margin checks
if ua.Assessed
    if ua.Basis == "rated"
        note = string(sprintf("spec-rated %.0f lbf (no area basis; " + ...
            "5020B §4.4.1 rated strength)", ua.EffUlt));
    else   % "area"
        note = ua.AreaSrc + string(sprintf(", ultimate allowable %.0f lbf", ua.EffUlt));
        if strlength(ua.RatNote) > 0
            note = note + " (" + ua.RatNote + ")";
        end
    end
    modes(end+1) = modeEntry(ua.Mode, ua.EffUlt, true, note);
else
    modes(end+1) = modeEntry(ua.Mode, NaN, false, ua.Reason);
end

% ---- The system minimum --------------------------------------------------
% NASA-STD-5020B §4.4.1 — Ptu_allow = min over the fastening system's
% tensile failure modes (the weakest ASSESSED mode governs).
allows   = [modes.Allowable];
assessed = [modes.Assessed];
idx = find(assessed);
if isempty(idx)
    PtuAllow  = NaN;
    governing = "";
else
    [PtuAllow, k] = min(allows(idx));
    governing     = modes(idx(k)).Name;
end

unassessed = [modes(~assessed).Name];
if isempty(unassessed)
    unassessed = strings(1, 0);
end
complete = isempty(unassessed);

% ---- One-line trace for Detail / Decision --------------------------------
if isnan(PtuAllow)
    allDesc = strings(1, 0);
    for m = modes
        allDesc(end+1) = m.Name + ": " + m.Note; %#ok<AGROW>
    end
    noteStr = "no tensile failure mode of the fastening system could be assessed (" + ...
        strjoin(allDesc, "; ") + ")";
else
    % Each assessed mode's OWN Note (not just its number) so the governing
    % mode's basis — e.g. "spec-rated" vs "derived Ptu_allow = At*Ftu" for
    % bolt tension — reaches this one-line trace, and from there
    % engine.marginTensionUlt's Decision (a reader must never have to
    % guess whether Ptu_allow came from a rating or the derived fallback).
    assessedDesc = strings(1, 0);
    for m = modes(assessed)
        assessedDesc(end+1) = m.Name + ": " + m.Note; %#ok<AGROW>
    end
    noteStr = string(sprintf("system Ptu_allow %.0f lbf governed by %s [%s]", ...
        PtuAllow, governing, strjoin(assessedDesc, "; ")));
    if ~complete
        missDesc = strings(1, 0);
        for m = modes(~assessed)
            missDesc(end+1) = m.Name + " (" + m.Note + ")"; %#ok<AGROW>
        end
        noteStr = noteStr + ". INCOMPLETE ASSESSMENT — could not assess: " + ...
            strjoin(missDesc, "; ") + "; the minimum covers only the " + ...
            "assessable modes and may be OPTIMISTIC";
    end
end

% NOTE the cell wrapping: struct() replicates over array-valued fields, so
% the struct-array Modes and the (possibly empty / multi-element) string
% array Unassessed must be passed as scalar cells to keep s scalar.
s = struct( ...
    "PtuAllow",      PtuAllow, ...
    "GoverningMode", governing, ...
    "Modes",         {modes}, ...
    "Unassessed",    {unassessed}, ...
    "Complete",      complete, ...
    "Note",          noteStr);
end

% ---- Local helpers --------------------------------------------------------
function e = modeEntry(name, allowable, assessed, note)
%MODEENTRY  One tensile-failure-mode row of the fastening system.
e = struct( ...
    "Name",      string(name), ...
    "Allowable", allowable, ...
    "Assessed",  assessed, ...
    "Note",      string(note));
end
