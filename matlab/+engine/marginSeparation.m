function r = marginSeparation(preload, designLoads)
%MARGINSEPARATION  Joint-separation margin of safety (NASA-STD-5020A Eq. 19).
%   r = engine.marginSeparation(preload, designLoads) computes the
%   separation margin for one joint. preload is the struct from
%   engine.preload; designLoads is the struct from engine.designLoads.
%   All loads in lbf (see UNITS.md).
%
%   Separation is driven by the MINIMUM in-service preload against the
%   design separation load:
%       MS = PpMin / Psep - 1                                (Eq. 19)
%   where PpMin = preload.PpMin (worst-case min preload after uncertainty,
%   relaxation, creep, and thermal) and Psep = designLoads.Psep
%   (FSSep * FFSep * PtL).
%
%   Returned struct fields:
%       MS      margin of safety (double)
%       Method  string: governing equation
%
%   Validated against the DABJ Section 9 class problem (Solutions-17, via
%   validation.dabjSection9): MS = 6,469.75/5,590 - 1 = +0.16.

arguments
    preload     (1,1) struct
    designLoads (1,1) struct
end

% NASA-STD-5020A Eq. 19 — MS = PpMin / Psep - 1
MS = preload.PpMin / designLoads.Psep - 1;

r = struct( ...
    "MS",     MS, ...
    "Method", "NASA-STD-5020A Eq. 19 (separation)");
end
