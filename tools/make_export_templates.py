"""Build the styled export templates in matlab/templates/.

Dev-only (needs openpyxl); the app never runs this. The committed .xlsx
files are the output, and MATLAB fills them with values at export time
(writecell, UseExcel=false, PreserveFormat=true, AutoFitWidth=false).

Every block MATLAB writes into is a named range. The MATLAB side reads the
same names from report.exportLayout, and tExportTemplates fails if the two
ever disagree.

    python tools/make_export_templates.py
"""
from pathlib import Path

from openpyxl import Workbook
from openpyxl.formatting.rule import CellIsRule, FormulaRule
from openpyxl.formatting.rule import Rule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.styles.differential import DifferentialStyle
from openpyxl.styles.numbers import NumberFormat
from openpyxl.utils import get_column_letter
from openpyxl.workbook.defined_name import DefinedName

OUT = Path(__file__).resolve().parents[1] / "matlab" / "templates"

# Same values as gui.palette, so the workbook and the app agree.
PASS_BG, PASS_FG = "C7F0C7", "006600"
FAIL_BG, FAIL_FG = "FFC7C7", "CC0000"
NOTEVAL_BG, NOTEVAL_FG = "FFF3CD", "856404"
HEADER_BG = "E0ECF9"
MUTED = "666666"
RULE = "C7C7CC"

MARGIN_FMT = "+0.00;-0.00;0.00"
thin = Side(style="thin", color=RULE)
box = Border(left=thin, right=thin, top=thin, bottom=thin)
fill = lambda c: PatternFill("solid", start_color=c, end_color=c)


def status_rules(ws, rng):
    for text, bg, fg in (("FAIL", FAIL_BG, FAIL_FG),
                         ("Pass", PASS_BG, PASS_FG),
                         ("Not evaluated", NOTEVAL_BG, NOTEVAL_FG)):
        ws.conditional_formatting.add(rng, CellIsRule(
            operator="equal", formula=[f'"{text}"'],
            fill=fill(bg), font=Font(color=fg, bold=True)))


def header(ws, cells):
    for ref, text in cells:
        c = ws[ref]
        c.value = text
        c.font = Font(bold=True)
        c.fill = fill(HEADER_BG)
        c.border = box
        c.alignment = Alignment(vertical="center")


def grid(ws, cols, rows, wrap=False):
    for r in rows:
        for col in cols:
            c = ws[f"{col}{r}"]
            c.border = box
            c.alignment = Alignment(vertical="top" if wrap else "center",
                                    wrap_text=wrap)


def widths(ws, spec):
    for col, w in spec.items():
        ws.column_dimensions[col].width = w


def name(wb, key, ref):
    wb.defined_names[key] = DefinedName(key, attr_text=ref)


