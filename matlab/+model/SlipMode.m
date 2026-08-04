classdef SlipMode
    %SLIPMODE  How the slip (friction) margin check is evaluated.
    %   SingleFastener — per-fastener slip using PER-BOLT limit loads
    %                    (NASA-STD-5020B Eq. 86). The DEFAULT.
    %   Joint          — joint-level slip: total friction capacity from all
    %                    nf bolts vs JOINT-TOTAL limit loads
    %                    (NASA-STD-5020B Eq. 84).
    %   Ignored        — slip check not evaluated (MS = NaN → NotEvaluated).
    %   Three modes only: the per-fastener and joint-level forms are the
    %   two distinct 5020B slip checks, and "Ignored" exists because a
    %   joint that is not relied on for friction should report no slip
    %   number at all rather than a misleading one.
    enumeration
        Ignored
        SingleFastener
        Joint
    end
end
