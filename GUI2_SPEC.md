# GUI2 Spec — the rebuilt GUI

Design spec for the second-pass GUI. It replaces `GUI_PORT_SPEC.md` as the
authority on the GUI layer; that document stays as the record of the first pass
and the source of the behavior checklist (§14).

**This is a spec for the *flow and the contract*, not a layout drawing.** What it
fixes is which information sits where, what recomputes when, how failures are
surfaced, and what the app refuses to do silently.

---

## 1. Ground rules

1. **Pure GUI.** `+engine`, `+model`, `+data`, `+report` are frozen. This work
   adds no equation, changes no allowable, and touches no validated number. If a
   change appears to require an engine edit, stop and raise it — it means the
   scope was drawn wrong.
2. **New package `+gui2`, built alongside `+gui`.** Both launchable
   (`gui.launch` / `gui2.launch`) for the whole build. `+gui` is deleted only
   when the last page of `+gui2` lands. There is never a window with no working
   tool.
3. **Target R2026a.** No version guards, no back-compat shims.
4. **Programmatic, class-based, plain `.m`.** `classdef < handle` on `uifigure`
   + `uigridlayout`. No `.mlapp` — the packaged format does not diff, does not
   merge, and cannot be reviewed line by line. No GUIDE (removed R2025a). No
   raw pixel `Position`, no `SizeChangedFcn`.
5. **One page at a time.** A page is not done until its spec section is written,
   its class is built, its `matlab.uitest` test passes, and it has been looked
   at running. No moving on at 80%.

> `CLAUDE.md` currently says "MATLAB (App Designer GUI, Phase 4)". That is stale
> and now misleading — correct it to "programmatic uifigure GUI".

---

## 2. Check scope — 9 of 15 displayed

The engine computes all 15 checks, unchanged. The GUI renders a whitelist.
Adding a check later is an edit to this list and nothing else.

**Displayed (9)** — exact `Result.Margins(i).Name` strings:

| Row | Governing |
|---|---|
| `Tension-Ultimate` | 5020B Eq. 6 / 7 / 10 |
| `Tension-Yield` | 5020B Eq. 15–18 |
| `Shear-Ultimate` | 5020B Eq. 12/13, MS Eq. 14 |
| `Interaction` | 5020B Eq. 20–23 (reports **R**, not MS — pass iff R ≤ 1) |
| `Separation` | 5020B Eq. 19 |
| `Slip` | 5020B Eq. 84/86 |
| `Bearing` | TM-106943 Eq. 72–74, required by 5020B §4.4.2 |
| `Shear-tearout` | TM-106943 Eq. 69–71, required by 5020B §4.4.2 |
| `Separation-before-rupture` | 5020B Fig. 8 (a decision, not a margin) |

**Computed but not displayed (6):** `Bearing-under-head`,
`Bolt-thread shear`, `Nut strength`, `Insert internal-thread`,
`Insert external-thread`, `Tapped-hole parent-thread`.

### Two rules that make the scope honest

- **`Allowable from:` line on Tension-Ultimate.** The hidden nut / insert /
  tapped-parent rows produce the §4.4.1 fastening-system allowable that
  *governs* Tension-Ultimate. Hiding the rows must not hide their effect: the
  Tension-Ultimate detail names the governing member and its value, e.g.
  `Allowable from: insert (derived), 4,210 lbf`.
- **Scope footer, everywhere margins are shown or exported.**
  *"9 of 15 checks shown; 6 computed and not displayed"*, listing the six by
  name. A margin table that reads as complete when it is not is a compliance
  problem, not a cosmetic one.

### The displayed 9 is the tool's scope

Every verdict is **scope-qualified, never unqualified**.
*"All 9 displayed checks pass — 6 computed, not shown"* is honest.
*"ALL CHECKS PASS"* is not, and is forbidden outright
(`GUI2_HARVEST.md` A1).

Three consequences:

- **No worst-margin / governing-check headline.** `engine.analyze` computes
  `WorstMargin` and `GoverningCheck` across all 15 rows (`analyze.m:269–277`),
  so either could name a check with no row in the table. Neither is displayed.
  The nine colored rows make the problems obvious on their own.
  **Never recompute a minimum over the displayed subset** — that is the view
  re-deriving a number, and it can overstate the margin.
