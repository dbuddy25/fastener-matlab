function S = bulkJointSummary(T)
%BULKJOINTSUMMARY  One row per joint from a bulk results table.
%   S = report.bulkJointSummary(T) takes engine.analyzeBulk's table and
%   returns, per joint: analyses, failing analyses, errors, the worst
%   margin with its governing check, element and load case, then the
%   envelope of every margin column (worst MS; largest R for InteractionR).
%   The envelope is gui.MarginView's, the same the Bulk page's Joint
%   Summary tab draws, so the file and the screen agree. No filters.
arguments
    T table
end

vars = string(T.Properties.VariableNames);
iS = find(vars == "Shear", 1);
iW = find(vars == "WorstMargin", 1);
ms = vars(iS + 1:iW - 1);
ratio = gui.MarginView.isRatio(ms);

M = zeros(height(T), numel(ms));
for c = 1:numel(ms)
    M(:, c) = T.(char(ms(c)));
end
err = strlength(string(T.Error)) > 0;
[~, failM] = gui.MarginView.passFail(M, ratio);
rowFail = any(failM, 2) & ~err;

joints = unique(string(T.JointName), 'stable');
n = numel(joints);
Joint = joints;
Analyses = zeros(n, 1);
Failing = zeros(n, 1);
Errors = zeros(n, 1);
WorstMargin = nan(n, 1);
GoverningCheck = strings(n, 1);
WorstElement = strings(n, 1);
WorstLoadCase = strings(n, 1);
env = nan(n, numel(ms));
for j = 1:n
    mask = string(T.JointName) == joints(j);
    Analyses(j) = nnz(mask);
    Failing(j) = nnz(rowFail & mask);
    Errors(j) = nnz(err & mask);
    env(j, :) = gui.MarginView.envelope(M(mask, :), ratio);
    idx = find(mask);
    wm = T.WorstMargin(idx);
    if any(~isnan(wm))
        [WorstMargin(j), k] = min(wm, [], 'omitnan');
        r = idx(k);
        GoverningCheck(j) = string(T.GoverningCheck(r));
        WorstElement(j) = string(T.ElementId(r));
        WorstLoadCase(j) = string(T.LoadCase(r));
    end
end
S = [table(Joint, Analyses, Failing, Errors, WorstMargin, GoverningCheck, ...
    WorstElement, WorstLoadCase), array2table(env, 'VariableNames', cellstr(ms))];
end
