function file = singleJointReport(joint, loadCase, factors, file)
%SINGLEJOINTREPORT  Single-joint PDF report via MATLAB Report Generator (Phase 3.8).
%   file = report.singleJointReport(joint, loadCase, factors, file) runs
%   engine.analyze(joint, loadCase, factors) and builds ONE PDF report
%   documenting that single-joint analysis, returning the resolved
%   absolute path to the generated file. All loads in lbf (see UNITS.md).
%
%   factors: pass a model.Factors preset, or [] to fall back to the
%   built-in default preset (model.Factors()).
%
%   Report contents (mlreportgen.report.* + mlreportgen.dom.*):
%       1. Title page          "Bolted Joint Analysis" + the joint Name +
%                               "per NASA-STD-5020B"
%       2. Inputs               engine.summary(joint, loadCase, factors)
%                               as a MATLABTable
%       3. Preload               r.Preload (PpiMax/PpiMin/PpMax/PpMin/
%                               ThermalDelta), lbf
%       4. Design loads          r.DesignLoads (Ptu/Pty/Psu/Psep), lbf
%       5. Warnings              r.Warnings (bolt length / preload) --
%                               SKIPPED ENTIRELY when Warnings is empty.
%                               Per warning: the Message in its severity
%                               color (Critical red, Warning amber), then
%                               Method and Detail in normal weight below it
%                               -- traceability belongs in the report too,
%                               same as every margin row.
%       6. Margins of safety     r.asTable() (Name/MS/Status/Method), the
%                               row matching r.GoverningCheck bolded, Fail
%                               rows (by Status, NOT by "MS < 0" -- the
%                               Interaction row's MS is NaN by design; its
%                               Status is already Pass/Fail from R <= 1,
%                               see below) shaded red, plus a one-line
%                               "Governing: <check>, MS = <value>" callout.
%                               The Interaction row's Value cell shows
%                               "R = <value> (<=1)" (read from
%                               r.Margins(k).R, NOT from MS, which is NaN
%                               for that row) instead of the usual signed
%                               MS text -- see marginsTable's rowValueText
%                               helper.
%       7. Separation-before-rupture   r.Narrative (NASA-STD-5020B Fig. 8 /
%                               DABJ Fig. 9-9 decision text)
%       8. Governing equations   Name + Method for every EVALUATED check
%                               (NotEvaluated rows omitted) -- traceability
%                               back to the standard.
%
%   Section 7 is the lightweight "derivations" layer: it is equation
%   CITATIONS (the same Method strings each margin function already
%   carries), not full step-by-step symbolic derivations with every
%   intermediate substitution shown. That level of detail is a follow-up,
%   not built here.
%
%   REQUIRES the MATLAB Report Generator toolbox (mlreportgen.report.*,
%   mlreportgen.dom.*). If it is not installed/licensed, this function
%   errors immediately with id "report:singleJointReport:reportGenRequired"
%   rather than failing deep inside an undefined-class error.
%
%   Example:
%       c = validation.dabjSection9();
%       f = report.singleJointReport(c.Joint, c.LoadCase, c.Factors, "report.pdf");

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors
    file     (1,1) string
end

if isempty(factors)
    factors = model.Factors();
end

if exist("mlreportgen.report.Report", "class") ~= 8
    error("report:singleJointReport:reportGenRequired", ...
        "MATLAB Report Generator is required to build a PDF report " + ...
        "(mlreportgen.report.Report was not found). Install/enable " + ...
        "the Report Generator toolbox to use report.singleJointReport.");
end

[~, ~, ext] = fileparts(file);
if strlength(ext) == 0
    file = file + ".pdf";
end

% ---- Run the analysis -----------------------------------------------------
r = engine.analyze(joint, loadCase, factors);

import mlreportgen.report.*
import mlreportgen.dom.*

[fdir, fname] = fileparts(file);
if strlength(fdir) == 0
    reportName = fname;
