classdef SlipMode
    %SLIPMODE  How the slip (friction) margin check is evaluated.
    %   SingleFastener — per-fastener slip using PER-BOLT limit loads
    %                    (NASA-STD-5020B Eq. 86). The DEFAULT.
    %   Joint          — joint-level slip: total friction capacity from all
    %                    nf bolts vs JOINT-TOTAL limit loads
    %                    (NASA-STD-5020B Eq. 84).
    %   Ignored        — slip check not evaluated (MS = NaN → NotEvaluated).
    %   Mirrors the reference Python tool's slip-mode selector
    %   ["Ignored", "Single Fastener Slip", "Joint Slip"].
    enumeration
        Ignored
        SingleFastener
        Joint
    end
end
