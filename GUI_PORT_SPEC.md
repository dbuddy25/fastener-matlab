# GUI Spec — Phase 4

Design spec for the MATLAB GUI: the information architecture, the
conditional-field logic, the validation strategy, the output presentation, and a
long tail of usability details that are cheap to build and expensive to
rediscover.

**This is a spec for the *flow*, not a layout drawing.** What it fixes is which
information sits where, what recomputes when, how failures are surfaced, and
what the app refuses to do silently.

Tags used throughout: **BUILD** (build as written) · **ADAPT** (good idea,
MATLAB needs a different mechanism) · **SKIP** (not worth it).

---

## 1. Information architecture

Eleven tabs, in this order. The order is not arbitrary: 1–3 are the single-joint
loop, 4–7 are the bulk loop in execution order, 8–11 are reference/utility.

| # | Tab | Role |
|---|-----|------|
| 1 | Project & Factors | Units, project metadata, safety factors, presets |
| 2 | Joint Config | Define one joint + loads; **Analyze** lives here |
| 3 | Single Joint Analysis | Margin output for one joint |
| 4 | Defined Joints | Named joint library |
| 5 | Element Mapping | FE element ID → joint name |
| 6 | Element Forces | Force import per load case |
| 7 | Bulk Analysis | Run + 3-tier results + export |
| 8 | Bolt Sizing | Standalone sizing sweep; optional Threaded member context (None/Nut/Insert/Tapped Hole, mirroring Joint Config's nut-spec picker — `engine.boltSizingSweep`'s `Library`+`NutSpec`/`ThreadedMember` args) lets `MS_TensionUlt` use the fastening-system allowable instead of staying bolt-only. Tracks its own staleness (`BsStale`, same amber-banner/muted-table mechanism as Results/Bulk — an input edit here *or* a Project & Factors/temperature change elsewhere flags a shown sweep table stale); a failed Sweep is caught and reported the same way as a failed Analyze, leaving the previous table flagged stale rather than looking current |
| 9 | Materials & Hardware DB | Library editor |
| 10 | User Guide | → external PDF (see §8) |
| 11 | References | → external PDF (see §8) |

Tab names were chosen deliberately for what an analyst is looking for:
`Project & Factors` (not `Setup`), `Defined Joints` (not `Joint Library`),
`Materials & Hardware DB` (not `Libraries`). **Use these names.**

### Order is suggested, never enforced — four escalating mechanisms

No tab is ever disabled. Prerequisites are communicated by:

1. **Per-tab status hints** — set `app.StatusLabel.Text` from the tab group's
   `SelectionChangedFcn`. e.g. *"Bulk — step 3 of 4: run analysis after mapping
   and forces are loaded."*
2. **Empty-state placeholders** that replace the content — when a table has zero
   rows, hide it and show an info banner spelling out the whole workflow. Put
   both the `uilabel` and the `uitable` in the same grid cell and toggle
   `Visible`. This is the single best onboarding device in the app.
3. **Default summary text** on output pages before any run.
4. **Run-time pre-validation — the only hard gate.** On failure show a dialog
   listing the problems *plus navigation buttons that jump to the tab where the
   fix lives*:
   `uiconfirm(fig, msg, 'Cannot Run', 'Options', {'Go to Element Mapping', 'Go to Element Forces', 'Go to Defined Joints', 'Close'})`
   then set `app.TabGroup.SelectedTab`.

**The philosophy, worth stating once:** suggest with signs, enforce only at the
moment of truth, and always point at the fix.

> **Number the bulk workflow once.** Step numbering that disagrees between the
> status hints and the page placeholders (1/2/3 in one place, "2 of 3" in
> another) is a guaranteed support question. Use a single 4-step scheme
> everywhere: 1 Define Joints → 2 Element Mapping → 3 Element Forces →
> 4 Run Bulk.

### Auto-switch on analyze — **BUILD**

Pressing Analyze populates the results tab *and switches to it*, with the
governing margin row pre-selected. The user never navigates to results manually.

---

## 2. App shell

| Element | Mechanism | Verdict |
|---|---|---|
| Tabs | `uitabgroup` | **BUILD** |
| Sub-tabs | nested `uitabgroup` (Bulk = 3 tiers, DB = 5 entity types) | **BUILD** |
| Menu bar | `uimenu` on `uifigure` (R2020a+) | **BUILD** |
| Status bar | `uilabel` in the bottom row of the root grid + one `app.setStatus(msg)` | **ADAPT** |
| Toolbar | none global; each page owns a button row at its top | **BUILD** |
| Scrolling | `Scrollable='on'` per tab grid | **ADAPT** |
| Splitters | no MATLAB equivalent — hard-code the ratios: Results `{'2x','3.5x','2x'}`, Defined Joints `{'1x','2x'}`, Forces `{'1x','2x'}` | **ADAPT** |

**Window title** carries three pieces of state:
`Fastener Analysis Tool v0.1.x — NASA-STD-5020B Compliant` when nothing is open;
`Fastener Analysis Tool — /path/case.json` when a file is open;
prefixed `* ` when dirty. One `app.updateTitle()` reads `CurrentFile` + `IsDirty`.

**Menu bar:**
```
File   New | Open... | Open Recent > | Save | Save As...
       Import Joints from File...
View   [ ] Dark Mode          (see §9 — defer)
Help   User Guide | Equation Reference | Changelog
```
*Open Recent*: max 5, persisted, non-existent paths filtered, disabled
`(no recent files)` item when empty. Cheap, and users love it.