else
    reportName = fullfile(fdir, fname);
end

rpt = Report(reportName, "pdf");

% ---- 1. Title page ---------------------------------------------------------
tp = TitlePage();
tp.Title    = "Bolted Joint Analysis";
tp.Subtitle = joint.Name + " -- per NASA-STD-5020B";
add(rpt, tp);
add(rpt, TableOfContents());

% ---- 2. Inputs --------------------------------------------------------------
ch = Chapter("Inputs");
add(ch, Paragraph("Every input to the analysis (bolt, materials, " + ...
    "clamped stack, threaded member, preload spec, joint config, " + ...
    "applied loads, factors), plus the computed min/max preload band."));
add(ch, MATLABTable(engine.summary(joint, loadCase, factors)));
add(rpt, ch);

% ---- 3. Preload ---------------------------------------------------------------
ch = Chapter("Preload");
add(ch, Paragraph("Computed preload band (lbf):"));
add(ch, structTable(r.Preload, ["PpiMax", "PpiMin", "PpMax", "PpMin", "ThermalDelta"]));
add(rpt, ch);

% ---- 4. Design loads -------------------------------------------------------
ch = Chapter("Design Loads");
add(ch, Paragraph("Design loads (lbf):"));
add(ch, structTable(r.DesignLoads, ["Ptu", "Pty", "Psu", "Psep"]));
add(rpt, ch);

% ---- 5. Warnings (skipped entirely when empty) ------------------------------
if ~isempty(r.Warnings)
    ch = Chapter("Warnings");
    add(ch, Paragraph("Bolt-length and preload watchdog warnings -- NOT " + ...
        "margin checks (they never affect WorstMargin/GoverningCheck), " + ...
        "surfaced here with the same equation/citation traceability as " + ...
        "every margin below."));
    for i = 1:numel(r.Warnings)
        w = r.Warnings(i);
        msgPar = Paragraph();
        msgText = Text(sprintf("%s: %s", w.Severity, w.Message));
        msgText.Bold  = true;
        msgText.Color = severityColor(w.Severity);
        append(msgPar, msgText);
        add(ch, msgPar);
        add(ch, Paragraph("Method: " + w.Method));
        add(ch, Paragraph("Detail: " + w.Detail));
    end
    add(rpt, ch);
end

% ---- 6. Margins of safety --------------------------------------------------
ch = Chapter("Margins of Safety");
add(ch, marginsTable(r));
if isnan(r.WorstMargin)
    add(ch, Paragraph("No checks evaluated -- see the Method column above for why."));
else
    callout = Paragraph();
    append(callout, Text("Governing: "));
    highlight = Text(sprintf("%s, MS = %.3f", r.GoverningCheck, r.WorstMargin));
    highlight.Bold = true;
    append(callout, highlight);
    add(ch, callout);
end
add(rpt, ch);

% ---- 7. Separation-before-rupture -------------------------------------------
ch = Chapter("Separation-Before-Rupture");
add(ch, Paragraph("NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) decision tree:"));
add(ch, Paragraph(r.Narrative));
add(rpt, ch);

% ---- 8. Governing equations --------------------------------------------------
ch = Chapter("Governing Equations");
add(ch, Paragraph("Equation citation for each EVALUATED check, traceable " + ...
    "to NASA-STD-5020B / NASA TM-106943 (see the header comment of " + ...
    "report.singleJointReport for scope: citations only, not full " + ...
    "step-by-step derivations). NotEvaluated checks are omitted here -- " + ...
    "see the Margins of Safety table for the complete 15-row set."));
allT     = r.asTable();
evalMask = allT.Status ~= "NotEvaluated";
add(ch, MATLABTable(allT(evalMask, ["Name", "Method"])));
add(rpt, ch);

close(rpt);

% Resolve to the absolute path actually written
d    = dir(file);
file = string(fullfile(d(1).folder, d(1).name));
end

