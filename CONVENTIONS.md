# Conventions — Fastener Analysis Tool (MATLAB)

The rules the code and docs cite. Sections 1-5 govern everything; Section A
governs the GUI (`+gui`), and its A-numbers are cited from code comments.

## Project

Ground-up MATLAB build of a NASA-STD-5020B bolted-joint margin-of-safety tool,
packaged as a standalone Windows `.exe`.

## Critical rules

- **The answer key is the source of truth for the numbers.** Primary key: the
  **DABJ course book §9 public worked example**. Margins are only ever validated against a published worked example or an
  independent hand calculation — never against another implementation, whose
  numbers carry no traceable authority.
- **Engine is GUI-independent** and must run headless from the Command Window.
  The GUI is a thin shell over the engine API.

## Code conventions

- **Equation traceability (REQUIRED, everywhere an equation is used).** At the
  point of use, the comment MUST carry all three, together:
  1. the **reference document** (e.g. `NASA-STD-5020B`, `NASA TM-106943`),
  2. the **equation number** if one exists ("if applicable"), and
  3. the **equation written out**.
  Also surface the reference + number in the function's returned `Method` string
  (which flows into `Result`, reports, and the GUI). Example:
  ```matlab
  % NASA-STD-5020B Eq. 19 — MS = PpMin / Psep - 1
  MS = preload.PpMin / designLoads.Psep - 1;
  ```
  No bare "Eq. 19" without the written formula; no formula without the citation.
  Applies to every equation in `+engine` (and anywhere else math is implemented).

- **Document hierarchy — 5020B governs; supplements only where 5020B relies on them.**
  1. **NASA-STD-5020B is the governing standard.** Where 5020B provides the
     equation, cite 5020B (preload Eq. 3/4/5/24, tension Eq. 6, shear Eq. 14,
     separation Eq. 19, interaction Eq. 20–23, slip Eq. 84–86, …).
  2. **Supplemental docs** (NASA TM-106943 "Chambers", NASA RP-1228 "Barrett")
     are cited **only where 5020B itself relies on them** for a detailed formula
     5020B does not print — e.g. the thermal preload change `P_dT` (5020B Eq. 2
     uses the term; the CTE-mismatch formula is **TM-106943 Eq. 10**), and
     several thread-shear / bearing / insert failure modes 5020B defers to
     TM-106943. **Before citing a supplement, confirm 5020B does not give the
     equation itself.**
  3. **The DABJ course book is VALIDATION ONLY** — the worked-example "answer
     key." Never cite DABJ as a governing equation; use it only in
     "Validated against DABJ §N (Solutions-NN)" provenance notes.
  4. **Open:** `engine.stiffness` cites Shigley (frustum) and
     `tools/kc_exact_crosscheck.py` leans on SAND2008-0371; neither is in this
     hierarchy yet. Decide whether to admit them.

## Engineering ground rules (must be exactly right)

- **Interaction:** NASA-STD-5020B **Eq. 20–23** — not the simpler R²+R² form.
  Different exponents for threads-in-shear vs body-in-shear.
- **Thermal preload:** included, per TFSR 5.
- **Separation-before-rupture:** 5020B Fig 8 decision tree; the 0.75–0.85 × Ptu
  band conservatively assumes rupture when bolt-elongation data is unavailable.
- **Temperature:** engine works internally in **°C** (CTE data is 1/°C); other units US customary (in, lbf, psi);
  convert only at the GUI boundary.