def single():
    wb = Workbook()

    # ---- Slide: one block to paste onto a 16:9 slide --------------------
    ws = wb.active
    ws.title = "Slide"
    ws.sheet_view.showGridLines = False
    widths(ws, {"A": 20, "B": 34, "C": 2, "D": 24, "E": 13, "F": 14,
                "G": 34, "I": 10})
    ws.column_dimensions["I"].hidden = True

    ws.merge_cells("A1:G1")
    ws["A1"].font = Font(size=16, bold=True)
    ws.row_dimensions[1].height = 24
    for cls, color in (("fail", FAIL_FG), ("noteval", NOTEVAL_FG),
                       ("pass", PASS_FG)):
        ws.conditional_formatting.add("A1", FormulaRule(
            formula=[f'$I$1="{cls}"'], font=Font(color=color, bold=True)))

    ws.merge_cells("A2:G2")
    ws["A2"].font = Font(italic=True, color=MUTED)

    header(ws, [("A4", "Input"), ("B4", "Value"), ("D4", "Check"),
                ("E4", "MS / R"), ("F4", "Status"),
                ("G4", "Governing equation")])
    grid(ws, "AB", range(5, 20))
    grid(ws, "DEFG", range(5, 20))
    for r in range(5, 20):
        ws[f"A{r}"].font = Font(bold=True)
        ws[f"E{r}"].number_format = MARGIN_FMT
        ws[f"E{r}"].alignment = Alignment(horizontal="right",
                                          vertical="center")
    status_rules(ws, "F5:F19")

    ws.merge_cells("A21:G21")
    ws["A21"].font = Font(italic=True, size=9, color=MUTED)
    ws["A21"].alignment = Alignment(wrap_text=True, vertical="top")
    ws.row_dimensions[21].height = 36

    name(wb, "SlideTitle", "Slide!$A$1")
    name(wb, "SlideSubtitle", "Slide!$A$2")
    name(wb, "SlideVerdictClass", "Slide!$I$1")
    name(wb, "SlideInputs", "Slide!$A$5:$B$19")
    name(wb, "SlideMargins", "Slide!$D$5:$G$19")
    name(wb, "SlideScope", "Slide!$A$21")

    # ---- Detail: the checker's view of every check ----------------------
    ws = wb.create_sheet("Detail")
    ws.freeze_panes = "A2"
    widths(ws, {"A": 24, "B": 14, "C": 16, "D": 60, "E": 48, "F": 48})
    header(ws, [("A1", "Check"), ("B1", "Status"), ("C1", "MS / R"),
                ("D1", "Governing equation"),
                ("E1", "Inputs (substituted)"), ("F1", "Detail")])
    grid(ws, "ABCDEF", range(2, 17), wrap=True)
    for r in range(2, 17):
        ws[f"C{r}"].number_format = MARGIN_FMT
    status_rules(ws, "B2:B16")
    name(wb, "DetailRows", "Detail!$A$2:$F$16")

    # ---- About: provenance ------------------------------------------------
    ws = wb.create_sheet("About")
    widths(ws, {"A": 22, "B": 100})
    header(ws, [("A1", "Item"), ("B1", "Value")])
    grid(ws, "AB", range(2, 26), wrap=True)
    for r in range(2, 26):
        ws[f"A{r}"].font = Font(bold=True)
    name(wb, "AboutRows", "About!$A$2:$B$25")

    wb.save(OUT / "export_single.xlsx")


# The headers report.bulkHeaders gives the engine's bulk margin columns
# (engine.analyzeBulk msColumns) plus the worst margin. Colour and number
# rules key on these header names, so a column is formatted wherever it
# lands. tExportTemplates checks this list.
MARGIN_COLUMNS = ["Tension-Ultimate", "Tension-Yield", "Shear-Ultimate",
                  "Shear-tearout", "Bearing", "Bearing-under-head",
                  "Bolt-thread shear", "Nut strength", "Insert internal-thread",
                  "Insert external-thread", "Separation", "Slip",
                  "Separation-before-rupture", "Interaction R (≤ 1)",
                  "Tapped-hole parent-thread", "Worst Margin"]
LOAD_COLUMNS = ["Axial (lbf)", "Shear (lbf)"]
RATIO_FMT = "0.00"
LOAD_FMT = "#,##0.0"


def fmt_rule(formula, code, num_id, bg=None, fg=None):
    """A formula rule that sets the number format too: the value stays
    unrounded, only its display is trimmed."""
    dxf = DifferentialStyle(numFmt=NumberFormat(numFmtId=num_id, formatCode=code))
    if bg:
        dxf.fill = fill(bg)
        dxf.font = Font(color=fg)
    return Rule(type="expression", dxf=dxf, formula=[formula])