- **Exports carry the same 9**, plus the scope statement naming the omitted six
  prominently enough that a reviewer cannot mistake the file for a complete
  5020B assessment. The omitted set includes the §4.4.1 checks that *govern*
  tension.
- **Warnings are never scope-filtered** — and nothing needs filtering.
  `Result.Warnings` rows are not tied to margin checks at all (`analyze.m:184`:
  *"they never [have] a Margins row of their own"*); the only sources are
  `PreloadNearYield` and `BoltLengthShort`, both joint-level. All warnings and
  the Fig. 8 narrative always render in full.

---

## 3. Information architecture — left rail, 10 pages

Top tabs waste vertical space, which is the scarce dimension on 16:9. A rail
costs ~190 px horizontally, where there is surplus, and gives the tall Joint
Config form the height it needs.

```
SETUP              REFERENCE
  Project            Materials & Hardware Library
  Factors
  Temp Loads       (Help -> menu bar, not a page)
SINGLE JOINT
  Joint Config
  Single Joint Results
BULK
  1  Defined Joints Library
  2  Element Mapping
  3  Element Forces
  4  Bulk Analysis
```

Order is deliberate: global setup → single-joint loop → bulk loop in execution
order → reference. The bulk steps are numbered **in the rail itself**, which is
the one place the 1–4 scheme lives; no other page or status hint may restate it
with different numbers.

**Not built:** Bolt Sizing. `engine.boltSizingSweep` stays in the engine,
untouched and re-addable.

**User Guide / References are not pages.** `Help → User Guide | Equation
Reference` on the menu bar, opening the bundled PDFs. Resolve paths via
`fileparts(mfilename('fullpath'))`, or `ctfroot` when `isdeployed` — never
`pwd`, which is what breaks in the `.exe`.

### The rail is a button rail, not a `uitabgroup`

`uitabgroup(TabLocation='left')` is a flat list: no section headers, no
per-item state. Build the rail as a left `uigridlayout` column of `uilabel`
section headers plus `uibutton(..., 'state')` page items, with a card area on
the right where one page is visible at a time. `ColumnWidth = {190, '1x'}`.

**Selection:** state buttons in a radio group — the click handler sets
`Value = true` on the clicked item, `false` on the rest. MATLAB renders the
pressed state natively, so it adapts to light/dark theme; hand-picked
background colors do not. Add `FontWeight = 'bold'` on the active item, since
the native pressed state alone is subtle.

**Each rail item carries two independent states, on two different channels:**

| State | Means | Channel |
|---|---|---|
| Active | where you are now | pressed + bold |
| Status | stale / loaded / empty | trailing glyph — `●` amber for stale, `✓` for loaded |

If both use color they fight, and a stale-but-active item reads as neither.

**No page is ever disabled.** Prerequisites are communicated by rail glyphs,
empty-state placeholders that replace the content, and run-time pre-validation
— which is the only hard gate, and always offers to navigate to the fix.

---

## 4. App shell

| Element | Mechanism |
|---|---|
| Rail + card area | root `uigridlayout`, `ColumnWidth = {190, '1x'}` |
| Page visibility | lazily built on first visit, then `Visible` toggled |
| Status bar | `uilabel` in the root grid's bottom row; one `app.setStatus(msg)` |
| Menu bar | `uimenu` on the `uifigure` |
| Sub-tabs | nested `uitabgroup` **inside** a page only (Bulk tiers, DB entities) |
| Scrolling | `Scrollable = 'on'` per page grid |

**Window title** carries three pieces of state: version when nothing is open,
the file path when a case is open, prefixed `* ` when dirty. One
`updateTitle()` reads `CurrentFile` + `IsDirty`.

**Menu bar:**

```
File   New | Open... | Open Recent > | Save | Save As...
       Import Joints from File...          (step 5 — needs Defined Joints)
Help   About                               (built)
       User Guide | Equation Reference     (step 10 — needs the bundled PDFs)
```

**`F5` runs Analyze** — from the `uifigure` `KeyPressFcn`. Noted because
`GUI_PORT_SPEC.md` §11 claimed this existed in the first build and it never
did; there is no `KeyPressFcn` anywhere in `+gui`. It lands with Joint Config
in step 3.

**Navigation is one method.** `app.navigateTo(pageId)` builds the page if
needed, swaps visibility, refreshes it from state, and updates the rail. The
pre-validation dialogs call it by name (`navigateTo("ElementMapping")`) rather
than poking a tab-group property.

---

## 5. State — one handle model, coarse events

