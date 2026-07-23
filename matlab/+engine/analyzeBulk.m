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
%                     ScaleFactor, Reversible
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
%
%   Row robustness: a bad element NEVER aborts the batch. An element whose
%   JointName is not in the library, or whose analyze() call errors, gets a
%   row with the Error column set and all margin columns NaN — the rest of
%   the batch still runs.
%
%   JOINT-SLIP LIMITATION (bulk runs are single-fastener by nature): the
%   force resolver produces PER-BOLT loads only (each FEM element = one
%   bolt, CBUSH projection), so the joint-level totals that SlipMode.Joint
%   needs (LoadCase.JointTensile/JointShearLimitLoad — NOT nf x per-bolt)
%   do not exist per element. A joint configured with SlipMode.Joint is
%   therefore analyzed with its slip check NotEvaluated here (Slip = NaN)
%   instead of erroring the whole row; WorstMargin/GoverningCheck then
%   exclude slip for that row. Joint-slip in bulk needs bolt-pattern
%   aggregation (future work). Most bulk runs use the SingleFastener
%   default, which evaluates normally from the per-bolt loads.
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

% ---- Per-element flow ---------------------------------------------------
for k = 1:n
    el = elements(k);
    elementId(k) = el.ElementId;
    jointName(k) = el.JointName;
    loadCase(k)  = el.LoadCaseName;

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

        % 3) Joint-slip limitation (see header): per-element forces carry no
        %    joint totals, so a Joint-mode slip check cannot evaluate in bulk.
        %    Disable it locally (Joint is a value class — the library copy is
        %    untouched) so the row analyzes with Slip = NotEvaluated instead
        %    of erroring on the missing joint-level loads.
        if joint.SlipMode == model.SlipMode.Joint
            joint.SlipMode = model.SlipMode.Disabled;
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
     table(worst, governing, errMsg, ...
        'VariableNames', {'WorstMargin', 'GoverningCheck', 'Error'})];
end