def margin_rules(ws, rng, first):
    """Pass/fail/not-evaluated colour and two decimals by header name;
    Interaction R reversed. Loads get one decimal and a thousands comma."""
    col = first[0]
    row = first[1:]
    head = f"{col}$1"
    cell = f"{col}{row}"
    is_margin = f"ISNUMBER(MATCH({head},Margins,0))"
    is_ratio = f'LEFT({head},11)="Interaction"'
    fail = f'AND(ISNUMBER({cell}),{is_margin},IF({is_ratio},{cell}>1,{cell}<0))'
    ok = f'AND(ISNUMBER({cell}),{is_margin},IF({is_ratio},{cell}<=1,{cell}>=0))'
    ne = f'AND({cell}="—",{is_margin})'
    load = f"AND(ISNUMBER({cell}),ISNUMBER(MATCH({head},Loads,0)))"
    # The ratio's format first: rules apply in order, and a ratio has no sign.
    ratio_fmt = f"AND(ISNUMBER({cell}),{is_margin},{is_ratio})"
    ws.conditional_formatting.add(rng, fmt_rule(ratio_fmt, RATIO_FMT, 201))
    ws.conditional_formatting.add(rng, fmt_rule(fail, MARGIN_FMT, 200, FAIL_BG, FAIL_FG))
    ws.conditional_formatting.add(rng, FormulaRule(
        formula=[ne], fill=fill(NOTEVAL_BG), font=Font(color=NOTEVAL_FG)))
    ws.conditional_formatting.add(rng, fmt_rule(ok, MARGIN_FMT, 200, PASS_BG, PASS_FG))
    ws.conditional_formatting.add(rng, fmt_rule(load, LOAD_FMT, 202))


def data_sheet(ws, n_cols, left_cols=(), last_col="BZ", last_row=5000,
               first_col_width=22):
    """Header row plus centred data cells. The cells are pre-styled because
    MATLAB's writer keeps a cell's existing format (PreserveFormat) but
    ignores column-level styles; left_cols are free-text columns."""
    ws.freeze_panes = "B2"
    for c in range(1, 79):
        h = ws.cell(row=1, column=c)
        h.font = Font(bold=True)
        h.fill = fill(HEADER_BG)
        h.alignment = Alignment(wrap_text=True, horizontal="center",
                                vertical="center")
    ws.row_dimensions[1].height = 45
    ws.column_dimensions["A"].width = first_col_width
    for col in ("B", "C", "D"):
        ws.column_dimensions[col].width = 16
    for c in range(5, 79):
        ws.column_dimensions[get_column_letter(c)].width = 14
    centre = Alignment(horizontal="center", vertical="center")
    for c in range(2, n_cols + 1):
        if get_column_letter(c) in left_cols:
            continue
        for r in range(2, last_row + 1):
            ws.cell(row=r, column=c).alignment = centre
    for col in left_cols:
        ws.column_dimensions[col].width = 40
    margin_rules(ws, f"A2:{last_col}{last_row}", "A2")


def bulk():
    wb = Workbook()
    ws = wb.active
    ws.title = "Joint Summary"
    # Joint | 3 counts | worst margin, check, element, load case | 15 margins
    data_sheet(ws, n_cols=23, last_row=1000, first_col_width=28)
    ws = wb.create_sheet("Results")
    # Element, joint, load case | 2 loads | 15 margins | worst, governing |
    # Error, Note, Warnings (free text, left)
    data_sheet(ws, n_cols=25, left_cols=("W", "X", "Y"))
    ws.auto_filter.ref = "A1:BZ5000"

    ws = wb.create_sheet("About")
    widths(ws, {"A": 22, "B": 100})
    header(ws, [("A1", "Item"), ("B1", "Value")])
    grid(ws, "AB", range(2, 26), wrap=True)
    for r in range(2, 26):
        ws[f"A{r}"].font = Font(bold=True)

    ws = wb.create_sheet("Lists")
    for i, col_name in enumerate(MARGIN_COLUMNS, start=1):
        ws.cell(row=i, column=1).value = col_name
    for i, col_name in enumerate(LOAD_COLUMNS, start=1):
        ws.cell(row=i, column=2).value = col_name
    ws.sheet_state = "hidden"
    name(wb, "Margins", f"Lists!$A$1:$A${len(MARGIN_COLUMNS)}")
    name(wb, "Loads", f"Lists!$B$1:$B${len(LOAD_COLUMNS)}")
    name(wb, "BulkAboutRows", "About!$A$2:$B$25")
    wb.save(OUT / "export_bulk.xlsx")


if __name__ == "__main__":
    single()
    bulk()
    print("wrote", OUT / "export_single.xlsx", "and", OUT / "export_bulk.xlsx")