A single `gui2.AppState < handle` owns everything: `Project`, `Joint`,
`LoadCase`, `Factors`, `Settings` (temperatures), `JointLibrary`, `Elements`,
`Mapping`, `Result`, `BulkTable`, `Library`, `CurrentFile`, `IsDirty`, and the
`ResultStale` / `BulkStale` flags.

Pages hold a reference to it, read and write it directly, and listen for
**coarse** events — not per-field:

```
ProjectChanged   JointChanged      LoadCaseChanged   FactorsChanged
SettingsChanged  LibraryChanged    JointLibraryChanged
ElementsChanged  ResultChanged     BulkChanged       DirtyChanged
```

Four notes, all settled during the step-1 build:

- **`Project` is case state**, round-trips through the case file, and owns the
  step-2 Project page — hence `ProjectChanged`, the eleventh event.
- **`Mapping` has no event of its own**; it fires `ElementsChanged`. Element
  Mapping and Element Forces cross-validate each other, so both must refresh
  when either moves. Split it later if the extra refresh ever costs anything.
- **`DirtyChanged` covers `CurrentFile` too** — it means *"dirty flag or open
  file changed, rebuild the title"* (§4 wants the title tracking both).
- **`ResultStale` / `BulkStale` live on AppState**, not on their pages, because
  harvest A3 requires `markDirty` to set them centrally rather than each page
  remembering to.

Pages never talk to each other. All cross-page effect goes through AppState.

> This reverses `GUI_PORT_SPEC.md` §2, which said to skip `events`/`notify` and
> hand-wire `notifyXChanged()` calls. The 11,945-line single class that advice
> produced is the evidence it does not scale past a few pages.

**Deviation from the MathWorks MVC reference, deliberately:** views are plain
`classdef < handle` page classes, not `matlab.ui.componentcontainer.
ComponentContainer`. ComponentContainer exists to make *reusable* components
that drop into App Designer; every page here is a singleton built in code, so
it would be ceremony with no payoff. The Model half of the pattern — one handle
class, events, no view-to-view coupling — is adopted in full.

**Page contract** — abstract base `gui2.Page`:

```matlab
pageId(obj)              % string, stable id used by navigateTo
title(obj)               % string, rail label
build(obj, parent)       % construct into the given grid cell, once
refresh(obj)             % re-read AppState; must be idempotent and cheap
railStatus(obj)          % "" | "stale" | "loaded" — drives the rail glyph
```

---

## 6. Engine contract — the only calls the GUI may make

The GUI builds typed model objects, calls the engine, and renders what comes
back. It re-derives nothing.

```matlab
r  = engine.analyze(joint, loadCase, factors)      % -> engine.Result
T  = engine.analyzeBulk(jointLibrary, elements, factors)  % -> table, 1 row/element
S  = engine.summary(joint, loadCase, factors)      % -> display table
chk = engine.boltLengthCheck(...)                  % live length adequacy
c  = data.loadCase(file)  /  data.saveCase(caseStruct, file)
lib = data.Library.load(path)   and its accessors
```

Note the engine takes **typed objects** (`model.Joint`, `model.LoadCase`,
`model.Factors`), not a config struct. Their property blocks are the
authoritative validation. Do not flatten them to structs.

**Threshold and pass/fail logic lives in the engine.** `Result.Margins(i).Status`
is already `"Pass" | "Fail" | "NotEvaluated"`; the view colors by that field and
never re-thresholds MS itself. `Interaction` reports `R` (pass iff `R ≤ 1`),
the opposite direction from MS — a consumer that thresholds it like MS is
wrong.

---

## 7. Joint Config — field order

Every field from the current build is retained. This is a reordering, plus the
six changes in §7.2. `buildJoint`/`applyJoint` marshal by property, not by row,
so nothing outside the view changes.

### 7.1 Order

**Left — the joint, in physical stack order**

| # | Group | Fields |
|---|---|---|
| 1 | Identity | Joint name |
| 2 | Bolt | Bolt, Bolt material, *[spec label]*, Bolt count nf |
| 3 | Washer under bolt head | Present, spec, size, material, OD, ID, thickness |
| 4 | Flange stack | 4 × (Active, Layer, Name, Material, t, Hole, Edge, Tear-out) |
| 5 | Washer under nut | Present, Same as Head, spec, size, material, OD, ID, thickness |
| 6 | Threaded member | Type, *member material (dynamic label)*, Nut spec, Engagement Le |
| 7 | Bolt length & grip | Overall bolt length, then grip label + 4-line adequacy readout |
| 8 | Advanced / overrides | Unthreaded body length L1, Bolt rated ultimate, Bolt rated yield, Frustum half-angle |

