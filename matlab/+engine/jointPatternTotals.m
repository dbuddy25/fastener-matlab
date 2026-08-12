function [PtJ, PsJ] = jointPatternTotals(group, axis)
%JOINTPATTERNTOTALS  Joint-level limit loads from one bolt pattern's elements.
%   [PtJ, PsJ] = engine.jointPatternTotals(group, axis) vector-sums each
%   element's SCALED force components — by equilibrium the per-bolt CBUSH
%   forces sum to the load crossing the joint interface — then projects the
%   TOTAL onto the bolt axis (engine.resolveForces):
%       PtJ  axial total (floored at 0: net compression adds clamp, no
%            tension demand; |total| if ANY group element is Reversible)
%       PsJ  RSS of the two transverse component sums (the resultant
%            in-plane shear on the pattern)
%
%   These are the two quantities NASA-STD-5020B Eq. 84 needs for
%   SlipMode.Joint, and the ones engine.analyze REFUSES to proceed without
%   (LoadCase.JointTensile/JointShearLimitLoad).
%
%   WHY THIS IS PUBLIC. It was a local helper inside engine.analyzeBulk,
%   reachable from the batch path and nothing else — so the GUI's
%   "Show in Single Joint Analysis" drill-down, which re-runs ONE element
%   of a bulk row, could not reproduce that row: analyze threw on the
%   missing joint-level loads and the button silently did nothing. A view
%   that re-derived the totals itself would be the GUI doing analysis, so
%   the aggregation moved here instead and both callers share it. This is
%   the same extraction, for the same reason, as engine.applyTemperatures.
%
%   Moments are not summed, and that is a narrower statement than it used
%   to be: transverse moments DO feed a real bending term per element
%   (LoadCase.BoltBendingLimitMoment -> the Eq. 20/22 fbu), but summing
%   them across a PATTERN is a different quantity that Eq. 84 does not
%   define — that equation takes the resultant force only. So bending is
%   per-element; a pattern total carries no moment and its interaction runs
%   at fbu = 0. resolveForces ignores torsion throughout.
%
%   group — struct array of the pattern's elements, each with Forces
%           (FX/FY/FZ), ScaleFactor and Reversible.
%   axis  — model.BoltAxis.
%
%   Call graph:
%       Precedents (calls)      engine.resolveForces.
%       Dependents (called by)  engine.analyzeBulk (joint-mode slip),
%                               gui2.BulkAnalysisPage (drill-down).
%       Tests                   tests/tBulk.m
%                               (bulkJointSlipFromPatternAggregation pins
%                               the DABJ Sec. 9 number through this path).
%
%   Validation status/coverage: VALIDATION.md, joint-slip row — the totals
%   reproduce the book's joint resultant (Solutions-22, option 1).

arguments
    group (1,:) struct
    axis  (1,1) model.BoltAxis
end

Fsum   = struct("FX", 0, "FY", 0, "FZ", 0);
anyRev = false;
for g = 1:numel(group)
    sf = group(g).ScaleFactor;
    Fsum.FX = Fsum.FX + sf * group(g).Forces.FX;
    Fsum.FY = Fsum.FY + sf * group(g).Forces.FY;
    Fsum.FZ = Fsum.FZ + sf * group(g).Forces.FZ;
    anyRev  = anyRev || group(g).Reversible;
end

r = engine.resolveForces(Fsum, axis);
if anyRev
    PtJ = abs(r.Axial);       % load may reverse: carry the total as tension
else
    PtJ = max(r.Axial, 0);    % net compression -> no joint tension demand
end
PsJ = r.Shear;
end
