# PRD — Exports

Status: **draft, 2026-09-24.** Delete once shipped; lasting rules move into
`GUI_SPEC.md`.

## 1. Problem

Dan reviewed all three exports: the PDF report, the single-joint Excel and the
bulk Excel. His verdict: **they look bad and are hard to follow.**

The real destination is **PowerPoint**. Results end up on slides that have to be
easy to understand at a glance. The current exports are calc-document dumps:
- the PDF opens with one long table of every input;
- the Excel sheets are bare `writetable` output with no styling or pass/fail colour
  and no summary.

## 2. Decisions (from Dan's answers)

| Question | Decision |
|---|---|
| How results reach PowerPoint | **Formatted Excel**, copied and pasted into slides |
| PowerPoint template | None; keep it plain and neutral |
| What a single-joint slide shows | **Verdict headline, margin summary table, key inputs, joint cross-section** |
| Detailed calc PDF for the checker | **Keep it, but fix it** |
| How the Excel is styled | A **styled template** `.xlsx` shipped with the tool; MATLAB fills in values only. It works in the `.exe` with no Excel installed. |
| Bulk | The **full results sheet** stays, now formatted. See open question 1 for the summary sheet. |

## 3. Single-joint Excel (Results → Export Table…)

| Sheet | Contents |
|---|---|
| **Slide** | Laid out to be copied as one block onto a 16:9 slide (fixed range, fixed column widths, no gridlines). Top to bottom: **verdict headline** (worst margin and governing check, or "N not evaluated", coloured like the Results verdict), **key inputs** (bolt, bolt material, stack, threaded member, torque and K, PtL / PsL, factors, temperatures), **margin table** (Check · MS or R · Status · Equation), with pass / fail / not-evaluated colours from the template's conditional formatting on the Status column |
| **Detail** | Per check: the equation written out, the substituted inputs (the Results detail panel's content) and the Method string |
| **About** | Tool, version, run time, Project rows, scope note (as now) |

**The cross-section** is saved as `<name>_section.png` beside the workbook, using
`exportgraphics` on the section view's axes. That doesn't use `exportapp`, which
failed on busy app states. A template-filled workbook can't embed a picture.

Rules carried over:
- Interaction shows **R** with its own pass rule (A2).
- A not-evaluated check shows `—` in amber, never blank (A1).
- The verdict never says "all pass" while anything is not evaluated.

## 4. Bulk Excel (Bulk Analysis → Export…)

| Sheet | Contents |
|---|---|
| **Results** | Every element × load case, as now, but **formatted**: frozen header, filter, number formats, conditional pass / fail colour on every margin column, Interaction R ratio-aware |
| Summary | See open question 1 |
| **About** | As now |

Always the complete result set, whatever the on-screen filters show (as now).

## 5. Calc PDF (Results → Save PDF Report…), kept and fixed

The checker's document. Same content, reordered to be followable:
1. **Page 1 = the Slide sheet's content**: verdict, key inputs, margin table, cross-section.
2. Project and scope.
3. **One section per check**: the equation written out, the substituted numbers, the result and status. The Results detail panel already builds this per row, so the PDF reuses it.
4. Inputs **grouped as on Joint Config** (Bolt, Washers, Flange stack, Threaded member, Preload, Loads, Assumptions), not one long table.
5. Preload and design loads, then warnings.

It shares the calc report's existing styled-table and colour code.

## 6. Mechanism

- Templates live in `matlab/templates/`: `export_single.xlsx` and `export_bulk.xlsx`. Styles and conditional-formatting rules are made in Excel once and committed.
- MATLAB writes with `writecell` / `writetable` using `PreserveFormat = true` and `UseExcel = false`, so no Excel is needed at run time.
  **To verify in phase 1:** that formatting survives this path in R2026a for `.xlsx`.
- A template-to-code contract test: the cell addresses the code writes to are named ranges in the template, and a test fails if one goes missing.
- The build line gains `-a templates` (today it bundles only `+data/library` and `userguide`).

## 7. Tests

| What | How |
|---|---|
| The values land in the right cells | Write the answer-key case, read back with `readcell`, and check the six margins, statuses and the verdict text |
| Interaction is ratio-aware | Construct a result with a failing R and check its Status cell reads FAIL |
| Not evaluated is never blank | A not-evaluated row's MS cell is `—` |
| Bulk export is complete | Row count equals element × load-case count |
| The PNG is written | The file exists and is non-empty (skipped where graphics are unavailable) |

Visual quality is checked by Dan, in Excel and pasted into PowerPoint.

## 8. Phasing

| Phase | Ships |
|---|---|
| **(a)** | Single-joint template, the Slide / Detail / About sheets, the section PNG, and tests. Confirm `PreserveFormat` first. |
| **(b)** | The bulk template with the formatted Results sheet (and a Summary sheet, if wanted) |
| **(c)** | The calc PDF reorder |
| **(d)** | Dan pastes real results into a deck and we adjust |

## 9. Open questions

| # | Question |
|---|---|
| 1 | **Bulk summary sheet:** is the formatted full Results sheet enough, or do you also want a slide-sized summary: one row per joint (worst margin, governing check, where it occurs) plus pass / fail counts? |
| 2 | Slide sheet orientation: the margin table beside the inputs (wide) or below them (tall)? |
