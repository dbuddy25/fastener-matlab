function T = analyzeBulk(jointLibrary, elements, factors)
%ANALYZEBULK  Batch orchestrator: parse -> resolve -> analyze, one row per element.
%   T = engine.analyzeBulk(jointLibrary, elements, factors) runs the full
%   bulk pipeline over a set of FEM elements and returns a writetable-ready
%   MATLAB table with ONE ROW PER ELEMENT (each element row is one
%   (element, load case) pair from the elements table). Orchestration only —
%   every number comes from the already-validated pieces:
%       engine.loadCaseFromForces  (element forces -> per-bolt LoadCase)
%       engine.analyze             (single-joint solver -> engine.Result)
%
%   Inputs:
%       jointLibrary  struct array from data.loadJointLibrary — fields
%                     Name (string) and Joint (model.Joint)
%       elements      struct array from data.loadElements — fields
%                     ElementId, JointName, LoadCaseName, Forces,
%                     ScaleFactor, Reversible, and optionally PatternId
%                     (bolt-pattern id for joint-slip aggregation; blank or
%                     absent -> JointName is the pattern)
%       factors       model.Factors — safety/fitting factors applied to
%                     every element
%
%   Output table columns (one row per element):
%       ElementId, JointName, LoadCase        identity (strings)
%       Axial, Shear                          resolved PER-BOLT limit loads,
%                                             lbf (LoadCase PtL / PsL)
%       TensionUlt, TensionYield, ShearUlt, ShearTearout, Bearing,
%       BearingUnderHead, BoltThreadShear, NutStrength, InsertInternal,
%       InsertExternal, Separation, Slip, SepBeforeRupture, Interaction,
%       TappedParent                          the 15 margin MS values, pulled
%                                             from Result.Margins by Name
%                                             (NaN = NotEvaluated)
%       WorstMargin, GoverningCheck           from the Result
%       Error                                 "" on success; the error
%                                             message when the element could
%                                             not be analyzed (margins NaN)
%       Note                                  "" normally; a non-fatal
%                                             warning (e.g. joint slip not
%                                             evaluated — see the nf check)
%
%   Row robustness: a bad element NEVER aborts the batch. An element whose
%   JointName is not in the library, or whose analyze() call errors, gets a
%   row with the Error column set and all margin columns NaN — the rest of
%   the batch still runs.
%
%   JOINT-MODE SLIP — BOLT-PATTERN AGGREGATION: each FEM element is one
%   bolt (CBUSH projection), so per-element loads are PER-BOLT only. For a
%   joint configured with SlipMode.Joint, the joint-level totals that
%   NASA-STD-5020B Eq. 84 needs (LoadCase.JointTensile/JointShearLimitLoad
%   — NOT nf x per-bolt) are built by aggregating the element's BOLT
%   PATTERN: all elements sharing the same pattern key (the optional
%   PatternId field — the physical joint instance — falling back to
%   JointName when blank, i.e. one joint name = one physical pattern), the
%   same JointName, and the same LoadCaseName. Their SCALED force
%   components are vector-summed (by equilibrium the per-bolt CBUSH forces
%   sum to the load crossing the interface) and the total is projected onto
%   the bolt axis: PtL_joint = the summed axial (floored at 0 — net
%   compression adds clamp, no tension demand; |total| if ANY pattern
%   element is Reversible) and PsL_joint = the RSS of the two transverse
%   sums. This mirrors how DABJ §9 builds its joint totals from the
%   resultant applied load (Solutions-22, option 1). Pattern torsion
%   (moment about the bolt axis at the pattern centroid) is NOT modeled —
%   the same scope as Eq. 84 itself (resultant force only).
%
%   THE nf CHECK: joint slip is evaluated ONLY when the pattern's element
%   count equals Joint.BoltCount — the nf in Eq. 84's capacity term
%   nf·mu·PpMin, so the capacity's bolt count and the demand's aggregated
%   pattern must describe the same set of bolts. A mismatch means the
%   elements table does not carry the pattern the library row describes
%   (missing/filtered rows, or one JointName reused for several physical
%   joints without a PatternId) — the slip check is left NotEvaluated
%   (Slip = NaN) and the Note column says why, rather than computing a
%   silently wrong Eq. 84 margin. The SingleFastener default needs no
%   aggregation and evaluates normally from the per-bolt loads.
%
%   Note on SepBeforeRupture: the NASA-STD-5020B Fig. 8 gate is boolean, so
%   its MS column is NaN by design even on success — its Pass/Fail lives in
%   the Result's Margins Status / Narrative (use engine.analyze directly
%   for the decision text).
%
%   Example (the Headless Release flow):
%       lib = data.Library.load();
%       jl  = data.loadJointLibrary("my_joints.csv", lib);
%       el  = data.loadElements("my_elements.csv");
%       T   = engine.analyzeBulk(jl, el, factors);
%       writetable(T, "margins.xlsx");

arguments
    jointLibrary (1,:) struct
    elements     (1,:) struct
    factors      (1,1) model.Factors
end

% ---- Margin-name -> results-column mapping (the 15-check set) -----------
% Left: Result.Margins row Names as emitted by engine.analyze.
% Right: compact writetable-friendly column names.
marginNames = ["Tension-Ultimate", "Tension-Yield", "Shear-Ultimate", ...
    "Shear-tearout", "Bearing", "Bearing-under-head", "Bolt-thread shear", ...
    "Nut strength", "Insert internal-thread", "Insert external-thread", ...
    "Separation", "Slip", "Separation-before-rupture", "Interaction", ...
    "Tapped-hole parent-thread"];
