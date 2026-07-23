function d = designLoads(loadCase, factors)
%DESIGNLOADS  Per-bolt design loads from limit loads x safety/fitting factors.
%   d = engine.designLoads(loadCase, factors) applies the ultimate, yield,
%   and separation safety factors (FS) and fitting factors (FF) to the
%   per-bolt limit loads. All loads in lbf (see UNITS.md).
%
%   Returned struct fields (all lbf):
%       Ptu   design ultimate tension    = FSU  * FFU  * PtL
%       Pty   design yield tension       = FSY  * FFY  * PtL
%       Psu   design ultimate shear      = FSU  * FFU  * PsL
%       Psep  separation load            = FSSep* FFSep* PtL
%   where PtL = loadCase.BoltTensileLimitLoad and
%         PsL = loadCase.BoltShearLimitLoad (most-loaded bolt).
%
%   Validated against the DABJ Section 9 class problem (p. 9-6, via
%   validation.dabjSection9): Ptu 9,000 / Pty 6,990 / Psu 2,510 /
%   Psep 5,590 lbf (book-rounded; exact 8,999.9 / 6,987.5 / 2,511.6 / 5,590).

arguments
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

d = struct( ...
    "Ptu",  factors.FSU   * factors.FFU   * loadCase.BoltTensileLimitLoad, ...
    "Pty",  factors.FSY   * factors.FFY   * loadCase.BoltTensileLimitLoad, ...
    "Psu",  factors.FSU   * factors.FFU   * loadCase.BoltShearLimitLoad, ...
    "Psep", factors.FSSep * factors.FFSep * loadCase.BoltTensileLimitLoad);
end
