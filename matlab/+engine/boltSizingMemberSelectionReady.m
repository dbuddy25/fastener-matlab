function [ok, reason] = boltSizingMemberSelectionReady(memberType, nutSpec, memberMaterialChosen)
%BOLTSIZINGMEMBERSELECTIONREADY  Is a threaded-member selection complete?
%   [ok, reason] = engine.boltSizingMemberSelectionReady(memberType,
%   nutSpec, memberMaterialChosen) answers whether a Bolt Sizing
%   threaded-member picker is complete enough to sweep on, and says why not
%   when it is not.
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
%   memberType empty ("None (bolt-only)") is always ready -- the bolt-only
%   screen is a supported result, not an incomplete one.
%
%   Nut is ready only once a real family is chosen. Otherwise the caller
%   would have to either fall back to bolt-only WITHOUT SAYING SO -- which
%   engine.boltSizingSweep's TensionUltBasis honesty requirement forbids --
%   or hand the engine a blank NutSpec, which it refuses outright
%   (engine:boltSizingSweep:missingNutSpec).
%
%   Insert and TappedHole are ready only once a member material is chosen,
%   mirroring Joint Config's own required-field rule for the same dropdown.
%
%   Call graph:
%       Precedents (calls)      none (pure).
%       Dependents (called by)  a Bolt Sizing UI, when one exists.
%       Tests                   tests/tBoltSizingMemberArgs.m.

arguments
    memberType           (1,:) model.ThreadedMemberType
    nutSpec              (1,1) string  = ""
    memberMaterialChosen (1,1) logical = false
end
if isempty(memberType)
    ok = true;
    reason = "";
elseif memberType == model.ThreadedMemberType.Nut
    if strlength(strtrim(nutSpec)) > 0
        ok = true;
        reason = "";
    else
        ok = false;
        reason = "Choose a nut spec for the threaded-member context (or switch Threaded member to None).";
    end
else
    if memberMaterialChosen
        ok = true;
        reason = "";
    else
        ok = false;
        reason = "Choose a member material for the Insert/Tapped Hole template (or switch Threaded member to None).";
    end
end
end