msColumns = ["TensionUlt", "TensionYield", "ShearUlt", ...
    "ShearTearout", "Bearing", "BearingUnderHead", "BoltThreadShear", ...
    "NutStrength", "InsertInternal", "InsertExternal", ...
    "Separation", "Slip", "SepBeforeRupture", "Interaction", ...
    "TappedParent"];

% ---- Name -> Joint lookup (string-array find; small libraries) ----------
if isempty(jointLibrary)
    libNames = strings(1, 0);
else
    libNames = [jointLibrary.Name];   % string array (one Name per joint row)
end

% ---- Preallocate the result columns -------------------------------------
n = numel(elements);
elementId = strings(n, 1);
jointName = strings(n, 1);
loadCase  = strings(n, 1);
axial     = nan(n, 1);
shear     = nan(n, 1);
ms        = nan(n, numel(msColumns));
worst     = nan(n, 1);
governing = strings(n, 1);
errMsg    = strings(n, 1);
note      = strings(n, 1);

% ---- Identity + pattern keys, precomputed for the whole batch -----------
% (Pattern grouping for joint slip needs every element's key up front.)
patKeys = strings(n, 1);
for k = 1:n
    elementId(k) = elements(k).ElementId;
    jointName(k) = elements(k).JointName;
    loadCase(k)  = elements(k).LoadCaseName;
    patKeys(k)   = jointName(k);          % default: one joint name = one pattern
    if isfield(elements, "PatternId")
        pid = string(elements(k).PatternId);   % [] -> 0x0 string (not scalar)
        if isscalar(pid) && ~ismissing(pid) && strlength(pid) > 0
            patKeys(k) = pid;
        end
    end
end

% ---- Per-element flow ---------------------------------------------------
for k = 1:n
    el = elements(k);

    % 1) Find the element's joint in the library (missing -> Error row, no throw)
    idx = find(libNames == el.JointName, 1);
    if isempty(idx)
        errMsg(k) = "Joint """ + el.JointName + """ not found in the joint library.";
        continue
    end
    joint = jointLibrary(idx).Joint;

    try
        % 2) Resolve the element forces onto the bolt axis -> per-bolt LoadCase
        lc = engine.loadCaseFromForces(el.Forces, joint.BoltAxis, ...
            Name        = el.LoadCaseName, ...
            ScaleFactor = el.ScaleFactor, ...
            Reversible  = el.Reversible);
        axial(k) = lc.BoltTensileLimitLoad;   % PtL (signed axial resolved)
        shear(k) = lc.BoltShearLimitLoad;     % PsL (transverse RSS)

        % 3) Joint-mode slip: aggregate the bolt pattern (see header).
        %    Pattern = same pattern key + same joint + same load case. Joint
        %    is a value class, so flipping SlipMode on a mismatch only
        %    affects this row's local copy — the library stays untouched.
        if joint.SlipMode == model.SlipMode.Joint
            mask = (patKeys == patKeys(k)) & ...
                   (jointName == el.JointName) & ...
                   (loadCase == loadCase(k));
            nEl = nnz(mask);
            if nEl == joint.BoltCount
                % The nf check passed: the pattern's totals feed Eq. 84
                [PtJ, PsJ] = groupTotals(elements(mask), joint.BoltAxis);
                lc.JointTensileLimitLoad = PtJ;
                lc.JointShearLimitLoad   = PsJ;
            else
                % nf mismatch: leave joint slip NotEvaluated + say why
                joint.SlipMode = model.SlipMode.Ignored;
                note(k) = sprintf( ...
                    "Joint slip not evaluated: pattern ""%s"" has %d element(s) for load case ""%s"" but Joint.BoltCount = %g.", ...
                    patKeys(k), nEl, loadCase(k), joint.BoltCount);
            end
        end

        % 4) Run the full 15-check solver and pull each MS by margin Name
        r = engine.analyze(joint, lc, factors);
        resNames = [r.Margins.Name];
        for c = 1:numel(marginNames)
            m = find(resNames == marginNames(c), 1);
            if ~isempty(m)
                ms(k, c) = r.Margins(m).MS;
            end
        end
        worst(k)     = r.WorstMargin;
        governing(k) = r.GoverningCheck;
    catch err
        % 5) Any failure -> Error column, margins stay NaN, batch continues
        errMsg(k) = string(err.message);
    end
end

% ---- Assemble the results table (writetable-ready) ----------------------
T = [table(elementId, jointName, loadCase, axial, shear, ...
        'VariableNames', {'ElementId', 'JointName', 'LoadCase', 'Axial', 'Shear'}), ...
     array2table(ms, 'VariableNames', cellstr(msColumns)), ...
     table(worst, governing, errMsg, note, ...
        'VariableNames', {'WorstMargin', 'GoverningCheck', 'Error', 'Note'})];
end

% ---- Local helpers --------------------------------------------------------

function [PtJ, PsJ] = groupTotals(group, axis)
%GROUPTOTALS  Joint-level limit loads from one bolt pattern's element forces.
%   Vector-sums each element's SCALED force components — by equilibrium the
%   per-bolt CBUSH forces sum to the load crossing the joint interface —
%   then projects the TOTAL onto the bolt axis (engine.resolveForces):
%       PtJ  axial total (floored at 0: net compression adds clamp, no
%            tension demand; |total| if ANY group element is Reversible)
%       PsJ  RSS of the two transverse component sums (the resultant
%            in-plane shear on the pattern)
%   Moments are not summed: resolveForces ignores torsion, and transverse
%   moments only feed the informational Bending output — pattern torsion is
%   out of scope here (same as NASA-STD-5020B Eq. 84, resultant force only).
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
