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
    %                                  Same numeric result as NotDeclared,
    %                                  reported as VERIFIED.
    %   ClearanceOrGapped            — the analyst has confirmed §4.4.4's
    %                                  exemption does NOT apply (clearance fit,
    %                                  or shear transferred across a gap or
    %                                  non-load-carrying spacer). With a moment
    %                                  supplied the criterion evaluates with
    %                                  bending in it; with none it reports
    %                                  NotEvaluated, because the analyst has
    %                                  said bending matters and given nothing
    %                                  to compute it from.
    %
    %   ⚠️ THIS SELECTS THE WORDING, NOT WHETHER A MOMENT IS USED. A supplied
    %   LoadCase.BoltBendingLimitMoment is included on EVERY value above.
    %   §4.4.4's exemption is scoped to bending "caused by the shear loading"
    %   (p33), so it justifies not DERIVING a shear-induced moment — it never
    %   justified discarding one the analyst handed over, which may come from
    %   prying, eccentric tension or flange rotation. CloseTolerance dropped
    %   a supplied moment until the 2026-08-13 equation audit.
    %
    %   Two things this doc claimed that were already false when written:
    %   bolt bending IS implemented (engine.private.boltBendingStress, since
    %   Phase 3.9 — there is an M*c/I, fbu = 32*Mbu/(pi*d^3)), and
    %   ClearanceOrGapped is not an unconditional NotEvaluated.
    enumeration
        NotDeclared
        CloseToleranceOrInterference
        ClearanceOrGapped
    end
end