### State sharing — **ADAPT**

MATLAB has no signals/slots, and a switchboard of ad-hoc callbacks wired between
pages does not survive the eleventh tab. **Use a single `handle`-derived
`AppState` object** held by the main app and passed to every tab builder. Pages
read/write it directly and call explicit `app.notifyXChanged()` methods that do
the fan-out. Simple and debuggable; skip the `events`/`notify` machinery.

**Lazy tab-switch sync:** `SelectionChangedFcn` refreshes the entering tab from
`AppState`. Avoids maintaining N² live bindings.

### Case file format

```json
{ "format": "fastener-analysis-matlab-v1",
  "joint": {...}, "factors": {...}, "library": {...},
  "mapping": {...}, "forces": {...} }
```

> **`mapping` and `forces` are in the case file from day one.** Leave them out
> and a user who sets up a 200-element bulk run and saves loses both without
> being told.

> **Mark dirty from *every* editable page, and always confirm when dirty.** A
> discard-confirm that returns immediately because no file is open lets File→New
> silently destroy a whole fresh session's unsaved work.

---

## 3. Joint Config — the guided form

Single scrolling column of labelled groups. A two-panel splitter layout was
built and **rejected by the user as feeling worse** — that is a settled
decision, do not revisit.

Group order encodes the analyst's workflow:

1. **General Joint Definition** — Joint Name (own full-width row, min 350 px, it
   was truncating), then 2×2: Thread Size / Bolt Material, Bolt Length /
   Threaded Member
2. **Analysis Options** — threads-in-shear checkbox, Slip Mode, Override μ,
   Separation Critical, Frustum Angle, Bolt Axis, # Bolts
3. **Washer Under Bolt Head** — Present, Material, Type, OD/ID/Thk
4. **Clamped Flanges** — count spinner + 7-column grid: Name, Material, Hole
   Fit, Hole Dia, Thickness, Edge Dist, Tearout
5. **Insert / Tapped Hole Details** *(conditional)* — Host Material, Engagement
6. **Nut Details** *(conditional)* — Nut Material, Nut Height (read-only)
7. **Washer Under Nut** *(conditional)*
8. **Preload Definition** — Mode, torque/K/Γ/relaxation, preload readout
9. **Service Temperatures** — Nominal / Hot / Cold
10. **Applied Loads** — Axial / Shear / Bending, then Preview + Analyze
11. **Defined Joints** — joint dropdown + Save / Load / Copy

### The reactive logic — highest-value section, build all of it

This is the entire difference between a guided form and a bare grid of 62
numeric fields.

**Thread Size is the master key.** Changing it cascades, in order:
repopulate bolt lengths (*preserving the current selection if still valid*) →
re-lookup head washer dims → re-lookup nut washer dims → recompute all four
flange clearance holes → refresh nut height → recompute bolt-length adequacy →
recompute preload readout → re-lookup torque spec.

**Threaded Member swaps groups.** `Nut` shows groups 6+7, hides 5.
`Helical Insert` / `Tapped Hole` shows group 5 **and retitles it** to
`<selection> Details`, hides 6+7. Also re-runs required-field validation,
because the required set differs per branch.

**Auto-fill then lock.** Washer Type and Hole Fit populate their numeric fields
from the library and **disable** them; `Custom` re-enables. Nut washer
`Same as Head` mirrors the head washer live.