**Right — loads, assumptions, run**

| # | Group | Fields |
|---|---|---|
| 9 | Preload (torque-controlled) | Nominal torque, Tolerance, Nut factor K, Uncertainty Γ, Relaxation, Separation-critical |
| 10 | Applied loads | Case name, Bolt tensile PtL, Bolt shear PsL, *(joint totals — conditional, see §7.2)* |
| 11 | Analysis assumptions | Shear plane, Slip mode, Friction coefficient, Bolt axis, Loading-plane factor n |
| 12 | Actions | **Analyze Single Joint**, Save to Defined Joints |

The old "Hardware" and "Joint behavior" groups dissolve: hardware splits along
the stack, behavior becomes "Analysis assumptions".

### 7.2 The six changes

**a. Member material gets a dynamic label.** One dropdown plays three roles.
Label it for the role: `Nut` → *Nut material*; `Helical Insert` and
`Tapped Hole` → *Parent (host) material*; `None` → hidden.

**b. Threaded-member rated load — field removed.** For a nut it already comes
from the library (the Nut spec picker resolves `data.Library.nutFor` and
auto-fills). For an insert the library has nothing to give —
`data.Library.insert` is tapped-hole geometry only, with no material and no
rated load. For a tapped hole it is documented as "may stay 0".

> Accepted cost: for a nut family absent from the library, the §4.4.1
> rated-load ceiling cannot be applied and the computed `0.75·π·E·Le`
> thread-shear area governs unchecked. The escape is `data.Library.addNut`,
> which carries provenance — not a typed number, which does not.

**c. Nut/insert bearing face OD — field removed.** Nut: `data.Library.nut`
returns `BearingDiameter` and the picker already fills it. Insert / tapped
hole: no such field in the catalogue, and physically no bearing annulus. Its
only consumer, `marginBearingUnderHead`, is outside the displayed scope.

**d. Unthreaded body length L1 — field KEPT, moved to Advanced / overrides.**

> Originally specified for removal ("make it automatic"). **It cannot be made
> automatic today.** `engine.stiffness` resolves L1 by three-level precedence
> (`stiffness.m:144–190`): an explicit `Joint.BodyLengthInGrip` wins; otherwise
> `Ls = Bolt.Length − Bolt.ThreadLength`; otherwise the bolt length is estimated
> and the same subtraction applied. **Levels 2 and 3 both require
> `Bolt.ThreadLength`, and no library bolt has one** — all 32 seeded entries
> omit it on purpose, per their own source note: *"thread length is a per-part
> (length-dependent) property."* NAS1351/NAS1352 thread length varies with the
> ordered length, so it cannot live in a catalogue keyed by thread size.
>
> With no thread length, removing the field leaves `L1 = NaN` and
> `engine.stiffness` throws (`stiffness.m:187`) — taking down separation, the
> tension-rupture branch, φ, and everything downstream. `stiffness.m:146` also
> records that DABJ Example 8-b supplies `L1 = 0.70` directly, so the validated
> example depends on this path.
>
> Making it automatic requires per-part-number library entries carrying thread
> length — a `+data` change, out of scope for a pure-GUI pass. Logged in §15.

The field keeps its current tooltip, plus: *required for bolt stiffness —
catalogue bolts carry no thread length, so it cannot be derived.*

**e. Bolt rated loads become locked display with an explicit override.**
They already auto-fill from `data.Library.boltSpecFor(bolt, material)` on every
bolt or material change — the problem is that they render as primary inputs.
Lock by default, unlock deliberately, same mechanism as the Nut spec picker.
The override still matters: a bolt+material pair with no `boltSpec` entry falls
back to `At · Ftu`, a derived convention rather than a 5020B equation.

**f. Shear-transfer condition — control removed, `NotDeclared` hard-set.**

> `NotDeclared` computes `fbu = 0` and records the §4.4.4 exemption as
> **ASSUMED**. `CloseToleranceOrInterference` computes the identical number but
> records it as **VERIFIED** — hard-setting that would have every joint claim a
> verification nobody performed. Same math, honest record.