% ---- Local helpers ----------------------------------------------------------
function c = severityColor(severity)
%SEVERITYCOLOR  Warning-row text color -- Critical red, Warning amber.
%   Mirrors the GUI's palette semantics (gui.palette: amber = warning, red
%   = failure/critical) using literal CSS color names, the same convention
%   marginsTable already uses for its own Color("red") Fail-row styling
%   (this report layer has no shared palette() of its own).
if severity == "Critical"
    c = "red";
else
    c = "darkorange";
end
end

function tbl = structTable(s, order)
%STRUCTTABLE  A small Field/Value MATLABTable from a struct + field order.
vals = strings(numel(order), 1);
for i = 1:numel(order)
    vals(i) = fmtNum(s.(order(i)));
end
t   = table(order(:), vals(:), VariableNames = ["Field", "Value"]);
tbl = mlreportgen.dom.MATLABTable(t);
end

function tbl = marginsTable(r)
%MARGINSTABLE  The 15-row margins table, governing row bold + Fail rows red.
%   The "MS" column header stays generic -- it already reads as "Value"
%   for every check, ordinary margin or not (mirrors the GUI Results
%   table's "Value" column, GUI_PORT_SPEC.md Section 4). The Interaction
%   row's cell text is the one exception: since its MS is NaN by design
%   (NASA-STD-5020B Eq. 20-23 is a pass/fail CRITERION on the ratio R, not
%   a margin equation -- see engine.analyze's INTERACTION IS NOT A MARGIN
%   note), rowValueText below reads r.Margins(i).R directly and renders
%   "R = <value> (<=1)" instead of the usual signed MS text -- so the row
%   never prints a bare "-" where a real, meaningful number exists, and
%   the opposite pass/fail direction (R <= 1, not MS >= 0) is spelled out
%   inline rather than left for the reader to infer.
import mlreportgen.dom.*
T = r.asTable();

tbl = Table();

header = TableRow();
for h = ["Name", "MS", "Status", "Method"]
    append(header, TableEntry(Paragraph(h)));
end
header.Style = {Bold(true)};
append(tbl, header);

for i = 1:height(T)
    row = TableRow();
    append(row, TableEntry(Paragraph(T.Name(i))));
    append(row, TableEntry(Paragraph(rowValueText(T.MS(i), r.Margins(i).R))));
    append(row, TableEntry(Paragraph(T.Status(i))));
    append(row, TableEntry(Paragraph(T.Method(i))));

    rowStyle = {};
    if strlength(r.GoverningCheck) > 0 && T.Name(i) == r.GoverningCheck
        rowStyle = [rowStyle, {Bold(true)}]; %#ok<AGROW>
    end
    if T.Status(i) == "Fail"
        rowStyle = [rowStyle, {Color("red")}]; %#ok<AGROW>
    end
    if ~isempty(rowStyle)
        row.Style = rowStyle;
    end
    append(tbl, row);
end
end

function s = rowValueText(ms, ratio)
%ROWVALUETEXT  Margins table Value-cell text for one row.
%   Ordinary rows: the usual signed-MS text (fmtNum). The Interaction row
%   is the one exception -- its MS is NaN by design (see marginsTable's
%   header note), so when ratio (r.Margins(i).R) is not NaN this renders
%   "R = <value> (<=1)" instead, making both the number AND the OPPOSITE
%   pass/fail direction (R <= 1, not MS >= 0) visible in the cell itself.
if ~isnan(ratio)
    s = string(sprintf("R = %.6g (<=1)", ratio));
else
    s = fmtNum(ms);
end
end

function s = fmtNum(v)
%FMTNUM  One value -> display string. NaN -> "-"; numbers via %.6g; else string().
if isnumeric(v)
    if isnan(v)
        s = "-";
    else
        s = string(sprintf("%.6g", v));
    end
else
    s = string(v);
end
end
