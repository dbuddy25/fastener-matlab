# GUI2 Spec — the rebuilt GUI

> **`GUI_PORT_SPEC.md` was deleted 2026-08-17.** Its live content — the
> Materials & Hardware page design and the cross-section preview — is now §16
> and §17 below. Everything else in it was superseded layout advice for the
> first-pass tab shell. References to it in this file and in code comments are
> historical citations; the file itself is recoverable from git history
> (`git show <rev>:GUI_PORT_SPEC.md`).

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

## 2. Check scope — all 15 displayed

The engine computes all 15 checks, and the GUI now shows all 15: **14 margin
rows plus the Fig. 8 gate**, which leads Analysis decisions because it selects a
branch rather than carrying a margin.

It did not always. The first build displayed 9 and named the other 6 as
"computed and not displayed", and that whitelist was wrong in two separate ways,
both found in use:

- **`Bearing-under-head` was REQUIRED and invisible.** §4.4.2 calls for margins
  on the joint members and prints no member-strength equations, so TM-106943
  Eq. 74/75 supply them — the check ran on every analysis and appeared nowhere.
  `Bolt-thread shear` joined it as a row at the same time.
- **The four §4.4.1 threaded-member modes were hidden on a false premise** — that
  a row for them would report one fact twice, since whichever applies sets
  `Ptu_allow` and governs Tension-Ultimate. They are not one fact. Those modes
  carry their own margins against a **different** design load
  (`engine.boltDesignLoad`'s preload-included Eq. 8 form,
  `Pb = PpMax + FFU·FSU·n·φ·PtL`) while Tension-Ultimate divides by
  `Ptu = FSU·FFU·PtL`. A nut-strength MS is not recoverable from the
  Tension-Ultimate row.

Only one threaded-member mode applies to any given joint, so the other three
render NotEvaluated in amber — the same honest treatment Slip gets when µ = 0.

