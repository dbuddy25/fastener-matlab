classdef ShearTransferCondition
    %SHEARTRANSFERCONDITION  NASA-STD-5020B §4.4.4 bolt-bending exemption state.
    %   §4.4.4: "if shear is not transferred across gaps or non load carrying
    %   spacers, or if interference or close tolerance fits are used, then
    %   typically there is no need to account for bolt bending caused by the
    %   shear loading. However, if the shear is transferred across gaps or
    %   non load carrying spacers, or if there are clearances between the
    %   bolt and joint, interaction of loads, including non-negligible
    %   bending, should be considered."
    %
    %   NotDeclared                  — default; the analyst has not recorded
    %                                  which case applies. engine.marginInteraction
    %                                  still computes the fbu = 0 interaction
    %                                  criterion, but reports the §4.4.4
    %                                  exemption as ASSUMED, not verified.
    %   CloseToleranceOrInterference — the analyst has confirmed §4.4.4's
    %                                  exemption condition applies (interference
    %                                  or close-tolerance fit, no shear
    %                                  transferred across a gap or spacer).
    %                                  engine.marginInteraction computes exactly
    %                                  as NotDeclared, but reports the exemption
    %                                  as VERIFIED.
    %   ClearanceOrGapped            — the analyst has confirmed §4.4.4's
    %                                  exemption does NOT apply (clearance fit,
    %                                  or shear transferred across a gap or
    %                                  non-load-carrying spacer). Bolt bending
    %                                  is not implemented (no fbu term anywhere
    %                                  in this tool — see TOOL_DIFFERENCES.md
    %                                  §7.4), so engine.marginInteraction
    %                                  cannot evaluate the criterion
    %                                  conservatively for this configuration
    %                                  and reports NotEvaluated instead.
    %   This enum does not compute bending stress (no M*c/I anywhere) — it
    %   only turns the §4.4.4 exemption from a silent global assumption into
    %   an explicit, per-joint, recorded determination.
    enumeration
        NotDeclared
        CloseToleranceOrInterference
        ClearanceOrGapped
    end
end
