# PRD — Calculation Map

Status: **draft, 2026-09-28.** Delete once shipped; lasting rules move into
`GUI_SPEC.md`.

## 1. Goal

Anyone reviewing the MATLAB source can see **one flowchart per check**, from the
inputs through every intermediate quantity to the margin, and **click any box to
open that `.m` file in the MATLAB editor at the equation's line**. Dan: "that
would be really appreciated by folks."

This is possible now that the tool runs inside MATLAB (the `.exe` is dropped as
of 2026-09-28): `opentoline(file, line)` is MATLAB-only.

## 2. Decisions

| Question | Decision |
|---|---|
| Rendering | **Mermaid** in a `uihtml` panel. The library is bundled in the repo (MIT licence, about 3 MB), so it works offline. |
| Values | **Yes, when a result exists**: each box shows its formula plus the substituted value from the last Analyze (e.g. `PpMin = 6,470 lbf`). Formulas only when there is no result. |
| Opening it | **Help → Calculation Map**, and a **Show calculation** button on Results that opens the selected check's map |
| Kept current | **Built from the code when opened.** Never a hand-drawn picture that can drift. |

## 3. What a map contains

For the selected check, top to bottom:

| Box | Source | Example (Slip) |
|---|---|---|
| Inputs used | The check's recorded inputs (`Margins(k).Inputs`), otherwise the arguments `analyze` passes it | μ, nf, PtL-joint, PsL-joint, FFslip · FSslip |
| Intermediate steps | Each `engine.*` function (and `+engine/private` helper) the check draws on, e.g. `preload`, `designLoads`, `systemTensileAllowable`, `stiffness` | `preload`: Eq. 5, PpMinSlip = … |
| Equations inside a box | Every traceability comment in that function: reference, equation number, written-out formula, **line number** | `NASA-STD-5020B Eq. 84 — MS = …` at `marginSlip.m:NN` |
| The check | The margin function, its result and status | `marginSlip.m`, MS −0.65, FAIL |

Clicking a box opens its file at its first equation. Clicking an equation line
opens that exact line.

## 4. How the map is built (no hand-maintained wiring)

1. **Equations:** scan `+engine/**/*.m` for traceability comments, which
   `CONVENTIONS.md` requires at every equation (`% <reference> Eq. N — <formula>`),
   and record file, line, reference and formula.
2. **Edges:**
   - inside each function, calls to `engine.*` and to `+engine/private` helpers (bare names), with comments stripped;
   - in `analyze.m`, which earlier results (`p = engine.preload(…)`, `d = engine.designLoads(…)`) are passed into each margin call.
   This is the same derivation `ENGINE_FLOW.md` describes, done in code.
3. **Values:** from the current `Result`: `Preload`, `DesignLoads`, `Allowables`, and each margin's `Inputs`, `MS` / `R` and `Status`.

It lives in a pure function, e.g. `engine.calculationMap(checkName)`, testable
headless, which returns nodes, edges and equations with `file:line`. The window
only draws it.

**Side benefit:** the scan finds equations that are missing their traceability
comment, and a test can report them as a `CONVENTIONS.md` violation.

## 5. Window

- `gui.CalculationMapView`: a check picker (all 15) and a `uihtml` panel. It's a secondary window like the cross-section: create-or-focus, and closed with the app.
- MATLAB sends the Mermaid text plus a node → `file:line` table into the page. A click goes back to MATLAB via `sendEventToMATLAB` and runs `opentoline`.
- Legend: pass / fail / not-evaluated colours match the app.

## 6. Tests

| What | How |
|---|---|
| Every check has a map | `engine.calculationMap` for all 15 names returns a margin node plus at least one equation |
| Every link is real | Each `file:line` exists, and that line holds the equation comment it claims |
| The map follows the code | Slip includes `preload` and `designLoads`; Tension-Ultimate includes `systemTensileAllowable`. A few known edges are pinned. |
| Traceability audit | List every equation-shaped line with no comment. Report-only at first. |
| The window opens | Help → Calculation Map builds a view and shows a check (the drawing itself is checked by eye) |

## 7. Phasing

| Phase | Ships |
|---|---|
| **(a)** | `engine.calculationMap` plus tests. No UI. I also print the maps as text so you can sanity-check them. |
| **(b)** | The window: Mermaid bundled, click → `opentoline`, Help menu item, and the Show calculation button on Results |
| **(c)** | Values from the current result on each box |
| **(d)** | You and a colleague use it on a real review; we adjust |
| **(e)** | **User guide:** a page on using the map, plus an **appendix** with all 15 flowcharts (formulas and `file:line` as text, no values, no click-through) generated from `engine.calculationMap` by a script. A test fails if the appendix is stale. The appendix pages use the bundled Mermaid, an accepted exception to the guide's no-JavaScript rule. |

## 8. Risks

| Risk | Mitigation |
|---|---|
| Static call parsing misses an indirect call | The tests pin known edges. Anything missed shows as a missing box, never a wrong number. |
| `uihtml` ↔ MATLAB events and Mermaid click handlers | Proven in phase (b) before styling. The fallback is a dropdown of the check's equations with an Open button. |
| Six checks don't record their `Inputs` yet | Those boxes show formulas without values until they're wired. Say so in the box, never leave it blank. |