Built for nuts first (`NutSpecDropDown` → `data.Library.nutFor`, resolving rated
ultimate load / engagement length Le / bearing face OD / member material against
the selected bolt's thread). **Washers and inserts are the same job still to
do** — both library sections are empty, so washer OD/ID/thickness and the insert
allowables are still typed by hand. Washers add two wrinkles nuts did not have:
three dimensions rather than one, and the nut-washer `Same as Head` mirror,
which has to keep working while a spec drives the head washer.

**Deferred — open the selected spec sheet.** A button beside the spec picker
that opens the governing drawing (NASM21042, NAS1291, …) for whatever is
selected, so the rated load on screen is one click from its source. Needs a
decision on where the PDFs live: they are licensed AIA/Accuris drawings,
watermarked per-user, deliberately not in the repo, and a packaged `.exe` cannot
assume a path on the analyst's machine. Likely a library field holding a path or
URL resolved at click time, degrading to a clear message when unset rather than
a dead button.

**Enable, never read-only.** Locked fields must visibly gray out. A field that
is read-only but still looks editable draws clicks: users click in, type, and
wonder why nothing happens. Always `Enable='off'`.

### Two live labels do the real safety work

Both recompute on every relevant edit, *before* Analyze is pressed.

**Bolt-length adequacy** (4 lines, muted gray when OK, **bold red** when short):
```
Grip: 0.5630 in
Engagement 1.5D = 0.3750 in     (or: Nut 0.3438 + 2P 0.0714 in)
Min bolt: 0.9380 in
Selected: 1.0000 in OK          (or: TOO SHORT by 0.0620 in)
```

**Preload watchdog** — `Pp = T/(K·D)`, `%yield = Pp/(Fty·At)`, four bands:

| Band | Text | Style |
|---|---|---|
| ≤85% yield | `Nominal Preload: 4264 lb (62% yield)` | normal |
| >85% | same | bold amber |
| >100% yield | `… — EXCEEDS YIELD. Bolt may permanently deform.` | bold red |
| >100% ultimate | `… — EXCEEDS ULTIMATE (108% Ftu). Bolt may fracture!` | bold red |

Cheap to implement, and it catches an over-torqued joint before analysis.

### Dropdowns

- Display text is the **raw name** (`7075-T73 Plate`) — no composite
  `name — spec` strings. Selections round-trip by name.
- Thread sizes sort by **physical size, UNC before UNF at the same size** — never
  alphabetically (`#10-32` must not sort next to `1/4-28`).
- Bolt lengths display as **decimal** `0.750"`, not fractional `3/4"`.
- Only two real dependencies: thread size → bolt length list, and torque spec
  name → lubrication list. **Selecting a bolt does NOT filter nuts or materials**
  — nut data is resolved silently by thread size. Do not invent a nut dropdown.
- `Custom` / `(All)` / `(Custom)` are **sentinel items appended to fixed lists**,
  not library rows. Parenthesised for filter/preset lists, bare for geometry.
- **Every repopulation must save and restore the current selection:**
  cache `dd.Value` → set `dd.Items` → `if any(strcmp(saved, dd.Items)), dd.Value = saved; end`.
  (MATLAB doesn't fire callbacks on programmatic `Value` sets, so no
  signal-blocking is needed — the save/restore half is the essential half.)
- `uidropdown` doesn't auto-fit. Give dropdown columns explicit widths sized to
  the longest item (~`7 × maxChars` px). Budget ~170 px for washer types — they
  truncate at anything narrower.

### Validation — three complementary layers, build all three

**Layer 1 — continuous required-field checking.** Three material dropdowns
(**Bolt**, **Host**, **Nut**) start deliberately **blank**; a dropdown that
defaults to a material silently analyzes the wrong material. The required set is
conditional on threaded-member type. Empty ones get a red visual, and the
**Analyze button is disabled with a tooltip naming exactly what's missing**
(`Required fields missing: Bolt Material, Host Material`).
MATLAB has no CSS — set `BackgroundColor` to pale red `[1 0.90 0.90]` and
restore to white, or toggle a wrapping panel's `BorderColor`.

**Layer 2 — widget-level constraints.** Use `Limits`, `RoundFractionalValues`,
and `ValueDisplayFormat` (e.g. `'%.5f in'`) rather than hand-rolled validation.

**Layer 3 — build-time errors on Analyze.** `uialert` titled `Input Error`.
**The message convention:** name the field *as the user sees it*, say what
to do, and say which tab. e.g.
*"Bolt Material is required — select a material on the Joint Config tab"*.
Never surface an internal key name.

**Defaults must be mutually consistent.** A default bolt of `#2-56` sitting
beside a default torque of 55 in-lb (sized for 1/4-28) produces a false failure
on first launch. Keep the default set a coherent, passing joint.

### Tooltips — the cheapest high-value item in the build

49 tooltips of pure data (no logic), each following a fixed three-line contract:

```
Line 1 — field name (and symbol)
Line 2 — definition paraphrased from the standard
Line 3 — citation (standard, equation or section number)
```

Write them once as a MATLAB function returning a struct, with every line checked
against the standard, and assign `.Tooltip` per component. Keep flange tooltips
**per column, shared across rows** (7 strings, not 28).

---

## 4. Results — single joint

Layout, top to bottom:

```
[ Joint: JT-A — 2 FAILURE(S) — Controlling: Joint Separation = -0.14 ]  [x]Cap MS>5  [Export...]
[ WARNING: bolt length ... ]                              (amber banner, hidden when OK)
[ WARNING: preload ... ]                                  (red banner, hidden when OK)
Preload Summary          |  Stiffness Summary
MARGIN TABLE (4 columns, see below)
Detail View — <selected check>
```

### Margin table — 4 columns, solver order, no sorting

| Col | Header | Content |
|---|---|---|
| 1 | Check | `Ultimate Tensile (Bolt)`, `Joint Separation`, … |
| 2 | Value | `MS = +0.32` / `MS = -0.14` / `MS = >+5`; interaction rows show `R = 0.86` |
| 3 | Status | `PASS` / `FAIL` / `N/A`, colored |
| 4 | Equation | `5020B Eq. 20` |

**Four columns, deliberately — there is no fifth "Key Intermediates" column.**
`engine.Result.Margins` carries no intermediates dictionary; its fifth field is
the free-text `Detail` string, which is long, truncates badly in a column, and
(for the Fig. 8 rows) duplicates both the detail pane and the narrative panel.
`Detail` therefore lives **only in the detail pane**, shown in full for the
selected row. Do not add it as a column — and the Bulk tables (build Step 6,
§5) follow the same rule: no `Detail` column, margins/status only.

**Number formatting (literally this):** `inf` → `+inf`; `>5.0` with cap on →
`>+5`; `≥0` → `+%.2g` (explicit plus); `<0` → `%.2g`.

**"Cap MS > 5" checkbox, default ON**, display-only, tooltip saying so. Without
it, a table of `+47.3`, `+112.8`, `-0.14` buries the only number that matters.
Cheapest readability win in the app.

**Pass/fail — three redundant channels:**
1. Status cell background: pass `[0.78 0.94 0.78]`, fail `[1 0.78 0.78]`, N/A grey.
2. **Asymmetric row emphasis:** on FAIL, the Check and Value cells are *also*
   painted red — a failure reads as a red band, a pass as a small green chip.
   Keep the asymmetry; it stops the table becoming a green wall.
3. Bold colored summary label at top.

> `uistyle`/`addStyle` implementation note: **call `removeStyle(t)` before
> re-applying on every rebuild**, or styles accumulate and mis-index once the row
> count changes. Build the three styles once and batch `addStyle` with an Nx2
> index matrix — far faster than per-cell calls on a 500-row table.

**Governing check gets two treatments:** named in the summary label, *and* its
row is auto-selected and scrolled to, so the detail pane is already showing its
derivation when the user arrives. Note: setting `t.Selection` programmatically
does **not** fire `SelectionChangedFcn` — invoke the callback manually.

**Detail view** — 2-column `uitree` (`Parameter | Value`) rebuilt on row
selection: Check Name, MS, Criterion, Status, Governing Equation, Formula, then
an expanded "Intermediate Values" node. Note the precision split: **2 sig figs
in the table, 6 sig figs in the detail tree.**

### ⚠️ Where §4 outruns what `engine.Result` actually carries

An earlier draft of this section assumed a richer result object than the engine
produces. The resolutions are recorded here, from the Step 2 build, so nothing
downstream re-assumes them:

| Draft assumed | Engine reality | Resolution |
|---|---|---|
| Column 5 "Key Intermediates" | No intermediates dict; `Margins` has a free-text `Detail` string | **Table is 4 columns** (Check/Value/Status/Equation); `Detail` shows only in the detail pane. (First cut made `Detail` column 5, which showed the same string up to three times — column, detail pane, narrative panel. Removed.) |
| "Stiffness Summary" panel | No stiffness block on `Result` | Show **Preload** + **Design Loads** (Ptu/Pty/Psu/Psep) |
| Detail `uitree`, 6-sig-fig intermediates | Only `Name`/`MS`/`R`/`Status`/`Method`/`Detail` per margin | Flat detail pane; MS (or R, for Interaction) at 6 sig figs (table shows 2-3) plus the full wrapping `Detail` text — the pane's job is exactly what the 4-column table cannot carry. When a row's `Detail` *is* `Result.Narrative` (engine carries `tu.Decision` on the Tension-Ultimate and Separation-before-rupture rows AND on `Narrative`), the pane points at the labelled narrative panel below instead of repeating it |
| Amber "bolt length" / red "preload" warning banners | **`Result` has no warnings collection at all** | Not built. Needs an engine `Warnings` field first — see below |
| Interaction rows display `R = 0.86` | `engine.marginInteraction` now returns the ratio `R` (Pass iff `R <= 1`) on its own field, carried onto `Result.Margins(k).R` alongside (never inside) `MS`, which stays `NaN` for that row by design (see `engine.analyze`'s INTERACTION IS NOT A MARGIN note) | **Built as originally intended.** The Results table's Value cell shows `R = 0.86 (<=1)` (read from `Margins(k).R`) instead of the usual signed-MS text; the detail pane retitles its "Margin of Safety:" caption to "Interaction Ratio (R <= 1):" for that row. Same treatment in the PDF (`report.singleJointReport`) and the Bulk grid/export (`InteractionR` column, `gui.FastenerApp.isRatioColumn`/`envelopeAcrossRows`/`passFailMask`) — see §5 below, which now needs its own correction. |

**The warning banners are the one real gap.** The bolt-length and preload
warnings are computed live on the *input* page (§3), not derived from the
result — so they are a Joint Config feature, not a Results one. Getting them
onto this page means either recomputing in the GUI (**forbidden** — no analysis
logic) or adding a `Warnings` field to `engine.Result`. **Prefer the engine
field:** the same warnings belong in the PDF and the bulk export too, and the
engine already has every input needed to raise them.

> **Put the logic-flow narrative on screen.** The Fig. 8 separation decision
> tree, plus a narrative explaining *which equation was chosen and why, and
> which checks were skipped and why*, is the highest-value content in a
> compliance tool — writing it only to the PDF and never showing it wastes it.
> Give the narrative a fourth pane or sub-tab (a 3-column table
> `Step | Result | Detail` is enough). **Skip** the hand-painted flowchart.

**Stale results.** After a result is shown, any case edit (every editable
control funnels through `markDirty`), a File New/Open, or a *failed* Analyze
flags the display stale: the row-1 banner turns amber ("results are for a
previous joint definition — press Analyze"), the verdict headline and table are
muted. The result is deliberately **not cleared** — the user may want to read it
while editing. Navigation (tab switches, the cap toggle, row selection) never
calls `markDirty`, so browsing cannot invalidate a result. Only a successful
`showResult` clears the flag.

The Bulk Analysis (`BulkStale`) and Bolt Sizing (`BsStale`) tabs mirror this
exact mechanism for their own results tables. Bolt Sizing's own inputs
(loads, material, threaded-member picker) are not part of the saved case and
never call `markDirty`, but they DO call the same staleness flag directly,
*and* `markDirty` itself flags Bolt Sizing too — so a Project & Factors or
temperature edit (invisible to this tab's own controls, since Factors are
only ever read live, never duplicated) still stales a shown sweep, and a
failed Sweep is caught and reported the same way `onAnalyze` reports a
failed Analyze.

---

## 5. Bulk analysis

**Toolbar:** `Run` | `Export XLSX` | `Export Element PDF` | Filter `[All Joints]`
| `[ ]Failures Only` | `[ ]Show Supplemental` | `[x]Cap MS>5`

Run lives on the *results* page — the user runs from where they'll read the
answer.

**Summary line** splits the counts deliberately:
`12 joints × 6 LCs = 72 analyses — 5020B: 65 PASS, 7 FAIL | Supplemental: 70 PASS, 2 FAIL`
A bearing-margin failure must not read as a code non-compliance. **Keep the split.**

**Three tiers as sub-tabs:** Joint Summary (one row per joint, envelope across
load cases, with a `Driving LC` breadcrumb column) → By Load Case → By Element
(one row per element × load case). Joint labels are composite:
`JT-A (1/4-28 UNF, A-286)`.

*Simplification:* implement Tier 2 as a load-case dropdown over one table rather
than a vertical stack of N tables — ~⅓ the code, and it loses only a
side-by-side comparison the stack barely provides.

**Margin columns are discovered, not hard-coded.** Walk all results, collect
unique margin names in solver order, split into the 5020B group (tension,
yield, shear, separation, slip, `InteractionR` — with **`InteractionR` forced
to the end**) and everything else as supplemental. Screen shows 5020B unless
"Show Supplemental" is ticked; **export always includes both.** This means adding
an engine check produces a column with zero GUI changes — exactly right for a
GUI that holds no analysis logic.

**Cell coloring:** `None` → `--` grey; **every ordinary margin column passes
when `MS ≥ 0`** — EXCEPT `InteractionR`, which is the one column that must
be treated the way this section used to warn against *not* doing.

> ⚠️ **`InteractionR` is the deliberate exception to every rule in this
> section — the opposite of the earlier note here.** `engine.marginInteraction`
> reports the ratio `R` (5020B Eq. 20-23 is a pass/fail *criterion*, `R ≤ 1`,
> not a margin equation), carried on `Result.Margins("Interaction").R`
> (never inside `.MS`, which stays `NaN` for that row by design).
> `engine.analyzeBulk` sources its `InteractionR` column from that `.R` field
> directly, NOT from the generic `.MS` pull the other 14 columns use — so
> this ONE bulk-table column holds a real number on the OPPOSITE-direction
> scale from every other column here: it **passes at `R ≤ 1`**, and its
> Tier 1/2 "worst case across load cases" is a **MAXIMUM**, not a minimum
> (a larger `R` uses up more of the envelope and is worse — the opposite of
> an ordinary margin, where the worst case is the smallest number).
> Applying the generic `MS ≥ 0` / `min()` rule to this column would colour a
> failing `R = 1.2` green and pick the *best*-case `R` as a joint's "worst"
> interaction result. `gui.FastenerApp.isRatioColumn` names which discovered
> column gets this treatment; `envelopeAcrossRows` and `passFailMask` are the
> two shared helpers every tier (screen and XLSX export alike) route through
> instead of the raw `min()`/`>= 0` MATLAB used to use directly — a future
> ratio-type check is a one-line addition to `isRatioColumn`, not a rewrite
> of this section's logic.

**Finding failures:** Failures-Only checkbox + joint filter + read Tier 1 first,
then drill down. **Add `ColumnSortable = true`** on Tiers 1 and 3 — MATLAB gives
it free, and sorting Tier 1 by interaction instantly ranks joints by criticality.

**Add a "Show in Single Joint Analysis" drill-down button** — push the selected
element's result into the Results tab and switch to it. All the plumbing already
exists, and it replaces a 30-second export-and-open with a click. Highest-value
addition to this page.

**Export — Setup sheet first.** The reproducibility record: analysis metadata,
export date, software version, display units, pass/fail totals, the six factors,
and a table of every joint configuration. The exported workbook must be
self-describing without the case file. Read metadata from `AppState` **at export
time**, not at run time — read it at run time and any metadata edited afterwards
ships stale.

Conditional fills are most of an export's value on a 500-row sheet. `writetable`
can't do them; Excel COM automation can, and Windows is the deployment target.
Fall back to values-only gracefully.

---

## 6. Library editing + baseline protection

Two different things share the word "library" — keep them straight:
**Materials & Hardware DB** (app-wide, survives case files, protected) vs
**Defined Joints** (a dict inside the case JSON, unprotected).

**Structure:** a `Source:` filter (`All`/`Official`/`Custom`) above 5 sub-tabs
(Materials, Bolts, Nuts, Inserts, Torque Specs), each an identical
"table + button bar". **Write one parameterised `buildLibrarySection(parent,
entityType, appState)` and call it five times** — do not write five near-identical
tabs.

**Interaction model, worth stating because it's the opposite of what most people
build:** editing an existing row is **inline** (double-click, type, commit
straight to storage — no Save button); **adding** a row is a modal form dialog.

MATLAB's `ColumnEditable` is per-column, not per-cell, so enforce in
`CellEditCallback`: if the row is baseline and admin is off, revert `t.Data` and
`uialert("Official entries are read-only. Use Duplicate as Custom.")`. Also grey
the row via `uistyle` so the block is telegraphed rather than discovered after
typing.

### Add `Source` to `data.Library` now — recommended

The MATLAB `data.Library` deliberately has no baseline-protection concept. Add
one:

1. `Source` field (`"baseline"` | `"custom"`) on every record.
2. `addMaterial`/`addBolt`/`addBoltSpec` default to `custom`.
3. `save()` writes **only custom rows**; baseline comes from shipped seed data at
   load time and the two are merged.
4. Add `duplicateAsCustom(key)`.

Three reasons, in priority order:

- **Upgrade safety.** Without a source split, `save()` writes the whole merged
  table to the user's file. Ship a corrected A-286 Ftu and the user never sees it
  — their stale file wins forever. This is a data-correctness problem, not a UI
  one.
- **Compliance traceability.** "Was this allowable the shipped reviewed value, or
  something an analyst typed?" must be answerable from the output.
- **Cost asymmetry.** Adding the field now is ~an hour. Retrofitting after users
  have saved libraries means a migration that *guesses* which rows were baseline.
  There is no good guess.

Visual distinction is one glyph in column 1: **🔒** baseline, **✏** custom.
No color, no separate table.

**The key UX move: `Duplicate as Custom` works on any row.** A user who wants to
tweak a baseline material duplicates it (name gets a ` (Custom)` suffix) and edits
the copy. Protection without an escape hatch just makes people angry.

**Skip admin mode initially** — duplicate-as-custom covers ~95% of the need, and
curating the shipped baseline is better done by editing seed files directly.

**Any DB change must refresh dependent dropdowns**, or a newly added material is
invisible until restart.

### Defined Joints

Two views behind a toggle. **Summary**: name list (left, 1:2 split) + grouped
read-only summary + a bold "Load into Joint Setup" button. **Bulk Edit**: a
13-column editable grid of the fields people actually sweep (name, thread size,
material, length, threaded member, axis, torque, K, Γ, relaxation, 3 temps).
MATLAB's `ColumnFormat` maps almost 1:1 — a cell-of-strings column format renders
as a dropdown. Keep the honest note that flanges/washers are edited elsewhere.

CSV detail worth having: write thread size as `="1/4-28 UNF"` so Excel doesn't
reinterpret it as a date, and strip on read.

---

## 7. Import / mapping — what the GUI adds over a file reader

`data.loadElements` stays the parser; all of this lives in the GUI layer:

| GUI adds | Why the reader can't |
|---|---|
| Merge vs Replace on import | Requires knowing current state |
| Min/max range preview per load case | Reader has no place to show it |
| Editable per-LC scale factor + reversible flag | Post-load mutation |
| Cross-validation mapping ↔ forces | Requires two datasets at once |
| Unknown-joint stub creation | Requires writing a third dataset |
| Bulk add / bulk assign / duplicate detection | Interactive editing |
| Per-line error reporting with recovery | Reader throws; GUI must degrade |

**Element Mapping highlights:** bulk-add dialog (paste IDs separated by commas /
newlines / spaces, invalid tokens reported individually while valid ones still
import) · multi-select "assign joint to selected rows" · **live duplicate-ID
highlighting** (a duplicate silently produces wrong bulk results otherwise) ·
unknown-joint reconciliation offering Create All / Skip / Cancel ·
"Import IDs from Forces" to bootstrap the table.

**Element Forces highlights:** a **permanent units banner** — misinterpreted force
units are the highest-consequence silent error in the whole application, and a
permanent banner is the correct amount of paranoia · a summary table whose
**min/max range columns are the data sanity check** (a units error shows instantly
as an FZ range of 1e7) · editable per-load-case scale factor that recomputes on
edit · cross-validation warnings listing IDs when ≤5 and counts when >5.

**Templates.** Both pages ship `Export Template...` writing a correctly-shaped
empty file. Cheapest possible fix for "what columns does it want?"

**Import error-report shape — generalise to every importer:**
1. Validate structure first, reporting both what's missing *and* what was found.
   Never just "invalid file".
2. Process rows independently; one bad row must not abort the import.
3. Report `Imported 47 rows (12 updated).` then `3 error(s):` with **line
   numbers**, truncated at 20 with `... and N more`.
4. Refresh the view if anything imported at all.

---

## 8. Static content — skip as in-app pages

An in-app User Guide and References pair is ~1000 lines of HTML content wrapped
in a couple hundred lines of renderer. That content is the asset; the renderer is
not.

**Recommendation:** put both under the **Help menu** as buttons that open shipped
PDFs (`open(fullfile(appRoot,'docs','user_guide.pdf'))`), and drop the two tabs —
it also shortens an already-crowded 11-tab bar. Write the PDFs once the app has
stopped moving; documenting a UI in flux is wasted work.

**One thing must survive that decision:** the equation-reference string per margin
check already appears in the Results table's `Equation` column and detail tree.
That contextual reference is 90% of what the References page provides.

---

## 9. Theming — skip dark mode, keep the discipline

A full theme manager runs ~420 lines, and most of that exists to fight the
widget toolkit's own stylesheet rather than to do anything for the analyst
(custom cell delegates purely to stop a theme overriding pass/fail colors,
column-fitting helpers to compensate for uppercased headers). All of that is
**SKIP**.

**Dark mode: skip.** MATLAB R2025a gives the shell for free via the `uifigure`
`Theme` property, but the 20% it doesn't cover is exactly the pass/fail cells —
`uistyle` colors are literal and don't adapt. So dark mode costs a full parallel
palette, which is 100% of the real work. This is a daylight-office engineering
tool; dark mode is not why anyone adopts it.

**But do this now, because it's free:** put every color in one function,
`palette(name)`, and never write a literal RGB triple anywhere else. Dark mode
later becomes a one-file change plus a rebuild-styles pass instead of a grep
across twelve files.

Seed values: `statusPass #006600` · `statusFail #CC0000` · `statusWarn #CC6600` ·
`mutedText #666666` · `tablePassBg [0.78 0.94 0.78]` · `tableFailBg [1 0.78 0.78]` ·
`tableNaBg [0.94 0.94 0.94]`. Three banner styles used consistently:
info `#dce9fc/#1a3a6e`, warning `#FFF3CD/#856404`, error `#F8D7DA/#721C24`.

**Color semantics, applied consistently:** muted gray = informational/OK · amber =
warning · red bold = failure · red border = missing required input.

---

## 10. Long-running work

`uiprogressdlg(fig, 'Cancelable','on')`, `d.Value = i/n`,
`d.Message = sprintf('%d/%d', i, n)`. Being modal, it removes the need to disable
the Run button. **`close(d)` must be in an `onCleanup` or try/finally.**

**Cancellation is free** — MATLAB hands you `d.CancelRequested`. Check it in the
loop, break, and show partial results with an honest status
(`Cancelled — 143 of 312 analyses complete`). A bulk run with no way out is a
support ticket waiting to happen.

Skip background threading (`parfeval` can't easily update a UI progress dialog,
and the modal dialog makes responsiveness moot). Revisit only past ~30 s runs.

---

## 11. Hard-won UX details — the cheap wins

Small, individually unremarkable, and each one costs a review cycle to discover
the hard way.

**Widgets**
- All numeric spinner arrows removed — typing is preferred. Use
  `uieditfield('numeric')` everywhere; `uispinner` **only** for flange count (1–4).
- Locked fields use `Enable='off'`, never read-only-but-editable-looking.
- Frustum Angle is an **integer** field.
- `F5` runs Analyze → `uifigure` `KeyPressFcn`.
- *Not needed in MATLAB:* a mouse-wheel guard. Some widget toolkits let a scroll
  over a combo box change its value, and need a whole wrapper layer to suppress
  it. MATLAB components don't respond to the wheel — noted so nobody
  "helpfully" adds scroll handling.

**Decimals**
- Nut Factor, Uncertainty Γ, Relaxation: **2** dp (were 3).
- Geometry (washer OD/ID/Thk, hole dia, thickness, edge dist): **5** dp.
- Torque 2 · Forces 1 · Bending 2 · live-label lengths 4 · preload force 0.
- Per-unit-system: LENGTH 4 English / 5 metric; TORQUE 1/2; AREA 4/6.

**Wording**
- Temperature labels shortened to `Nominal:` / `Hot:` / `Cold:`.
- Slip is a 3-state `Slip Mode:` dropdown (was a checkbox, twice renamed).
- **The threads-in-shear checkbox relabels itself live** —
  `(threads in shear)` ↔ `(body in shear)`. Best small trick on the page: it
  removes all doubt about what "unchecked" means.
- Washer types show the **spec name** (`NAS1149 - Standard OD`), not thickness.
- The insert group **title** rewrites to match the selection.
- No `(optional)` placeholders on project metadata fields.

**Layout (exact values)**
- Group spacing `RowSpacing = 4` · group padding `[6 6 6 6]` · inline row spacing
  8 px (4 px in the flange grid) · grid H/V 8/4.
- Label columns `'fit'`, widget columns `'1x'`.
- Thin vertical separators between logical clusters in dense inline rows — a
  1-px `uipanel` with a border color. Worth it; it's what keeps them readable.
- **The preload readout frame is always visible even when empty**, so the layout
  doesn't jump when a warning appears.

**Empty states**
- Bolt length combo empty → `No standard NAS lengths for this thread size`,
  never silently blank.
- Joint dropdown empty → `No saved joints — fill in fields and click Save`, with
  Load/Copy disabled.
- Nut height unknown → `—`, never blank or `0.0000`.
- Onboarding banner on the first tab.

---

## 12. Units

The unit layer has two independent axes (unit system, temperature unit) and a
5-function API: `toDisplay`, `fromDisplay`, `label`, `suffix`, `decimals`, plus
a listener registry.

**The load-bearing decision:** conversion happens **only at the serialization
boundary**. `toStruct()` converts display→internal on every numeric;
`fromStruct()` converts internal→display. Intermediate calculations explicitly
convert to internal, compute, then convert back. The engine never sees display
units.

**The unit-toggle trick:**
```
snapshot = toStruct(page)     % everything in internal units
applyUnitLabels(page)         % rewrite every field's ValueDisplayFormat
fromStruct(page, snapshot)    % re-populate in the new display units
```
Round-trip through the serializer, so no field can be forgotten. Keep an
explicit registry of `(widget, Qty)` pairs for the relabelling pass.

> **State the temperature convention once, in `UNITS.md`, and nowhere else.**
> It is the easiest thing in this app to misdescribe: a length/force axis, a
> temperature axis, and a CTE that follows neither. The convention is
> **English lengths/forces/torques, Celsius temperatures, Fahrenheit-based
> CTE** — CTE is stored internally as `in/in/°F` and multiplied by 1.8 for °C
> display, and the serialized temperature fields are
> `assembly_temp_C` / `hot_temp_C` / `cold_temp_C`.
>
> The MATLAB engine already works in °C, so it matches. Any document claiming
> "the engine stays in °F internally" is wrong — don't write it, and fix it
> where it appears.

Pitfalls that are easy to walk into — don't:
1. Initialize every field through `toDisplay()`, never with a raw constant.
2. File→New must reset through the deserializer, not by setting literals.
3. Anything not covered by the serializer must be preserved explicitly across a
   unit change (PDF metadata is the one that gets wiped).
4. Imported raw element forces are **never** reformatted by the unit toggle — they
   always display as imported, and a note says so.

---

## 13. Joint cross-section preview — later, simplified

Draws a to-scale axial cross-section: hex head → washer → flanges (split
left/right with the true clearance gap) → nut/insert/tapped host → shank at true
length, plus centerline, dashed frustum cone lines at the user's frustum angle,
per-flange labels, and (after analysis) the loading-plane line.

**Genuinely useful, not decorative** — it catches exactly what this form is prone
to: a bolt too short for the stack, a washer wider than the flange, an
implausible engagement, a loading plane outside the grip.

**ADAPT, later, geometry only.** On a `uiaxes` with `DataAspectRatio=[1 1 1]` and
limits from real dimensions, ~15 `rectangle`/`patch`/`line`/`text` calls do it —
**and drawing in MATLAB data coordinates removes the manual pixel-scaling layer
entirely** (~170 lines of it, if you draw in pixels instead). Skip the gradients,
hex chamfers, and coil hatching. Host it in a right-hand column of Joint Config
rather than a separate window.

Lowest value-per-hour item in this spec. Do §3 (reactive logic), the tooltips,
and validation first.

> Watch the scoping in the dimension-annotation code: the grip-top coordinate is
> easy to reference inside the full-mode branch without having defined it there,
> and the failure only appears when stiffness annotations are drawn.

---

## 14. Build order

Ordering principle: **first make the single-joint answer trustworthy, then make
it reusable, then make it scale.** The dependency graph, not the tab order, sets
the sequence.

| # | Step | Why here |
|---|------|----------|
| 1 | **App shell + Project & Factors** | Factors multiply into *every* margin. Until they're user-settable, Results shows numbers from hard-coded constants — worse than showing nothing, because it looks authoritative. Everything downstream also needs the shell: status bar, menus, dirty title, case save/load, `palette()`. *Defer: presets, Open Recent.* |
| 2 | **Finish the Results tab** | Highest value per line in the project, and an upgrade to something that already exists. Turns "the engine computes numbers" into "an analyst believes them." Order: 4-column table + MS formatting + cap → pass/fail styles with the fail asymmetry → summary line → auto-select governing row → preload/stiffness panels → detail tree → warning banners. *Stretch: the logic-flow narrative.* |
| 3 | **Materials & Hardware DB — read-only browser** | Joint Config's dropdowns are only as credible as data the analyst can inspect. Read-only is ⅓ the work of the editor for most of the value. **Add `Source` to `data.Library` in this step** — schema first, UI second. *Defer: inline editing, Add dialogs, admin mode.* |
| 4 | **Defined Joints** | Biggest daily workflow win after Results, *and* a hard prerequisite for the whole bulk chain. *Defer: the 60-column CSV round-trip.* |
| 5 | **Element Mapping + Element Forces together** | Mutually dependent by design — mapping's "Import IDs from Forces" needs forces; forces' cross-validation needs mapping. Building one alone means building it twice. |
| 6 | **Bulk Analysis** | Pure output over 4 and 5; nothing depends on it. Largest single page. |
| 7 | **Bolt Sizing** | Independent of everything — which is exactly why it waits. It's the only remaining tab that blocks nothing. |
| 8 | **User Guide + References** | Two Help-menu items opening shipped PDFs. Write the docs once the UI stops moving. |

### Build once, at first point of need

| Helper | First needed |
|---|---|
| `palette(name)` | Step 1 |
| `app.setStatus(msg)` | Step 1 |
| `uiconfirm` wrappers (Yes/No, Overwrite/Skip/Rename, Replace/Merge/Cancel) | Step 1 |
| Display↔internal unit conversion at the boundary | Step 1 |
| `formatMS(value, capEnabled)` | Step 2 — used by Results, Bulk, Bolt Sizing |
| `applyPassFailStyles(table, ...)` | Step 2 — `removeStyle` first, batch `addStyle` |
| Import error-report builder | Step 5 |

### Known traps — design them out, don't rediscover them

1. ~~Element mapping and forces missing from the saved case file.~~ **Done** —
   the `fastener-analysis-matlab-v1` container written by `saveToFile` carries
   `project / joint / loadCase / factors / library / mapping / forces`, and
   `readCaseFile` restores all of them. The joint library rides along in
   `library.joints`, so Defined Joints survive a save/load too.
2. A dirty flag fed by one page only — File→New then silently discards unsaved
   work when no file is open.
3. Bulk-workflow step numbering disagreeing between status hints and placeholders.
4. Project metadata going stale in the export when edited after the run — read it
   at export time.
5. A bulk run with no cancel path — MATLAB gives cancellation free.
6. The logic-flow narrative computed every analysis and shown only in the PDF.
7. An undefined grip-top coordinate in the cross-section dimension code (§13).
8. Documentation that misstates the internal temperature convention (§12).