The placeholder that replaces the control, which doubles as the future-feature
marker:

> *Close-fit assumed — bolt bending (fbu = 0) not yet implemented;
> NASA-STD-5020B §4.4.4 exemption assumed, not verified.*

The same note appears under the Interaction row on Single Joint Results.

### 7.3 Conditional fields

- **Joint tensile / joint shear totals appear only when Slip mode = Joint.**
  5020B Eq. 84 needs them; the single-fastener default (Eq. 86) does not, and
  showing them unconditionally is what makes them confusing.
- **Their current tooltip is wrong and must be rewritten.** It claims
  *"Blank = automatic (engine derives BoltCount × per-bolt)"*. The engine says
  the opposite, verbatim (`marginSlip.m:79`): *"They are NOT simply BoltCount ×
  per-bolt loads because of bolt-pattern load distribution — set them
  explicitly."* Blank means the Slip row silently reports NotEvaluated.

### 7.4 Shear plane needs an explainer

> Does the shear plane cut the **threads** or the full-diameter **body**? Body
> if the unthreaded shank extends past the faying surface; threads otherwise.
> Sets the shear area (5020B Eq. 12 shank area vs Eq. 13 minor-diameter area)
> **and** the interaction exponents (Eq. 20/21 body 2.5/1.5; Eq. 22/23 threads
> 1.2/2.0). **Threads** is the conservative choice.

### 7.5 Groups are collapsible

Collapsed groups stay unbuilt until first expanded. Eight groups on the left,
four on the right, so the page opens light.

### 7.6 Keep in sync

The Defined Joints summary (`djSummaryRows` in the current build) mirrors these
panels field for field. Any change here carries through to it in the same
commit, or the summary and the form disagree.

---

## 8. Single Joint Results

- Margin table, 9 rows, solver order, no sorting. Color from
  `Margins(i).Status` via `gui2.palette` — never re-thresholded in the view.
- **`removeStyle` before every `addStyle` pass.** Style accumulation costs
  render time and produces wrong colors, and remote sessions multiply the cost.
- **No worst-margin or governing-check headline** (§2). The verdict line is
  scope-qualified — *"All 9 displayed checks pass — 6 computed, not shown"* —
  and is never unqualified. The rail navigates here automatically after
  Analyze; the first failing row is selected, or row 1 if none fail.
- Detail panel for the selected row: `Method` (the equation citation), `Detail`,
  and — on Tension-Ultimate — the `Allowable from:` line from §2.
- Fig. 8 separation-before-rupture narrative, verbatim from `Result.Narrative`.
- Scope footer per §2.
- Stale banner when any input changed since the shown result was computed; the
  rail item carries the amber `●` at the same time.

---

## 9. Bulk Analysis

Three tiers, unchanged: **Joint Summary** (one row per joint), **By Load Case**,
**By Element**.

Realistic scale is ~3 load cases × a few hundred elements ≈ 900 rows; the
extreme corner is 50 × ~500 ≈ 25,000. Tiers 1 and 2 need nothing.

**Tier 3 — By Element:**

- Defaults to a **filtered** view: failing / governing rows only, plus a
  load-case selector. No analyst scrolls 25,000 rows hunting a negative margin,
  so this is better UX independent of performance.
- *"Show all (N rows)"* toggle, confirming above ~5,000 rather than silently
  painting.
- No pagination machinery.

**Roll-up column.** `engine.analyzeBulk` emits `WorstMargin` and
`GoverningCheck` columns (`analyzeBulk.m:341`); both span all 15 checks, so
**neither is displayed** (§2). In their place, a **scoped pass count** —
`7/9 pass` — which counts `Status` fields the engine already set rather than
re-deriving a margin. Without some roll-up, "which joints are in trouble" means
scanning hundreds of rows across nine colored columns.

**The row filter must never reach the export.** Tier 3's failures-only default
is a *view*. Export writes every row of the 9-column scope — an analyst who
filters to failures and exports still gets all of them. Row scope and display
scope are separate concerns; conflating them loses data silently.

**Export column scope is the displayed 9** (§2), with the scope statement in
the workbook and the PDF.

---

## 10. Performance — remote-session rules

A meaningful share of users run over Remote Desktop, where `uifigure` falls back
to software rendering. **Render cost, not compute, is the binding constraint** —
which is why analysis stays on the main thread. Moving it to `backgroundPool`
would not make a single paint faster, and single-joint analysis is milliseconds.