- **Bolt length (nut config):** grip + nut height + 2·pitch.
- **Nut strength & insert pull-out:** COMPUTED thread-shear ultimate/yield pair
  (nut: group As = 0.75·π·E·Le × nut Fsu/Fsy; insert: shear engagement area ×
  parent Fsu/Fsy) as the FALLBACK. **A spec-rated ultimate load, when supplied,
  IS the nut's ultimate allowable** — not a ceiling on a computed one — per
  5020B §4.4.1 p26 ("based on the strength specified for that item **rather than
  on** thread-stripping analysis"); p27's "limited to the load rating" then holds
  automatically. A rated nut needs no material data for its ultimate. The YIELD
  criterion is never rating-based (a rating carries no yield information) and
  still needs area + Fsy. For an INSERT the rating is a different quantity
  entirely — the internal-thread allowable, on its own row — so insert pull-out
  is uncapped and "the lower value should be used" is applied ACROSS the two
  rows. (Both were CEILING rules until 2026-08-13/14.) Rating-only fallback (ultimate-only) when no area is available.
  Tapped holes stay ultimate-only (deliberate gap).
- **Flanges** = clamped stack only; insert/tapped-hole material is independent.

## Tech

- MATLAB, JSON for library + cases. The GUI is **programmatic** — `classdef <
  handle` on `uifigure` + `uigridlayout`, plain `.m` files. Never `.mlapp`
  (opaque packaged format: no line diffs, no merges, not reviewable) and never
  GUIDE (removed in R2025a). Target R2026a.
- Licensing available: MATLAB Compiler, Report Generator, Database Toolbox.
- Run: open MATLAB, `cd matlab`, then `fastenerTool` / `runTests`.
- **Tests: `runTests` for the full suite (required before every push);
  `runTests("engine")` while iterating on `+engine`/`+model`/`+data`/`+report`
  (seconds), `runTests("gui")` or `runTests("<PageName>")` for `+gui`.** The
  nine `tGui*` files build a real app per test method and are essentially the
  whole runtime. A green subset proves only what it ran — the suite has caught
  GUI tests broken by engine changes and vice versa, so neither half predicts
  the other.

## A. GUI invariants

These apply to every page. Violating one is a defect, not a style difference.

### A1. Unknown must never look like fine

`NotEvaluated` / `NaN` /
"couldn't run" states render **visually distinct from both pass and fail** —
an em dash `—`, never a blank, never `0.0000`, never `NaN`, never the muted
"everything's fine" style.

- A check that could not run is **amber**, not muted grey: the check is *not
  running*, and that must not read as *nothing to report*.
- `"ALL CHECKS PASS"` may never be shown when any check is NotEvaluated — it
  would overstate what the engine actually concluded.
- A bare `--` may never replace a real, meaningful number.

### A2. Never re-threshold in the view

Pass/fail comes from `Result.Margins(i).Status`. The view colors by that field
and computes nothing.

**`Interaction` is the trap.** It reports `R`, passing iff `R ≤ 1` — the
*opposite direction* from `MS ≥ 0`. Every consumer must route it through the
ratio-aware helpers (`gui.MarginView.isRatio` / `envelope` / `passFail`), never a plain `< 0` test. Two specific consequences:

- A failing interaction (`R > 1`) must still visibly fail the 5020B summary
  count, even though it never governs the worst margin.
- An envelope across load cases must not silently pick the **best**-case `R`.

### A3. Staleness discipline

Any displayed result carries a stale flag, an amber banner, and muted table
rendering the moment an input changes.

- **Reading a stale flag never sets it.** Switching to a page must not
  invalidate a result that was valid.
- **A failed run flags the previous table stale rather than leaving a confident
  verdict on screen** — and rather than clearing it.
- Muting is cosmetic and is **never allowed to break the numbers**: if styling
  is unavailable, the banner alone still says stale.
- Export/report buttons are enabled **exactly when** fresh, non-stale results
  exist.
- Warning banners are rebuilt from scratch on every render, never accumulated,
  and are refreshed **only** from the show-result path — refreshing them when
  the user starts editing would be anti-conservative.

### A4. Dirty-flag discipline

`markDirty` means *case state changed*. Trap: a dirty flag fed by only one page
silently discards unsaved work on File → New.

- Case state (joint, loads, factors, settings, defined joints, mapping, forces)
  **always** marks dirty.
- Selection changes, DB browsing, and scratch tools **never** mark dirty.
- Programmatic repopulation (`applyState`, `applyJoint`) must not mark dirty —
  a dirty flag there is a lie.

### A5. Auto-fill then lock — `Enable='off'`, never read-only

Library-resolved fields (nut spec → material / rated load / engagement /
bearing OD; washer spec+size → OD / ID / thickness) auto-fill and **lock**.

- Locking is `Enable='off'`. Never a read-only-but-editable-looking field.
- The **`Custom` manual path is permanent and is never removed.**
- A spec family with **no match at the resolved thread size reverts to `Custom`
  and says so in the status bar** — never leave numbers resolved for a
  different size looking authoritative.
- Changing the bolt **re-resolves every dependent picker** (nut spec, both
  washer specs). A library update never carries a stale value forward.
- Dropdown repopulation must save and restore the current selection, and must
  go through the set-items-and-data helper — a bare `Items` assignment while
  `ItemsData` is non-empty resizes inconsistently.

### A6. Required inputs start blank

A required dropdown (bolt material, flange material where the layer is in use,
member material) **starts blank, never on the first library item**. A silently
defaulted material dropdown analyzes the wrong material and looks deliberate.
Test for blank with the explicit sentinel helper, never `strcmp` against `''`.

### A7. Reset and load go through the deserializer

File → New, File → Open, and any reset repopulate via the same `applyState`
deserializer path used for case files — **never by setting literals per field**.
A field added later is then impossible to forget.

### A8. Table styling

`removeStyle` **before** every `addStyle` pass — styles otherwise accumulate,
degrading render time and producing wrong colors. Apply with an **N×2 index
matrix**, never one `addStyle` call per cell. Formatting helpers are shared
across Results and Bulk so the two can never drift.

### A9. Cross-type field crossing must clear, never convert

The engagement field means **ratio** for Insert and **inches** for Nut/Tapped
Hole. A ratio left behind from a former Insert would be read as inches — on a
#10-32 that is a plausible-looking number the analyst never entered.

**Clear on crossing.** Converting would silently swap the analyst's *intent*.
Same rule anywhere a field's meaning changes with a type selector.

### A10. Import is per-row, and names what it found

- Process rows independently — **one bad row never aborts the import**.
- Report what was actually wrong, never just "invalid file".
- Partial success is reported as partial — never silently half-worked.
- A clean parse that yields **zero usable rows must not look like success**
  (this is the dangerous case; it renders red).
- Raw imported element forces are never reformatted by a unit change; they
  display as imported, and a note says so.

### A11. Export reads controls at export time

Project metadata and factors are read from the live controls **at export time**,
never from values captured when the run happened — captured metadata goes stale
the moment a control changes. The workbook must be self-describing without the
app.

### A12. Empty states name the absence

Never a silent blank. `No standard NAS lengths for this thread size`,
`No saved joints — fill in fields and click Save` (with Load/Copy disabled),
`—` for an unknown nut height. Put the `uilabel` and the `uitable` in the same
grid cell and toggle `Visible`.

### A13. Identity collisions

Joint names collide **case-insensitively** — letting `JT-A` and `jt-a` coexist
is a mapping trap. A rename must not orphan the elements referencing the old
name.
