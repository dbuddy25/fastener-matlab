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
%       5. Margins of safety     r.asTable() (Name/MS/Status/Method), the
%                               row matching r.GoverningCheck bolded, Fail
%                               rows (MS < 0) in red, plus a one-line
%                               "Governing: <check>, MS = <value>" callout
%       6. Separation-before-rupture   r.Narrative (NASA-STD-5020B Fig. 8 /
%                               DABJ Fig. 9-9 decision text)
%       7. Governing equations   Name + Method for every EVALUATED check
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

% ---- 5. Margins of safety --------------------------------------------------
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

% ---- 6. Separation-before-rupture -------------------------------------------
ch = Chapter("Separation-Before-Rupture");
add(ch, Paragraph("NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) decision tree:"));
add(ch, Paragraph(r.Narrative));
add(rpt, ch);

% ---- 7. Governing equations --------------------------------------------------
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
    append(row, TableEntry(Paragraph(fmtNum(T.MS(i)))));
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