1. Build pages **lazily**, on first visit. Not up front.
2. Assign table `Data` **in one batch**. Never per-cell in a loop.
3. `removeStyle` before `addStyle`, always.
4. Collapsed groups stay unbuilt.
5. Audit `ValueChangingFcn` (per-keystroke) uses — prefer `ValueChangedFcn`
   (on commit). Per-keystroke callbacks are the classic remote-session killer.
6. `uiprogressdlg` for anything that might exceed a beat; poll `CancelRequested`.

**Baseline before tuning:** time the current app over Remote Desktop with a
representative bulk case. Real numbers beat speculation about where it hurts.

---

## 11. Validation — three layers

1. **Required-field marking**, live: pale red background
   (`palette('requiredBlankBg')`) on a required field left blank; Analyze
   disabled with a tooltip naming what is missing.
2. **Typed model validation** — `model.*` property blocks and `arguments`
   blocks. Authoritative, and protects headless callers too.
3. **Run-time pre-validation** — the only hard gate. On failure, a dialog
   listing the problems plus buttons that navigate to the page where each fix
   lives.

Every engine call is wrapped in its own `try/catch` **inside its callback** —
an outer `try/catch` around figure construction does not catch anything thrown
later from a callback. Report with `uialert`.

---

## 12. Color

All color goes through `gui2.palette`. No literal RGB triple appears anywhere
else in `+gui2`. Carry the semantics forward from `gui.palette`: muted gray =
informational, amber = warning, bold red = failure, red field background =
missing required input. Add `navActiveFg` / `navIdleFg` for the rail.

Current values assume a light background (`fieldBg` pure white, `defaultText`
pure black). R2026a apps are theme-aware, so if dark mode is taken up, `palette`
becomes theme-aware and remains the single file that changes.

---

## 13. Testing

- The engine is already covered by `matlab.unittest` and stays that way.
- **Every page ships with a `matlab.uitest.TestCase` test** exercising its
  wiring: widget → AppState → engine → rendered output. This is the mechanism
  that makes "critical about each page" real rather than aspirational; the
  current build has one smoke test for nine tabs.
- Use `matlab.mock` to stub the engine where a page test should not depend on
  real numbers.

---

## 14. Build order

Each step lands complete — spec section, class, test, run — before the next.

| Step | Deliverable |
|---|---|
| 0 | **Behavior harvest.** Read each current tab and write its earned edge cases into a checklist. The 11,945-line class is ~20% layout and ~80% behavior; the layout is cheap to rebuild and the behavior is expensive to rediscover. Do this before deleting anything. |
| 1 | Shell — `AppState`, `Page` base, rail, card area, navigation, status bar, menu bar, title/dirty. One placeholder page. |
| 2 | Project · Factors · Temp Loads |
| 3 | Joint Config — the big one |
| 4 | Single Joint Results |
| 5 | Defined Joints Library |
| 6 | Element Mapping |
| 7 | Element Forces |
| 8 | Bulk Analysis |
| 9 | Materials & Hardware Library |
| 10 | Help menu + bundled PDFs; delete `+gui` |

---

## 15. Open items

- **Two pages named "Library".** *Defined Joints Library* is case-scoped —
  saved inside the case file, travels with the analysis. *Materials & Hardware
  Library* is app-scoped — baseline plus custom, persisted to `library.json`,
  shared across every case. Same word, different lifetime.
  `GUI_PORT_SPEC.md` §1 avoided this deliberately. Current decision: keep both
  names, and state the scope in-page on each. One-line change if it reads badly
  in practice.
- **Three thin setup pages.** Project is ~4 fields and Temp Loads ~3. Defensible
  — they are easier to build and review separately, which is the point of this
  pass. If they feel sparse once built, merge into one *Project Setup* page with
  a nested `uitabgroup`. Temp Loads needs an *applies to every joint* banner
  regardless, since it is global and sits among per-joint-looking pages.
- **Automatic L1 needs a library change.** Closed for this pass (§7.2(d)): no
  seeded bolt carries `threadLength`, so L1 can only be entered. Deriving it
  would mean per-part-number bolt entries (thread length is length-dependent,
  not a property of the thread size), which is a `+data` change and a separate
  decision — it would multiply the 32 catalogue entries by every ordered length.
- **Dark mode** — near-free in R2026a, but below performance in priority.
  Deferred, not ruled out.