**Displayed (all 15)** — exact `Result.Margins(i).Name` strings:

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
| `Bearing-under-head` | TM-106943 Eq. 74/75, required by 5020B §4.4.2 |
| `Bolt-thread shear` | TM-106943 Eq. 63 (the bolt's own external threads) |
| `Nut strength` | 5020B §4.4.1, thread shear per TM-106943 |
| `Insert internal-thread` | 5020B §4.4.1, thread shear per TM-106943 |
| `Insert external-thread` | 5020B §4.4.1, thread shear per TM-106943 |
| `Tapped-hole parent-thread` | 5020B §4.4.1, thread shear per TM-106943 |

**Nothing is computed and hidden.** The last four are the §4.4.1
threaded-member modes: only one applies to a given joint, so the other three
come back NotEvaluated and render amber — which is the honest outcome, not a
gap.

### Two rules that make the scope honest

- **`Allowable from:` line on Tension-Ultimate.** The hidden nut / insert /
  tapped-parent rows produce the §4.4.1 fastening-system allowable that
  *governs* Tension-Ultimate. Hiding the rows must not hide their effect: the
  Tension-Ultimate detail names the governing member and its value, e.g.
  `Allowable from: insert (derived), 4,210 lbf`.
- **Scope footer, everywhere margins are shown or exported.** It no longer
  names absent checks — there are none. It still refuses to claim a complete
  assessment, because **a complete check list is not a complete assessment**:
  TFSR 11 requires yield and separation to account for combined loading and the
  tool implements neither (`COMPLIANCE.md`, TFSR 11 **PARTIAL**). A margin table
  that reads as a finished 5020B case when it is not is a compliance problem,
  not a cosmetic one — only the reason has changed.

### The displayed 9 is the tool's scope

Every verdict is **scope-qualified, never unqualified**.
*"All 9 displayed checks pass — 6 computed, not shown"* is honest.
*"ALL CHECKS PASS"* is not, and is forbidden outright
(`GUI2_HARVEST.md` A1).

Three consequences:

- **No worst-margin / governing-check headline.** `engine.analyze` computes
  `WorstMargin` and `GoverningCheck` across all 15 rows (`analyze.m:269–277`).
  Neither is displayed. The coloured rows make the problems obvious on their
  own, and a single headline number invites reading one figure instead of the
  table. *(The original reason — that either could name a check with no row —
  expired when all 15 became rows. The rule stands on the weaker ground above;
  revisit it deliberately if ever, not by drift.)*
  **Never recompute a minimum over the displayed subset** — that is the view
  re-deriving a number, and it can overstate the margin.
- **Exports carry all 15**, plus the scope statement. Nothing is omitted from a
  file any more, so what the statement must say is what the TOOL does not do:
  yield and separation under combined loading (TFSR 11) are required by 5020B
  and not implemented, so no export is a complete 5020B assessment.
- **Warnings are never scope-filtered** — and nothing needs filtering.
  `Result.Warnings` rows are not tied to margin checks at all (`analyze.m:184`:
  *"they never [have] a Margins row of their own"*); the only sources are
  `PreloadNearYield` and `BoltLengthShort`, both joint-level. All warnings and
  the Fig. 8 narrative always render in full.

---

## 3. Information architecture — left rail, 10 pages

Top tabs waste vertical space, which is the scarce dimension on 16:9. A rail
costs ~160 px horizontally, where there is surplus, and gives the tall Joint
Config form the height it needs.

```
SETUP              REFERENCE
  Project            Materials & Hardware
  Factors
  Temp Loads       (Help -> menu bar, not a page)
SINGLE JOINT
  Joint Config
  Single Joint Results
BULK
  1  Defined Joints
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

**User Guide / References are not pages.** They live on the menu bar. Path
resolution is `fileparts(mfilename('fullpath'))`, or `ctfroot` when
`isdeployed` — never `pwd`, which is what breaks in the `.exe`. Built as
`gui2.docPath`, the first deployment-aware resolver in the codebase.

**CHANGED — nothing is bundled, because nothing can be.** This section said
Help opens *"the bundled PDFs"*. Nine of the fifteen documents the tool cites
are not ours to redistribute: every NAS/NASM sheet carries *"COPYRIGHT …
Aerospace Industries Association … ALL RIGHTS RESERVED"*, the DABJ course book
carries a copyright notice and restrictions, and the Heli-Coil bulletin is
vendor material. `references/` is gitignored twice over precisely so none of
them can be published by accident, and those nine are exactly the sheets the
hardware catalogue is transcribed from.

So the tool ships the **citations** — which are facts, and are the part that
carries traceability — and opens a local copy only where the analyst already
has one. `data.referenceDocuments` is the list (title, publisher, year, role in
the document hierarchy, what this tool takes from it, and a redistributable
flag); `gui2.ReferencesView` renders it; `gui2.referencesFolder` remembers
where this machine keeps its copies. A row with no local file says *"not on
this machine"* rather than going blank — "you do not have this" and "the tool
does not cite one" are different facts.

`Help → User Guide` opens `USER_GUIDE.md` externally: one source of truth, and
MATLAB has no markdown renderer, so an in-app window would show raw markup.

### The rail is a button rail, not a `uitabgroup`

`uitabgroup(TabLocation='left')` is a flat list: no section headers, no
per-item state. Build the rail as a left `uigridlayout` column of `uilabel`
section headers plus `uibutton(..., 'state')` page items, with a card area on
the right where one page is visible at a time. `ColumnWidth = {160, '1x'}` —
which fits the longest label bolded, once the labels are kept short.

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
| Rail + card area | root `uigridlayout`, `ColumnWidth = {160, '1x'}` |
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
       User Guide | References...          (built)
```

> **No keyboard shortcut for Analyze.** `GUI_PORT_SPEC.md` §11 claimed the
> first build ran Analyze on `F5`; it never did — there is no `KeyPressFcn`
> anywhere in `+gui`. An earlier draft of this section specified one anyway,
> on the strength of that claim. It was built, it required a figure-level
> handler that made a page reach outside itself, and it shipped broken.
> Removed: the button is the whole interface, and this is an MVP.

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
[el, info] = data.loadElementWorkbook(file)   % force import (step 7)
r  = engine.applyTemperatures(joint, settings) % global temps onto one joint
```

`data.loadElementWorkbook` is on this list for the same reason the rest are:
the GUI must not grow a parser of its own. It reads a multi-sheet workbook,
one load case per sheet, and returns rows plus a per-sheet `info` the page
turns into an import report. What the GUI adds around it — Merge vs Replace,
the per-load-case Scale and Reversible, the range preview, cross-validation
against the mapping — is all state and presentation, never parsing.

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
| 4 | Flange stack | 4 × (Layer, Name, Material, t, Hole, Edge, Tear-out) |
| 5 | Washer under nut | Present, Same as Head, spec, size, material, OD, ID, thickness |
| 6 | Threaded member | Type, *member material (dynamic label)*, Nut spec, Engagement Le |
| 7 | Bolt length & grip | Overall bolt length, then grip label + 4-line adequacy readout |
| 8 | Advanced / overrides | Unthreaded body length L1, Bolt rated ultimate, Bolt rated yield, Frustum half-angle |

**Right — loads, assumptions, run** (40%)

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
`Tapped Hole` → *Parent (host) material*.

> **There is no `None`.** `model.ThreadedMemberType` has exactly three
> members — a joint always threads into something, so "no threaded member" is
> not a state Joint Config can be in. An earlier draft of this section listed a
> fourth `None → hidden` row; it was wrong, and it was implemented faithfully
> as `case model.ThreadedMemberType.None`, which threw on every switch to
> Insert or Tapped Hole. The old build's *Bolt Sizing* tab did offer
> "None (bolt-only)", but that was a standalone sizing context rather than a
> joint — do not carry it back here.

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

**d. Unthreaded body length L1 — kept in Advanced / overrides, now a true
override.**

> Originally specified for removal, then documented as impossible because no
> library bolt carried a thread length. **Both were wrong.** NAS1351/NAS1352
> Table II gives `Lt`, the MINIMUM BASIC THREAD LENGTH, **per size** — it
> follows the ASME B18.3 body size rather than the thread pitch, which is why
> the two standards list identical values for every shared dash number. It sits
> in a catalogue keyed by thread size perfectly well; nobody had transcribed it.
>
> With `Bolt.ThreadLength` seeded, `engine.stiffness` levels 2 and 3 can fire:
> `Ls = Bolt.Length − Bolt.ThreadLength`, clipped into the clamp. The field
> stays, but as a genuine override rather than the only working path.
>
> Note (c) bounds it: screws shorter than `Lt` are threaded as close to the
> head as practicable, so `Lt` is the threaded length only for screws longer
> than it.

**e. Bolt rated loads auto-fill from the library and stay editable.**
They fill from `data.Library.boltSpecFor(bolt, material)` on every bolt or
material change. A pairing with **no** `boltSpec` entry **blanks** them rather
than carrying the previous pairing's numbers over — analysing a new bolt with
the old bolt's ratings is the failure that matters here.

> An earlier draft called for "locked display with an explicit override",
> mirroring the nut-spec picker. Dropped once built: these fields live in a
> group titled **Advanced / overrides**, so leaving them editable *is* the
> override path. Locking them would need a second unlock control to say what
> the group's title already says. The override still matters — a pairing with
> no spec entry falls back to `At · Ftu`, a derived convention rather than a
> 5020B equation, and an analyst with a real spec value needs somewhere to put
> it.

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

> **No `Active` column.** A layer is in the stack when it has a thickness —
> that is the whole rule. The first attempt carried an `Active` checkbox as a
> second, independent way to say the same thing, and the two states had to be
> kept in step: the deserializer unticked every row for an empty stack, which
> silently undid the pre-ticked first row and made typing a thickness do
> nothing at all. One source of truth removes both the bug and a column. To
> park a layer, clear its thickness.

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

### 7.4a Shear-transfer condition (§4.4.4) — now a real control

The first build deliberately omitted this dropdown and left
`Joint.ShearTransferCondition` at `NotDeclared`, reasoning that a selectable
"verified" member would have joints claiming a verification nobody performed.
The static note that stood in its place was wired to nothing, and the omission
had a worse consequence than the one it avoided: `NotDeclared` was the only
value gui2 could produce, so `ClearanceOrGapped` — the case the enum exists to
expose — was **unreachable from this GUI**.

The dropdown reads **Bolt bending (4.4.4)** — *Not determined* (default) /
*Exempt — close or interference fit* / *Required — clearance or gap*, using
§4.4.4's own framing rather than naming the shear-transfer mechanism. The
default is still `NotDeclared`, so nothing claims a verification by accident; picking a value is a positive act by the
analyst, which is what the original objection actually wanted. Applied loads
gained a **Bolt bending limit MbL** field (in-lbf) alongside it — declaring
`ClearanceOrGapped` without one leaves the interaction check NotEvaluated, and
the Results bending line says so.

### 7.5 Groups are collapsible

Eight groups on the left, four on the right. Collapsing shrinks what an analyst
has to scan.

> **Bodies are built eagerly; collapse toggles visibility only.** The spec
> originally asked for collapsed groups to stay unbuilt, for render cost. That
> is incompatible with the marshalled design: `buildJoint` reads *every* control
> to assemble a `model.Joint`, so an unbuilt control is a marshalling failure
> rather than a saving. Correctness wins. The lazy-build saving that matters —
> the whole page, on first navigation — is unaffected.
>
> Getting the render saving too would mean making the page model-bound instead
> of marshalled, which is a different design and not worth reopening for it.

### 7.6 Keep in sync

The Defined Joints summary (`djSummaryRows` in the current build) mirrors these
panels field for field. Any change here carries through to it in the same
commit, or the summary and the form disagree.

---

## 8. Single Joint Results

### 8.1 The margin table — 14 rows

All fifteen displayed checks minus `Separation-before-rupture`, which is not a
margin (§8.2). Solver order, no sorting, **`Interaction` last**.

`Bearing-under-head` and `Bolt-thread shear` were hidden in the first build and
are rows now. NASA-STD-5020B §4.4.2 REQUIRES margins on the joint members and
prints no member-strength equations (TM-106943 Eq. 74/75 supply them), so
bearing-under-head was a required check computed on every run and displayed
nowhere. `Bolt-thread shear` is a real mode 5020B defers on (TM-106943 Eq. 63)
and, unlike the four checks that remain unlisted, is **not** folded into
`Ptu_allow` — those are the internal threads.

- Colour from `Margins(i).Status` — `"Pass" | "Fail" | "NotEvaluated"`. The
  view never re-thresholds (A2).
- **`removeStyle` before every `addStyle` pass**, applied with an N×2 index
  matrix, never per cell (A8).
- **Margins render to two decimals** with an explicit sign: `+0.32`, `-0.14`.
- **"Cap MS > 5" checkbox, default ON, display-only**, with a tooltip saying
  so. Above the cap renders `>+5`; `inf` renders `+inf`. Without it a table of
  `+47.3`, `+112.8`, `-0.14` buries the only number that matters. Toggling the
  cap is a display action: it must never mark the case dirty or stale a result.
- **`Interaction` is last, and labelled for its own direction.** It reports a
  RATIO, passing iff `R <= 1` — the opposite of every other row. Render it as
  `R = 0.86 (<= 1)` so the criterion travels with the number and cannot be read
  as a margin. It is deliberately excluded from any worst-margin comparison.
- No worst-margin or governing-check headline (§2). The verdict line is
  scope-qualified.

### 8.2 Analysis decisions — a separate section

**Separation-before-rupture is not a margin and must not sit in the margin
table.** It carries no number: it records which branch the tension check took
(5020B Fig. 8), and listing it among margins is a category error that the first
build made. `ENGINE_CHECKS.md` says as much — it is one of "three rows that are
not margins".

It gets its own section, which generalises to everything that determined
*which* equations ran:

| Decision | Source |
|---|---|
| Separation before rupture — assured or not | `Result.Narrative`, 5020B Fig. 8 |
| Bolt bending — included, or the §4.4.4 determination that excused it | 5020B §4.4.4 / Eq. 20/22, `Result.Bending` |
| Shear plane — which area and which exponents ran | `Joint.ShearPlane`, Eq. 12/13 and 20–23 |
| Fastening-system allowable — which member governs | §2's `Allowable from:` line |

These are choices with consequences, not a trace, which is why the section is
named for decisions rather than for a path.

### 8.3 The rest

- Detail panel for the selected row: `Method` (the equation citation) and
  `Detail`, plus the `Allowable from:` line on Tension-Ultimate (§2).
- Warnings from `Result.Warnings`, rebuilt from scratch on every render and
  never accumulated. Refreshed only from the show-result path — refreshing them
  when the user starts editing would be anti-conservative (A3).
- Scope footer per §2: all 15 shown, and still not a complete assessment.
- Stale banner when any input changed since the shown result was computed, with
  the table muted and the rail carrying its amber dot. Muting is cosmetic and
  never allowed to break the numbers.
- The rail navigates here automatically after Analyze; the first failing row is
  selected, or row 1 if none fail.

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

**Roll-up.** `engine.analyzeBulk` emits `WorstMargin` and `GoverningCheck`
columns; neither is displayed (§2). In their place, a **split pass count** over
the whole run — `5020B: 12 PASS, 1 FAIL | Supplemental: 13 PASS, 0 FAIL`. The
split is compliance communication: a bearing failure must not read as
NASA-STD-5020B non-compliance, and a 5020B failure must not hide among
supplemental ones. Counted through the ratio-aware helpers, so a failing
interaction (`R > 1`) fails the 5020B count even though it never governs
`WorstMargin`.

**Counts are taken over the FULL result set**, never the filtered view. The
verdict is a statement about the run; the filters are a statement about the
screen. A partial (cancelled) run that is otherwise all-pass renders **amber**,
never green.

**Column groups are a WIDTH concession, not a scope one.** Core = the checks
5020B gives equations for; supplemental = the ones it defers to TM-106943.
"Show Supplemental" changes which columns fit on screen and nothing else —
the counts include both groups either way, and so does the export.

**The row filter must never reach the export.** Tier 3's failures-only default
is a *view*. Export writes every row and every column — an analyst who filters
to failures and exports still gets all of them. Row scope and display scope are
separate concerns; conflating them loses data silently. The MS display cap is
the same kind of concession and is likewise absent from the file.

**Export carries all 15 checks**, with the scope statement (§2) in the workbook
and the PDF: what is missing is TFSR 11, not a subset of columns.

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
| 5 | Defined Joints |
| 6 | Element Mapping |
| 7 | Element Forces |
| 8 | Bulk Analysis |
| 9 | Materials & Hardware — **DONE** (see §16) |
| 10 | Help menu + References window; delete `+gui` — **DONE**. Phase 4 complete. |

---

## 15. Open items

- ~~Two pages named "Library".~~ **Resolved** — the rail labels are now
  *Defined Joints* and *Materials & Hardware*, which drops the collision
  `GUI_PORT_SPEC.md` §1 warned about and fixes the rail fit at the same time.
  The scope difference still gets stated in-page on each: **Defined Joints is
  case-scoped** (saved in the case file, travels with the analysis);
  **Materials & Hardware is app-scoped** (baseline plus custom, persisted to
  `library.json`, shared across every case).
- **Three thin setup pages.** Project is ~4 fields and Temp Loads ~3. Defensible
  — they are easier to build and review separately, which is the point of this
  pass. If they feel sparse once built, merge into one *Project Setup* page with
  a nested `uitabgroup`. Temp Loads needs an *applies to every joint* banner
  regardless, since it is global and sits among per-joint-looking pages.
- **Automatic L1 needs a library change.** Closed for this pass (§7.2(d)): no
  seeded bolt carries `threadLength`, so L1 can only be entered. Deriving it
  would mean per-part-number bolt entries (thread length is length-dependent,
  not a property of the thread size), which is a `+data` change and a separate
  decision — it would multiply the 25 catalogue entries by every ordered length.
- **Dark mode** — near-free in R2026a, but below performance in priority.
  Deferred, not ruled out.

---

## 16. Materials & Hardware — BUILT (step 9, 2026-08-17)

`gui2.HardwareLibraryPage`. The design below was rescued from
`GUI_PORT_SPEC.md` §6 when that file was deleted; three parts of it were
**changed on the way in**, and those changes are marked. Everything unmarked
was built as written.

**Two different things share the word "library" — keep them straight.**
*Materials & Hardware* is app-scoped (baseline + custom, persisted to
`library.json`, shared across every case). *Defined Joints* is case-scoped (a
dict inside the case JSON, unprotected). The rail labels already reflect this;
each page states it in-page too.

**Structure.** A `Source:` filter (All / Baseline / Custom) above sub-tabs —
Materials, Bolts, Nuts, Inserts, Washers, Bolt Specs — each an identical
"table + button bar". **Write one parameterised builder and call it once per
entity type**; do not write six near-identical tabs.

**CHANGED — no inline editing.** The original called for double-click-to-edit
committing straight to storage, with per-row protection enforced in
`CellEditCallback` by reverting `t.Data` on a baseline row. Built instead as
**browse + Add + Duplicate as Custom**, every table `ColumnEditable = false`.

Two reasons. A table that *looks* editable and then reverts teaches the analyst
to distrust the page — and `ColumnEditable` is per-column, not per-cell, so
every baseline row would have had to invite the edit before refusing it.
Second, `data.Library` has no edit-in-place method, and adding one means
rename handling plus referential integrity for the cross-references
(`boltSpec.bolt`, `nut.material`) that nothing else needed yet.

**CHANGED — Duplicate opens the form pre-filled, rather than committing a copy.**
`duplicateAsCustom` on its own produces an entry identical to the original under
a new name, and nobody duplicates an allowable to keep every number the same —
the copy exists to be changed. With inline editing out of scope the pre-filled
form *is* the edit. It is also where the new citation is demanded: a copy that
silently inherited the original's `source` would attribute the analyst's numbers
to a document that does not contain them.

**The data layer is ALREADY BUILT — do not re-design it.** `data.Library`
carries an `origin` field (`"baseline"` | `"custom"`, absent = baseline),
`save()` writes only custom entries and `load()` re-merges the shipped baseline,
and `duplicateAsCustom(key)` exists for every managed section. The three reasons
it was built first still explain the constraints the page must respect:

- **Upgrade safety.** Without the split, `save()` would write the whole merged
  table to the user's file, and a corrected baseline value would never reach
  them — their stale file would win forever. A data-correctness problem, not a
  UI one.
- **Compliance traceability.** *"Was this allowable the shipped reviewed value,
  or something an analyst typed?"* must be answerable from the output.
- **Cost asymmetry.** Retrofitting after users have saved libraries would mean a
  migration that guesses which rows were baseline. There is no good guess.

**CHANGED — origin renders as the words `baseline` / `custom`, not 🔒 / ✏.**
The glyphs are non-ASCII (the lock is outside the Basic Multilingual Plane),
this code is written on a machine that never runs it, and a font-fallback or
file-encoding problem on the Windows target would silently break the one column
that carries the protection state. A word cannot fail that way. Inherited from
the first-pass DB tab, which made the same call for the same reason. No colour,
no separate table.

**The key UX move: `Duplicate as Custom` works on any row.** A user who wants to
tweak a baseline material duplicates it (name gets a ` (Custom)` suffix) and
edits the copy. Protection without an escape hatch just makes people angry.

**Skip admin mode.** Duplicate-as-custom covers ~95% of the need, and curating
the shipped baseline is better done by editing the seed file directly. The
admin tier, checksums and the packaging-path split are still only designed, in
`LIBRARY_PLAN.md`.

**Any library change must refresh dependent dropdowns**, or a newly added
material is invisible until restart. Built: `JointConfigPage` subscribes to
`LibraryChanged` — nothing in `+gui2` did before step 9 — and every picker
saves and restores its selection across the repopulation, because setting
`Items` can drop `Value` and MATLAB fires no callback when it does. The nut and
washer family pickers restore a **token** rather than a label, since their
`Items` are display strings and their `Value` is `ItemsData`.

**Persistence.** Custom entries go to `data.Library.userPath()` —
`userpath()` plus a repo-local fallback, mirroring the factor presets.
`save()` refuses the bundled seed and a compiled standalone cannot write its
own install directory. `data.Library.loadInstalled()` is the read side, and
`AppState`, `runBulk`, `runWorkbook` and `makeTemplate` all go through it: the
bare `load()` reads only the seed, so a saved entry would have been invisible
to bulk and gone from the GUI on the next launch.

**Provenance.** Every written entry carries a mandatory `source`, plus
`modifiedBy` / `modifiedUtc`. `approvedBy` / `approvedUtc` are in the schema
and preserved across a round trip but nothing writes them — signing an
allowable off as reviewed is a separate act the tool does not perform. See
`COMPLIANCE.md` and `data.Library`'s header.

## 17. Joint cross-section preview — deferred, geometry only

Also rescued from `GUI_PORT_SPEC.md` (§13). Still deferred, still the lowest
value-per-hour item on the list, but it is a real design and nothing else
records it.

Draws a to-scale axial cross-section: head → washer → flanges (split left/right
with the true clearance gap) → nut/insert/tapped host → shank at true length,
plus centreline, dashed frustum lines at the joint's frustum angle, per-flange
labels, and — after analysis — the loading-plane line.

**Genuinely useful, not decorative.** It catches exactly what the Joint Config
form is prone to: a bolt too short for the stack, a washer wider than the
flange, an implausible engagement, a loading plane outside the grip.

**Geometry only.** On a `uiaxes` with `DataAspectRatio = [1 1 1]` and limits
taken from real dimensions, ~15 `rectangle`/`patch`/`line`/`text` calls do it —
and **drawing in MATLAB data coordinates removes the manual pixel-scaling layer
entirely**. Skip gradients, hex chamfers and coil hatching. Host it in a
right-hand column of Joint Config rather than a separate window.
