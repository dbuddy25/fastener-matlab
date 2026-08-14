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
%                               as a styled table
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
% STAMPED WITH THE TOOL VERSION AND THE RUN TIME. A margin report is
% read away from the machine that made it, often much later, and the
% first question asked of one is which version of the tool produced it.
% Without this there was no way to answer that from the document.
generated = string(datetime("now", "Format", "yyyy-MM-dd HH:mm"));
stamp     = "Fastener Analysis Tool v" + toolVersion();

tp = TitlePage();
tp.Title     = "Bolted Joint Analysis";
tp.Subtitle  = joint.Name + " -- per NASA-STD-5020B";
tp.PubDate   = generated;
tp.Publisher = stamp;
add(rpt, tp);
add(rpt, TableOfContents());

% ---- 2. Inputs --------------------------------------------------------------
ch = Chapter("Inputs");
add(ch, Paragraph("Every input to the analysis (bolt, materials, " + ...
    "clamped stack, threaded member, preload spec, joint config, " + ...
    "applied loads, factors), plus the computed min/max preload band."));
add(ch, tableFromMATLAB(engine.summary(joint, loadCase, factors)));
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
    % SAY SO WHEN THE GOVERNING CHECK IS NOT ONE 5020B REQUIRES. Only the
    % bolt-thread-shear row is in that position (engine.analyze's
    % SUPPLEMENTAL note has the reasoning: §4.7.4 handles thread stripping
    % by design rule, not by a computed margin). Without this line a reader
    % could redesign a joint to satisfy a requirement the standard does not
    % levy, or state a 5020B compliance result that rests on a check
    % outside it. The margin itself is still real and still reported —
    % this caveats what it means, not whether to trust it.
    if isfield(r, "GoverningIsRequiredByStd") && ~r.GoverningIsRequiredByStd
        note = Text([" — this check is SUPPLEMENTAL to NASA-STD-5020B, " ...
            "which handles thread stripping by design rule (4.7.4) rather " ...
            "than by a computed margin. Every check 5020B does require " ...
            "carries a wider margin than this one."]);
        note.Italic = true;
        append(callout, note);
    end
    add(ch, callout);
end
add(rpt, ch);

% ---- 7. Separation-before-rupture -------------------------------------------
ch = Chapter("Separation-Before-Rupture");
add(ch, Paragraph("NASA-STD-5020B Fig. 8 (DABJ Fig. 9-9) decision tree. " + ...
    "This is a BRANCH SELECTION, not a margin: it decides which tension " + ...
    "equation governs, and it is deliberately absent from the Margins of " + ...
    "Safety table above for that reason."));
add(ch, gateVerdict(r));
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
add(ch, tableFromMATLAB(allT(evalMask, ["Name", "Method"])));
add(rpt, ch);

% ---- 9. About this report ---------------------------------------------------
% REPEATED FROM THE TITLE PAGE ON PURPOSE. Title pages get separated from
% the pages people actually circulate, and a table of margins with no
% version on it is untraceable the moment that happens.
% Named to match the About sheet report.exportResults writes, so the
% two outputs call the same thing the same name.
ch = Chapter("About This Report");
add(ch, Paragraph(stamp + ", run " + generated + "."));
add(ch, Paragraph("Analysis per NASA-STD-5020B; supplementary relations " + ...
    "per NASA TM-106943 where 5020B defers to it. The version above " + ...
    "identifies the build that produced every number in this report."));
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
%STRUCTTABLE  A small Field/Value table from a struct + field order.
vals = strings(numel(order), 1);
for i = 1:numel(order)
    vals(i) = fmtNum(s.(order(i)));
end
tbl = styledTable(["Field", "Value"], [order(:), vals(:)]);
end

function p = gateVerdict(r)
%GATEVERDICT  The Fig. 8 outcome, stated rather than left in prose.
%   Reads Result.Gate. It used to print Result.Narrative, which is the
%   engine's glued sentence -- gate trace, winning equation and Ptu_allow
%   basis in one run-on line -- the same string the Results page stopped
%   showing once Gate carried the pieces separately. Paper had kept it.
import mlreportgen.dom.*
st = report.reportStyle();
p  = Paragraph();

if ~isfield(r.Gate, 'Assessed')
    append(p, Text(string(r.Narrative)));   % pre-Gate Result, best effort
    return
end
g = r.Gate;

if ~g.Assessed
    verdict = "NOT ASSESSED";
elseif g.Assured
    verdict = "ASSURED -- separation occurs before rupture";
else
    % NOT a failure. The conservative branch is SELECTED, and its effect
    % is already carried by the Tension-Ultimate margin.
    verdict = "NOT ASSURED -- the conservative rupture branch governs";
end

head = Text(verdict);
head.Bold = true;
append(p, head);

if strlength(g.Equation) > 0
    append(p, Text("  Governing equation: " + g.Equation + "."));
end
if isfinite(g.Phi)
    append(p, Text(sprintf("  phi = %.4g (Eq. 9), n = %.2f.", g.Phi, g.N)));
end
if strlength(g.Trace) > 0
    trace = Text("  Gate: " + g.Trace);
    trace.Color = "#" + st.MutedText;
    append(p, trace);
end
end

