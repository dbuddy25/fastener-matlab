function s = systemTensileYieldAllowable(joint)
%SYSTEMTENSILEYIELDALLOWABLE  Allowable YIELD tensile load of the FASTENING SYSTEM.
%   s = engine.systemTensileYieldAllowable(joint) returns Pty-allow as
%   NASA-STD-5020B §4.4.2 defines it — the yield counterpart of
%   engine.systemTensileAllowable, and the term NASA-STD-5020B Eq. 17
%   actually names. The governing citation is the GLOBAL SYMBOL LIST, p13:
%     P'ty — "the applied tensile load that causes the fastener load to
%             exceed the FASTENING SYSTEM'S allowable yield tensile load,
%             if yielding occurs before separation"
%   Eq. 17 computes P'ty, so the Pty_allow inside it must be the system's
%   or the equation does not produce the quantity the standard defines it
%   to be. p13 defines P'tu the same way for the ultimate side, where
%   §4.4.1 p27 independently confirms the pairing — see
%   engine.marginTensionYield's header for the full argument, including
%   why §4.4.2 p30's "of the material" where-clause and p29's "all
%   elements" sentence do NOT settle it either way.
%   So, exactly as on the ultimate side,
%       Pty-allow = min over the system's tensile YIELD modes:
%           bolt yield                 (spec-rated Joint.BoltRatedYieldLoad,
%                                       else NASA-STD-5020B Eq. 18
%                                       Pty_allow = (Fty/Ftu)*Ptu_allow —
%                                       boltTensileAllowable)
%           nut / insert / tapped-hole thread shear at yield
%                                      (As*Fsy — memberTensileYldAllowable)
%   engine.marginTensionYield consumes this everywhere §4.4.2 uses
%   Pty-allow:
%       NASA-STD-5020B Eq. 15 — MS = Pty_allow/Pty - 1 (separation before
%                               yield);
%       NASA-STD-5020B Eq. 17 — P'ty = (1/(n*phi))*(Pty_allow - Pp_max),
%                               then Eq. 16 MS = P'ty/Pty - 1 (yield before
%                               separation).
%
%   WHY THIS EXISTS SEPARATELY FROM systemTensileAllowable. The two minima
%   are over DIFFERENT numbers and can be governed by different modes: a
%   spec rating is an ultimate quantity, so a rated-only member has an
%   ultimate mode and NO yield mode at all (memberTensileYldAllowable rule
%   2), while a member with an engagement area has both. Folding them into
%   one function would need a flag on every field; two functions with the
%   same shape is how the per-mode rows already do it.
%
%   INCOMPLETE ASSESSMENTS ARE REPORTED, NOT HIDDEN — same contract, same
%   wording, as engine.systemTensileAllowable. A minimum can only be taken
%   over modes that produce a number, so when an applicable mode cannot be
%   assessed the minimum covers an INCOMPLETE set and is therefore
%   OPTIMISTIC: Complete is false, the mode is listed in Unassessed with
%   its reason, and Note says so plainly. This fires MORE often here than
%   on the ultimate side, and that is the point: a rated nut or insert
%   (DABJ §9's, for one) carries no yield information whatsoever, so the
%   yield minimum genuinely IS bolt-only there, and the analyst is told so
%   instead of the tool implying the member was checked.
%   PtyAllow is NaN only when NO mode at all can be assessed.
%
%   The bolt EXTERNAL-thread shear mode is deliberately NOT in this
%   minimum, for the same CLOSED reason it is absent from the ultimate
%   system allowable — NASA-STD-5020B §4.7.4 handles thread stripping by
%   DESIGN RULE, not by a computed margin. See
%   engine.systemTensileAllowable's header for the full argument; it is not
%   restated here so the two cannot drift apart.
%
%   Returned struct fields (identical shape to engine.systemTensileAllowable,
%   so a caller can treat the two interchangeably):
%     PtyAllow      system allowable yield tensile load, lbf (minimum over
%                   the ASSESSED modes; NaN if none could be assessed)
%     GoverningMode name of the mode that set the minimum ("" if none;
%                   ties go to the first-listed mode, the bolt)
%     Modes         struct array (Name, Allowable, Assessed, Note) — every
%                   mode applicable to this configuration
%     Unassessed    string array: applicable modes that could NOT be
%                   assessed (empty when Complete)
%     Complete      logical: true only if EVERY applicable mode was assessed
%     Note          one-line trace for Detail strings — names the governing
%                   mode and flags an incomplete assessment
%
%   Call graph:
%       Precedents (calls)      boltTensileAllowable, memberTensileYldAllowable
%                               (both private helpers, +engine/private/).
%       Dependents (called by)  engine.marginTensionYield.
%       Tests                   tests/tSystemAllowable.m —
%                               dabjYieldSystemBoltGovernedButIncomplete
%                               (DABJ §9: rated nut has no yield mode, so
%                               the minimum is bolt-only AND flagged),
%                               nutYieldGovernsSystem, insertYieldGovernsSystem,
%                               tappedHoleYieldModeAssessed,
%                               ratedOnlyMemberYieldUnassessedFlagged,
%                               noYieldModeAtAllNotEvaluated,
%                               derivedFsyFlagSurvivesIntoSystemNote.
%
%   Validation status/coverage: see VALIDATION.md (Margin checks, rows 2, 2r
%   consume this as an input, plus the hand-derived member-governed row).

arguments
    joint (1,1) model.Joint
end

% ---- Mode 1: bolt yield --------------------------------------------------
% NASA-STD-5020B §4.4.2 / Eq. 18 — the bolt's allowable yield tensile load:
% the spec rating (joint.BoltRatedYieldLoad) when set, else the Eq. 18
% estimate Pty_allow = (Fty/Ftu)*Ptu_allow applied to whichever ultimate
% allowable is actually in use. Resolved by the SAME helper the ultimate
% system allowable, engine.marginTensionYield and engine.marginInteraction
% use, so every site agrees on the basis and the number.
bt = boltTensileAllowable(joint);
if bt.Yld.Assessed
    modes = modeEntry("bolt yield", bt.Yld.Value, true, bt.Yld.Note);
else
    modes = modeEntry("bolt yield", NaN, false, bt.Yld.Reason);
end

% ---- Mode 2: the internal-thread member (nut / insert / tapped hole) -----
% AllowYld = As*Fsy, shared with the per-mode margin checks' own yield
% criteria via memberTensileYldAllowable — one implementation, so the row
% and this minimum can never disagree about which area source governed or
% whether Fsy was supplied or derived.
ya = memberTensileYldAllowable(joint);
if ya.Assessed
    note = ya.AreaSrc + string(sprintf(", yield allowable %.0f lbf", ya.AllowYld));
    if strlength(ya.FsyBasis) > 0
        % The von Mises fallback must stay visible: a derived Fsy is never
        % allowed to pass as test data. §4.4.2 p31 sanctions deriving it;
        % NASA-STD-5020B Eq. 63 (p66, A.8) prints Fsy = Fty/sqrt(3).
        note = note + " (" + ya.FsyBasis + ")";
    end
    modes(end+1) = modeEntry(ya.Mode, ya.AllowYld, true, note);
else
    modes(end+1) = modeEntry(ya.Mode, NaN, false, ya.Reason);
end

% ---- The system minimum --------------------------------------------------
% NASA-STD-5020B §4.4.2 — Pty_allow = min over the fastening system's
% tensile yield modes (the weakest ASSESSED mode governs).
allows   = [modes.Allowable];
assessed = [modes.Assessed];
idx = find(assessed);
if isempty(idx)
    PtyAllow  = NaN;
    governing = "";
else
    [PtyAllow, k] = min(allows(idx));
    governing     = modes(idx(k)).Name;
end

unassessed = [modes(~assessed).Name];
if isempty(unassessed)
    unassessed = strings(1, 0);
end
complete = isempty(unassessed);

% ---- One-line trace for Detail -------------------------------------------
if isnan(PtyAllow)
    allDesc = strings(1, 0);
    for m = modes
        allDesc(end+1) = m.Name + ": " + m.Note; %#ok<AGROW>
    end
    noteStr = "no tensile yield mode of the fastening system could be assessed (" + ...
        strjoin(allDesc, "; ") + ")";
else
    % Each assessed mode's OWN Note (not just its number), so the governing
    % mode's basis — spec-rated vs the Eq. 18 estimate for the bolt, the
    % area source and Fsy basis for the member — reaches this one-line
    % trace and from there engine.marginTensionYield's Detail. A reader
    % must never have to guess where Pty_allow came from.
    assessedDesc = strings(1, 0);
    for m = modes(assessed)
        assessedDesc(end+1) = m.Name + ": " + m.Note; %#ok<AGROW>
    end
    noteStr = string(sprintf("system Pty_allow %.0f lbf governed by %s [%s]", ...
        PtyAllow, governing, strjoin(assessedDesc, "; ")));
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
    "PtyAllow",      PtyAllow, ...
    "GoverningMode", governing, ...
    "Modes",         {modes}, ...
    "Unassessed",    {unassessed}, ...
    "Complete",      complete, ...
    "Note",          noteStr);
end

% ---- Local helpers --------------------------------------------------------
function e = modeEntry(name, allowable, assessed, note)
%MODEENTRY  One tensile-yield-mode row of the fastening system.
e = struct( ...
    "Name",      string(name), ...
    "Allowable", allowable, ...
    "Assessed",  assessed, ...
    "Note",      string(note));
end
