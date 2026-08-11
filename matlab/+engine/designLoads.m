function d = designLoads(loadCase, factors)
%DESIGNLOADS  Per-bolt design loads from limit loads x safety/fitting factors.
%   d = engine.designLoads(loadCase, factors) applies the ultimate, yield,
%   and separation safety factors (FS) and fitting factors (FF) to the
%   per-bolt limit loads. All loads in lbf (see UNITS.md).
%
%   Governing definition: NASA-STD-5020B design-factor application —
%   design load = FS x FF x limit load (per NASA-STD-5020B design-factor
%   requirements; DABJ Section 9 applies this to form Ptu/Pty/Psu/Psep).
%   These design loads feed every downstream margin (Eq. 6/14/15/19/20-23).
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
%
%   Call graph:
%       Precedents (calls)      model.LoadCase, model.Factors — a leaf; no
%                               engine.* dependencies.
%       Dependents (called by)  engine.analyze.
%       Tests                   tests/tDabjCase.m — designLoadsMatchDABJ.
%
%   Validation status/coverage: no dedicated VALIDATION.md row (Ptu/Pty/
%   Psu/Psep are exercised as inputs to the Margin-checks rows 1/2/3/10
%   rather than as a named feature of their own) — the DABJ §9 numbers
%   above are kept in full rather than pointed at a row that doesn't exist.

arguments
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

% NASA-STD-5020B design-factor application: design load = FS x FF x limit load
d = struct( ...
    "Ptu",  factors.FSU   * factors.FFU   * loadCase.BoltTensileLimitLoad, ... % NASA-STD-5020B design ultimate tension (FSU*FFU*PtL)
    "Pty",  factors.FSY   * factors.FFY   * loadCase.BoltTensileLimitLoad, ... % NASA-STD-5020B design yield tension (FSY*FFY*PtL)
    "Psu",  factors.FSU   * factors.FFU   * loadCase.BoltShearLimitLoad, ...   % NASA-STD-5020B design ultimate shear (FSU*FFU*PsL)
    "Psep", factors.FSSep * factors.FFSep * loadCase.BoltTensileLimitLoad, ...  % NASA-STD-5020B separation load (FSSep*FFSep*PtL)
    "Mbu",  factors.FSU   * factors.FFU   * loadCase.BoltBendingLimitMoment);  % design ultimate bending MOMENT, IN-LBF (FSU*FFU*MbL)

% Mbu IS IN-LBF, not lbf -- the only field here that is not a force. It
% takes the same FSU*FFU pair as Ptu and Psu because bending enters the
% ULTIMATE interaction criterion (NASA-STD-5020B Eq. 20/22) alongside them,
% and 5020B defines fbu as "the design ultimate bending stress".
%
% The MOMENT stops here; the STRESS fbu does not belong in this function.
% fbu = 32*Mbu/(pi*d^3) needs a bolt diameter, and this function takes only
% a LoadCase and Factors -- deliberately, since its whole job is applying
% FS*FF to limit loads. engine.marginInteraction owns the geometry step
% (see engine/private/boltBendingStress).
end
