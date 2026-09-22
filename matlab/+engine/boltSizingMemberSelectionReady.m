function [ok, reason] = boltSizingMemberSelectionReady(memberType, nutSpec, memberMaterialChosen)
%BOLTSIZINGMEMBERSELECTIONREADY  Is a threaded-member selection complete?
%   [ok, reason] = engine.boltSizingMemberSelectionReady(memberType,
%   nutSpec, memberMaterialChosen) answers whether a Bolt Sizing
%   threaded-member picker is complete enough to sweep on, and says why not
%   when it is not.
%
%   Pure (model and data types in, no app state), so it is testable
%   without building a GUI. gui.BoltSizingPage is bolt-only and does not
%   use it; it is kept for a caller that offers a threaded-member picker.
%
%   memberType empty ("None (bolt-only)") is always ready -- the bolt-only
%   screen is a supported result, not an incomplete one.
%
%   Nut is ready only once a real family is chosen. Otherwise the caller
%   would have to either fall back to bolt-only without saying so, which
%   engine.boltSizingSweep's TensionUltBasis honesty requirement forbids,
%   or hand the engine a blank NutSpec, which it refuses outright
%   (engine:boltSizingSweep:missingNutSpec).
%
%   Insert and TappedHole are ready only once a member material is chosen,
%   mirroring Joint Config's own required-field rule for the same dropdown.

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
