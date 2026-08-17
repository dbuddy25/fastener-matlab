function nvArgs = boltSizingMemberArgs(memberType, library, nutSpec, member)
%BOLTSIZINGMEMBERARGS  A threaded-member selection -> boltSizingSweep args.
%   nvArgs = engine.boltSizingMemberArgs(memberType, library, nutSpec, member)
%   translates a Bolt Sizing threaded-member selection into the name-value
%   pairs engine.boltSizingSweep's optional threaded-member context expects.
%   ONE place that translation happens, so a caller stays a thin
%   orchestration call that cannot drift from what this returns.
%
%   MOVED OUT OF gui.FastenerApp AT GUI STEP 10, logic unchanged. It was a
%   static method on the first-pass GUI class, which step 10 deletes. Its
%   inputs were always model and data types rather than widgets, its own
%   docstring already called it "Pure (no app state) -- testable without
%   building the GUI", and what it produces is consumed by
%   engine.boltSizingSweep -- so the engine is where it belonged.
%
%   GUI2_SPEC.md Sec. 3 records that Bolt Sizing is deliberately NOT built in
%   +gui2 and that the engine sweep "stays in the engine, untouched and
%   re-addable". Keeping this mapping (and the assertions in
%   tests/tBoltSizingMemberArgs.m) alive is most of what makes that true:
%   without it, re-adding the tab means rediscovering which selection maps
%   to which sweep argument, which is the part that is easy to get wrong.
%
%   memberType empty (model.ThreadedMemberType.empty(1,0), the picker's
%   "None (bolt-only)" selection) -> {} : the bolt-only call shape.
%   Nut               -> {'Library', library, 'NutSpec', nutSpec}
%   Insert            -> {'ThreadedMember', member, 'Library', library}
%   TappedHole        -> {'ThreadedMember', member}
%   with member.Type FORCED to memberType in the latter two, so the Type is
%   decided in exactly one place.
%
%   THIS IS THE CODE THAT KEEPS A NUT OFF THE TEMPLATE BRANCH.
%   engine.boltSizingSweep REJECTS a ThreadedMember template whose Type is
%   Nut -- a nut varies by thread size, so it must come through
%   Library + NutSpec instead. The switch below routes Nut one way and
%   everything else the other, so the two paths can never cross.
%
%   Call graph:
%       Precedents (calls)      none (pure).
%       Dependents (called by)  a Bolt Sizing UI, when one exists. None
%                               today -- +gui2 does not build that tab.
%       Tests                   tests/tBoltSizingMemberArgs.m.

arguments
    memberType (1,:) model.ThreadedMemberType
    library    (1,:) data.Library         = data.Library.empty(1, 0)
    nutSpec    (1,1) string                = ""
    member     (1,:) model.ThreadedMember  = model.ThreadedMember.empty(1, 0)
end
if isempty(memberType)
    nvArgs = {};
    return
end
if memberType == model.ThreadedMemberType.Nut
    nvArgs = {'Library', library, 'NutSpec', nutSpec};
elseif memberType == model.ThreadedMemberType.Insert
    % Insert needs BOTH. The template carries the joint design
    % choices (material, rated load, engagement ratio, shear
    % area), but StiPitchDiameter is catalogue geometry that
    % varies by thread size, so engine.boltSizingSweep resolves
    % it per row from Library.insertFor -- which it can only do
    % if the Library actually reaches it. Without this the sweep
    % silently loses the computed-area basis on every row AND
    % reports "no insert is catalogued for this thread size",
    % which would be a lie about the cause. The engine's guards
    % permit Library alongside a template; only NutSpec and
    % ThreadedMember are mutually exclusive.
    member.Type = memberType;
    nvArgs = {'ThreadedMember', member, 'Library', library};
else
    % TappedHole: no catalogue exists for a tapped parent, so
    % there is nothing for a Library to resolve.
    member.Type = memberType;
    nvArgs = {'ThreadedMember', member};
end
end
