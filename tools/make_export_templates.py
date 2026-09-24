"""Build the styled export templates in matlab/templates/.

Dev-only (needs openpyxl); the app never runs this. The committed .xlsx
files are the output, and MATLAB fills them with values at export time.

    python tools/make_export_templates.py
"""
from pathlib import Path

from openpyxl import Workbook
from openpyxl.formatting.rule import CellIsRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.workbook.defined_name import DefinedName

OUT = Path(__file__).resolve().parents[1] / "matlab" / "templates"

# Same values as gui.palette, so the workbook and the app agree.
PASS_BG, PASS_FG = "C7F0C7", "006600"
FAIL_BG, FAIL_FG = "FFC7C7", "CC0000"
NOTEVAL_BG, NOTEVAL_FG = "FFF3CD", "856404"
HEADER_BG = "E0ECF9"
RULE = "C7C7CC"

thin = Side(style="thin", color=RULE)
box = Border(left=thin, right=thin, top=thin, bottom=thin)


def status_rules(ws, rng):
    for text, bg, fg in (("FAIL", FAIL_BG, FAIL_FG),
                         ("Pass", PASS_BG, PASS_FG),
                         ("Not evaluated", NOTEVAL_BG, NOTEVAL_FG)):
        ws.conditional_formatting.add(rng, CellIsRule(
            operator="equal", formula=[f'"{text}"'],
            fill=PatternFill("solid", start_color=bg, end_color=bg),
            font=Font(color=fg, bold=True)))


def probe():
    wb = Workbook()
    ws = wb.active
    ws.title = "Slide"
    ws.sheet_view.showGridLines = False

    ws.merge_cells("A1:D1")
    ws["A1"].font = Font(size=14, bold=True)
    for col, width in zip("ABCD", (26, 10, 16, 40)):
        ws.column_dimensions[col].width = width

    for col, head in zip("ABCD", ("Check", "MS", "Status", "Equation")):
        c = ws[f"{col}3"]
        c.value = head
        c.font = Font(bold=True)
        c.fill = PatternFill("solid", start_color=HEADER_BG, end_color=HEADER_BG)
        c.border = box
    for row in range(4, 19):
        for col in "ABCD":
            c = ws[f"{col}{row}"]
            c.border = box
            c.alignment = Alignment(vertical="center")
        ws[f"B{row}"].number_format = "+0.00;-0.00;0.00"
        ws[f"B{row}"].alignment = Alignment(horizontal="right")
    status_rules(ws, "C4:C18")

    wb.defined_names["MarginTable"] = DefinedName(
        "MarginTable", attr_text="Slide!$A$4:$D$18")
    wb.save(OUT / "export_probe.xlsx")


if __name__ == "__main__":
    probe()
    print("wrote", OUT / "export_probe.xlsx")