function tbl = tableFromMATLAB(T)
%TABLEFROMMATLAB  A MATLAB table rendered in the report's look.
%   The drop-in for mlreportgen.dom.MATLABTable. Everything is stringified
%   through fmtCell so a numeric column prints the way the rest of the
%   report prints numbers rather than however the table happens to store
%   them -- MATLABTable's own formatting was the other half of why these
%   pages looked unlike the ones built by hand.
cells = strings(height(T), width(T));
for j = 1:width(T)
    col = T.(j);
    for i = 1:height(T)
        if isnumeric(col) || islogical(col)
            cells(i, j) = fmtNum(col(i));
        else
            cells(i, j) = string(col(i));
        end
    end
end
tbl = styledTable(string(T.Properties.VariableNames), cells);
end

function tbl = newStyledTable(headers)
%NEWSTYLEDTABLE  An empty table carrying the report's one table look.
%   Grid, header band, type scale. Callers append their own rows, which is
%   what the margins table needs so it can colour rows by Status.
%
%   This replaces mlreportgen.dom.MATLABTable, which renders a MATLAB
%   table with the toolbox's stock styling -- that default was the whole
%   of why the report looked unfinished. The DOM layer underneath does
%   everything ReportLab's TableStyle does; it simply was not being used.
import mlreportgen.dom.*
st = report.reportStyle();

tbl = Table();
tbl.Style = { ...
    Border("solid", "#" + st.GridColor, "0.5pt"), ...
    ColSep("solid", "#" + st.GridColor, "0.5pt"), ...
    RowSep("solid", "#" + st.GridColor, "0.5pt"), ...
    FontFamily(st.FontFamily), ...
    FontSize(st.TableSize)};

hdr = TableRow();
hdr.Style = {Bold(true), BackgroundColor("#" + st.HeaderBg), ...
             Color("#" + st.HeaderText)};
for h = string(headers)
    append(hdr, TableEntry(Paragraph(h)));
end
append(tbl, hdr);
end

function tbl = styledTable(headers, cells)
%STYLEDTABLE  A plain data table in the report's look, with row banding.
import mlreportgen.dom.*
st  = report.reportStyle();
tbl = newStyledTable(headers);
cells = string(cells);

for i = 1:size(cells, 1)
    row = TableRow();
    for j = 1:size(cells, 2)
        append(row, TableEntry(Paragraph(cells(i, j))));
    end
    % Banding, not colour-coding: these tables carry inputs and loads, not
    % verdicts, so nothing here should read as pass or fail.
    if mod(i, 2) == 0
        row.Style = {BackgroundColor("#" + st.BandBg)};
    end
    append(tbl, row);
end
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
st = report.reportStyle();
T  = r.asTable();

% SEPARATION-BEFORE-RUPTURE IS NOT A MARGIN AND DOES NOT BELONG HERE.
% It carries no number -- it records which branch the tension check took
% (NASA-STD-5020B Fig. 8) -- and the engine gives it Pass/Fail only
% because Status has no third word for a boolean gate. Left in this
% table it rendered as a red FAILED row, which is wrong twice: the joint
% has not failed anything, and the consequence of the branch it selected
% is ALREADY priced into Tension-Ultimate, so a reader counting red rows
% would count it twice. Its own chapter reports it properly.
%
% The mask indexes r.Margins as well as T -- rowValueText reads
% r.Margins(i).R for the Interaction row, so dropping a row from one and
% not the other would silently shift every R after it.
% Through report.reportedMarginNames, not a second copy of the rule --
% that function is what tests/tPdfReport.m asserts against, and a PDF is
% a binary the suite cannot read back, so if the two derived the row set
% separately the test would be checking a claim the document need not
% honour.
keep = ismember(T.Name, report.reportedMarginNames(r));
M    = r.Margins(keep);
T    = T(keep, :);

tbl = newStyledTable(["Name", "MS", "Status", "Method"]);

for i = 1:height(T)
    row = TableRow();
    append(row, TableEntry(Paragraph(T.Name(i))));
    append(row, TableEntry(Paragraph(rowValueText(T.MS(i), M(i).R))));
    append(row, TableEntry(Paragraph(T.Status(i))));
    append(row, TableEntry(Paragraph(T.Method(i))));

    % COLOUR COMES FROM Status, NEVER FROM RE-READING MS. The report does
    % not re-threshold a margin any more than the Results page does
    % (GUI2_SPEC.md Section 2) -- the engine decided, and paper and screen
    % have to agree about what it decided. These are gui2.palette's own
    % result colours, restated in report.reportStyle.
    rowStyle = {};
    switch T.Status(i)
        case "Pass"
            rowStyle = {BackgroundColor("#" + st.PassBg)};
        case "Fail"
            rowStyle = {BackgroundColor("#" + st.FailBg), ...
                        Color("#" + st.FailText)};
        otherwise   % NotEvaluated -- amber, never the grey of "nothing here"
            rowStyle = {BackgroundColor("#" + st.NotEvalBg)};
    end
    if strlength(r.GoverningCheck) > 0 && T.Name(i) == r.GoverningCheck
        rowStyle = [rowStyle, {Bold(true)}]; %#ok<AGROW>
    end
    row.Style = rowStyle;
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
