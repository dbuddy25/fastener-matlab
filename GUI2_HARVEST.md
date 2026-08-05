# Step 0 — behavior harvest from `+gui`

What the first-pass GUI learned the hard way. `+gui/FastenerApp.m` is ~20%
layout and ~80% earned edge cases; the layout is cheap to rebuild and this is
not. Every item here is a **requirement on `+gui2`**, not a description of old
code.

**Sources:** the 322 rationale-bearing comments in `+gui/FastenerApp.m`, plus
`GUI_PORT_SPEC.md` §11 (hard-won UX details), §12 (units) and §14 (known traps).

**Confidence note:** §A–§C below are drawn from in-code rationale comments and
the superseded spec, not from a line-by-line read of all 229 functions. They are
the *load-bearing* rules. Pages marked ⚠ in §B need a deeper read of the
function bodies when that page is built.

---

## A. Cross-cutting invariants

These apply to every page. Violating one is a defect, not a style difference.

### A1. Unknown must never look like fine

The single most-repeated rule in the file (~8 sites). `NotEvaluated` / `NaN` /
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
ratio-aware helpers (`isRatioColumn` / `envelopeAcrossRows` / `passFailMask` in
the old build), never a plain `< 0` test. Two specific consequences:

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

---

## B. Per-page checklists

### Setup pages (Project / Factors / Temp Loads) — harvested during the step-2 build

These three split out of the old single "Project & Factors" tab
(`buildProjectTab`, `+gui/FastenerApp.m` ~825–1010) plus its scattered
helpers. Rules earned building `+gui2`'s versions, not already covered by §A:

- **The FF field is a single knob over four engine slots, and the four can
  disagree.** `model.Factors` keeps FFU/FFY/FFSep/FFSlip separately; the GUI
  exposes one FF field (NASA-STD-5020B 4.2.2 [TFSR 3]: one factor multiplies
  every factor of safety). A loaded case or applied preset can carry UNEQUAL
  values (the DABJ fixture: FFU=1.15, the rest 1.0) — collapsing that onto one
  field and writing it back on the next Analyze would silently change the
  loaded margins. Preserve the four verbatim, show a mixed-FF banner, and only
  collapse to one value when the analyst actually edits the FF field.
  `model.Factors()`'s own default is the DABJ mixed set — a **blank case must
  force the four slots uniform instead** (`AppState.blankCaseState` does
  this), or a fresh case opens already in the mixed-FF warning state.
- ~~There is no public enumerator for user-saved factor presets.~~
  **Resolved — `data.factorPresetNames` added.** `+data` originally exposed
  only `factorPreset` (lookup by exact name), `factorPresets` (built-in map)
  and `saveFactorPreset` (write); the on-disk reader
  (`loadUserFactorPresets`) and the path resolver (`userFactorPresetsPath`)
  are both `+data/private`. A user could therefore **save a preset and never
  see it listed** — the store was undiscoverable from outside `+data`.

  This was the first time the pure-GUI rule (`GUI2_SPEC.md` §1.1) genuinely
  bit, and it was resolved by an **authorized, scoped exception**: one
  read-only enumerator, computing nothing and owning no state, covered by
  `tCaseIO`. The rejected alternative was parsing `factorPreset`'s error text
  for its "Available: ..." list — fragile in the worst way, since a wording
  change in an error string would break the dropdown at runtime with no test
  to catch it.

  **The precedent, for the pages still to come:** the frozen-package rule
  protects the *math*, not the package boundary. A missing read-only accessor
  is a reason to ask, not a reason to duplicate private logic in `+gui2`.
  Ask; do not work around.
- **Neither `factorPreset`/`saveFactorPreset` nor their private helpers take a
  file override reachable from the GUI.** Both accept one for tests
  (`saveFactorPreset(name, factors, file)`), but the GUI always calls the
  2-arg form, so every preset Save/Load from the running app touches the
  REAL user preset store (`userpath()/fastener_factor_presets.json`, or a
  repo-local fallback file directly inside `+data/` when `userpath()` is
  empty). A GUI test that exercises Save/Load for real must back that file up
  and restore it byte-for-byte — the same discipline `tGui2Shell` already
  applies to `gui2.recentFiles` — or every test run leaves permanent junk in
  a real preset file, with no delete API to clean it up afterward.
- **Temp Loads is the one place `AppState.Settings` can hold an invalid
  ordering without the page's own entry-validation ever having run.**
  `AppState.readCaseFile`/`parseSettings` copies `nominalTempC`/`hotTempC`/
  `coldTempC` from a case file verbatim, with no Cold<=Nominal<=Hot check —
  that check lives only in the Temp Loads page's edit handler. So `refresh()`
  must show whatever AppState actually holds (never substitute a "nicer"
  value — that would hide a bad file), but must NOT blindly adopt an invalid
  incoming trio as the "last known good" value to revert to on the next bad
  edit; keep the previous (guaranteed-valid) revert target instead.
- **A `uidatepicker` has no supported blank state to carry through a round
  trip.** `AppState.defaultProject().date` is `""` (a genuinely blank case),
  but the picker widget always needs a real `datetime` — there is no
  proven-safe way to show "no date" in it. The proven `+gui` behavior
  (display today's date when the stored value is blank, but leave the
  *committed* value blank until the analyst actually changes something) is
  the safer carry-forward than experimenting with an untested "allow empty"
  widget property this environment cannot verify.
- **Bare `bindEdit` marks dirty even when a subsequent validation revert
  leaves the case state itself unchanged** (e.g. Temp Loads rejecting an
  invalid ordering and reverting the field). This is a harmless false
  positive baked into `bindEdit`'s unconditional-dirty design (`Page.m`), not
  a per-page bug to work around — it can only over-mark, never under-mark, a
  real edit.

### Joint Config

Harvested from `buildJointDefinitionPanel`, `buildLoadsPanel` and every handler
they reach. This page is where §A's hardest invariants actually live — A5
(auto-fill then lock), A6 (required blank), A9 (cross-type field crossing) are
all one page's problem.

**Sync is not an edit.** `applyNutSpec`, `applyWasherSpec`, `refreshWasherState`,
`syncWasherEnables`, `updateEngagementFieldMode` and `mirrorNutWasherFromHead`
**never** mark dirty. They run during panel construction and from the
case-loading path, where a dirty flag is a lie — a brand-new session would open
with a `* ` title and prompt to discard on close. Genuine edits are marked by
the edit funnel *before* the callback runs, so these can be called from
anywhere. Every one of them must also be idempotent and must no-op cleanly
before the panel is built.

**One cascade, four triggers.** Changing the **bolt** re-resolves the bolt spec,
the nut spec, and *both* washer specs, then refreshes the length readout — a
nut or washer match is keyed on the selected bolt's thread size, so a bolt
change invalidates all of them at once. The same orchestrator runs on a
member-type change, a washer Present toggle, panel build, and case load. Do not
wire these individually; there is one entry point per picker
(`applyNutSpec`, `refreshWasherState`) and every trigger calls it.

**Miss handling is uniform, and it is the point of the feature.** A spec family
with no entry at the resolved thread size **reverts to `Custom`, re-enables the
fields, and names the miss in the status bar** — the family and the bolt thread,
not "no match". Leaving the previous bolt's numbers locked and looking
authoritative is the exact failure the picker exists to prevent. Same contract
when a resolved nut names a material absent from the library: revert to
`Custom`, say which key was missing. A "select this key" helper that silently
keeps the previous selection on a miss must have its miss report captured —
discarding it re-creates the bug.

**Washers differ from nuts in two ways.** `washersFor` returns MANY matches
where `nutFor` returns one, so a washer group carries a *paired* size dropdown
listing every match (thinnest first). The current selection is kept if it is
still among the matches, otherwise the thinnest is auto-selected — the dropdown
is never left blank while OD/ID/thickness sit locked. And the nut washer has
`Same as Head` layered on top.

**Nut-washer gating is three gates deep**, outermost first: member type is not
Nut → the whole group is disabled (there is no nut, so a washer under it is
meaningless); then `Same as Head` → mirror and disable; then Present → gate
OD/ID/thickness and material. Gray, never hide: an analyst has to be able to
see that a field exists and why it is unavailable.

**Washer size lists change length between families**, so any repopulation must
go through the set-items-and-data helper. A bare `Items` assignment throws while
the old `ItemsData` pairing is still attached. Capture the previous value
*before* assigning, never after.

**The engagement field is one control with two meanings** — inches for
Nut/Tapped Hole, a multiple of the bolt nominal diameter for Insert. Nut ↔
Tapped Hole is not a crossing (both inches) and the value survives. Insert ↔
anything **is**, and the value is cleared with a status-bar note (A9). The
relabel-per-type routine must never touch the value: only a genuine user-driven
crossing clears it, or loading a case would wipe the number it just loaded.

**The live bolt-length readout is four lines and three states**, driven by
`engine.boltLengthCheck` on a probe joint built from the current controls:
muted when adequate, **amber when the check cannot run** — naming the missing
inputs in the form's own words — and bold red when short. The verdict keys off
`RequiredLength` being NaN, never off an `IsAdequate` flag alone: the original
bug was a grossly short bolt rendering in the same muted style as an adequate
one. Bad typed input is caught and rendered amber; **never an error dialog on
an edit**. The probe must resolve engagement the same way the built joint will,
or an inch value typed in Insert mode gets read as inches here and as a ratio
later.

**Required fields are conditional.** Bolt material and member material are
always required; a flange layer's material is required **only while that row is
in use** (Active checked *and* thickness > 0 — the identical predicate that
marshals the stack). So toggling Active or editing a thickness changes the
required set and must re-run the check. Blank required dropdowns paint pale red
and disable Analyze with a tooltip naming the missing fields *in the user's own
labels*. Programmatic population fires no callbacks, so the check must be
re-run explicitly after every load.

**Fail twice, deliberately.** The continuous check gates the button; a second
assertion at marshal time fails with the same user-facing wording if a blank
ever slips through. Without it the library throws about an internal key.

**A failed Analyze stales the previous result rather than clearing it** — the
numbers on screen predate the failed run and must stop looking current, but
they stay readable (A3).

**Save to Defined Joints preserves what the form does not own.** Overwriting
asks first, and carries over the fields Joint Config has no control for —
per-layer names, tapped-hole host name, preload creep loss and thermal rate.
Host name carries over **only when the member type is unchanged**; a type change
makes the old detail stale. Two fields are deliberately *not* carried: the
insert pitch diameter is re-resolved from the current bolt on every marshal, and
the shear engagement area is never analyst-supplied at all (§4.4.1 wants a rated
load or specified catalogue geometry, not a typed area), so preserving a stale
value would reintroduce the very override the field no longer accepts.

**Marshalling details that are easy to get wrong:** an absent washer marshals as
the model default (zero thickness, NaN diameters), not as zeros typed by the
user. Blank optional text fields parse to NaN — the model's "automatic"
sentinel — but a non-blank non-numeric entry is a typo and must error loudly
rather than silently become automatic. Overall bolt length comes from the form,
not the library entry, because it is joint-specific.

### Single Joint Results

- Renders one `engine.Result`. **Never computes a margin, an area, or a
  threshold.**
- Governing row auto-selected; detail panel titled so it reads as *this row's*
  detail.
- Detail keys off explicit `Evaluated` / `Shortfall` fields, never off `NaN`.
- Fig. 8 narrative shown in-app, not only in the PDF (old trap #6).
- Preload readout frame stays visible when empty, so layout doesn't jump.

### Defined Joints

- Summary view mirrors the Joint Config panels **field for field** — the two
  must be changed together or the summary silently goes stale while still
  looking current.
- Bulk-edit grid: validate then rebuild; the underlying array is **never mutated
  in place**. On success *or* failure the grid is re-rendered from state.
- Range clamping belongs in the cell-edit callback.
- Deleting/renaming a joint must account for elements mapped to it.

### Element Mapping ⚠

- `Import IDs from Forces` bootstraps mapping from imported forces; a blank
  joint name is not allowed, so the user picks one.
- Mapping 200 elements must survive one bad row.
- Summary line never lets a problem render muted.
- Dismissing an error bar must not clear the red summary line.

### Element Forces ⚠

- Cross-validated against mapping: unmapped IDs, and IDs that can never be
  mapped, are called out distinctly.
- **Zero usable elements is the dangerous case** — must not look like success.
- An empty load case must never scan like a populated one; it escalates the
  icon rather than vanishing.
- Sheets parsed with zero usable rows must not read as a clean import.
- `": 101, 102"` ID suffix when ≤ 5 IDs, omitted otherwise.

### Bulk Analysis ⚠

- Margin columns are **discovered**, never hardcoded.
- Counts are taken over the **full** result set (the run verdict), so a
  supplemental failure cannot read as a pass, and a partial run never reads as
  a clean full verdict.
- Ratio columns handled per A2 everywhere, including the envelope.
- Cancellable; MATLAB gives cancellation free (old trap #5).
- Export per A11, and per `GUI2_SPEC.md` §9 the display filter never narrows it.

### Materials & Hardware

- An unseeded library never crashes the app; dropdowns land on the blank
  sentinel, never a silent first item.
- Duplicate-as-custom goes through `data.Library`; the page never copies
  entries itself.

### Shell / File operations

**Confirm-before-discard**

- `gui.confirmDiscard` **always asks when dirty, including when no file is
  open.** Skipping the no-file case is the classic way File → New destroys
  work: unsaved edits are just as real before the case has a filename.
- **Cancel is both the default (Enter) and the Esc/close action.** Destroying
  work must never be the path of least resistance.
- Wired on File → New, File → Open, and `CloseRequestFcn`. All three, or the
  gap is the bug.
- Every recurring dialog shape routes through one `uiconfirm` wrapper
  (`gui.askChoice`) that returns a known option string on Esc/close — so no
  caller ever handles an empty/char special case.

**File → New**

- Resets through the **deserializer** (A7), never by setting page literals.
- Must explicitly clear the joint library, element mapping **and** element
  forces. They are case state; leaving them is a silent carry-over.
- Sets `CurrentFile = ""`, `IsDirty = false`, updates the title — then
  **explicitly stales any displayed result**. The dirty funnel cannot do it,
  because `IsDirty` was just reset. Same for File → Open. This is the one
  place staleness is set outside `markDirty`, and forgetting it leaves a
  confident verdict on screen for a case that no longer exists.

**File → Open**

- `try/catch` around the file read, reported with `uialert` — never an
  uncaught error.
- The deserializer **returns the library keys the file referenced but the
  library does not have.** Required material dropdowns are left **blank**
  (choose replacements before Analyze); other dropdowns keep their previous
  values. The list is surfaced in a warning dialog. Silently substituting a
  material would analyze the wrong one.
- Accepts **two on-disk formats**: the GUI's own case container, and the
  headless `data.saveCase` container (delegated to `data.loadCase`) so
  command-line-era files open in the GUI. Anything else errors **with the file
  path in the message**.
- **Factors fallback when the file carries none:** fitting factors are forced
  uniform (`FFY = FFSep = FFSlip = FFU`). `model.Factors()` alone is the DABJ
  *mixed* set, and opening a file in the "per-check fitting factors" warning
  state it never contained would mislead.
- Older files that wrote `mapping` / `forces` as empty structs with no
  `elements` key fall through to the empty default rather than erroring.

**File → Save / Save As**

- Save with no current file **falls through to Save As**.
- Save As **auto-appends the extension** when the user omits it.
- **Refuses to save when the hardware library failed to load** — the joint
  controls cannot be serialized, and a partial file is worse than none.
- `jsonencode` with `ConvertInfAndNaN = false`, so the model's `NaN`
  "unconfigured" sentinels round-trip as literal tokens. Pretty-print is
  attempted in its own nested `try/catch` and degrades silently.
- Check the `fopen` return; close via `onCleanup`, not a trailing `fclose`
  that an error skips.
- **The case container ships every key from day one** — mapping and forces
  included, even while empty. A container that omits them loses the user's
  bulk setup on every save (`GUI_PORT_SPEC.md` §14 trap 1).
- Model objects serialize through `data.toStruct` / `data.fromStruct`, the
  tested round-trip core. **Never hand-rolled.**
- Names cannot be struct field names, so name-keyed collections (defined
  joints) serialize as arrays of `{name, value}` pairs, not as structs keyed
  by name.

**Library load failure**

- Degrade gracefully: the app still opens, `LibraryOK` is false, and the
  failure is reported by a **non-blocking `uialert` after the window is
  visible** — never a modal dialog during construction.
- While the library is unavailable that failure **owns the status bar and the
  Analyze tooltip**; no other status message may overwrite it. Two independent
  disable reasons must not clobber each other's explanation.

**Not built in the first pass — no behavior to harvest**

- **Open Recent** — deferred, never implemented. `GUI2_SPEC.md` §4 specifies
  it (5-item cap, persisted, non-existent paths filtered, disabled
  `(no recent files)` item when empty); it is a **new build**, not a port.
- **Import Joints from File** — deferred, never implemented. Also a new build.
- **Keyboard beyond menu accelerators** — there is **no `KeyPressFcn`
  anywhere** in the first pass. `GUI_PORT_SPEC.md` §11's "F5 runs Analyze" was
  aspirational and never wired; §D below repeats the claim and is likewise
  aspirational. Only `Ctrl+N` / `Ctrl+O` / `Ctrl+S` exist, as `uimenu`
  `Accelerator` values.
- **No "Load Example Case" menu item**, deliberately. The DABJ fixture served
  its purpose as the validated answer key, and a menu slip away from
  overwriting real work is the wrong place for it. It stays reachable from the
  command line via `validation.dabjSection9`. **Do not add it back.**

---

## C. Known bugs — do not reintroduce, and test for them

1. **Tapped Hole silently behaved as bolt-only.** In the Bolt Sizing tab, the
   member-type comparison could never match `'TappedHole'`, so selecting it
   fell through to the empty-member branch: member fields never enabled, and
   the analysis quietly ran bolt-only. Joint Config's own dropdown never broke
   because it tests `isNut`/`isInsert` booleans and treats "neither" as
   TappedHole. **Rule: derive member type from explicit booleans with a
   defined fallback, never from string equality against enum names.** Worth a
   test even though Bolt Sizing itself is out of scope.
2. **Stale rated loads across a bolt/material change** — blanking the previous
   pairing's auto-filled values is what stops the new pairing being analyzed
   with the old bolt's numbers.
3. **Joint-load tooltip contradicts the engine** — see `GUI2_SPEC.md` §7.3.

---

## D. Concrete values worth carrying over

**Widgets**

- No numeric spinner arrows anywhere — typing is preferred. `uieditfield('numeric')`
  throughout; `uispinner` only for a small bounded count.
- Frustum angle is an **integer** field.
- `F5` runs Analyze, via the `uifigure` `KeyPressFcn` — ⚠ **aspirational, from
  `GUI_PORT_SPEC.md` §11; never built.** There is no `KeyPressFcn` in the first
  pass. Keep it as a want, not a port. See §B *"Shell / File operations"*.
- MATLAB components don't respond to the mouse wheel — **no scroll guard is
  needed**. Noted so nobody adds one.

**Decimals**

| Quantity | dp |
|---|---|
| Nut factor K, uncertainty Γ, relaxation | 2 |
| Geometry (washer OD/ID/thk, hole dia, thickness, edge dist) | 5 |
| Torque | 2 |
| Forces | 1 |
| Live-label lengths | 4 |
| Preload force | 0 |

**Layout**

- Group `RowSpacing = 4`, padding `[6 6 6 6]`; inline row spacing 8 px (4 px in
  the flange grid).
- Label columns `'fit'`, widget columns `'1x'`.
- 1-px `uipanel` vertical separators between logical clusters in dense rows.

**Wording**

- Temperature labels: `Nominal:` / `Hot:` / `Cold:`.
- Washer options show the **spec name** (`NAS1149 - Standard OD`), not thickness.
- No `(optional)` placeholders on project metadata.

### Layout conventions established in `+gui2`

Settled while building the setup pages. Follow them; they are what makes the
pages look like one application.

- **One banner format, from `gui2.Page.addBanner`.** Page-scope notes — what
  this page is, what its contents affect — are informational and all take the
  info palette. Never style one as an amber warning: it reads as a problem to
  resolve, and mismatched banners across pages read as a bug even when each is
  legible on its own. Emphasis goes in the words (`GLOBAL — applies to every
  joint`), never in per-page color.
- **Field rows are name | symbol | value**, with **fixed** pixel widths for the
  name and symbol columns. `'fit'` resolves *per grid*, so two panels using the
  same spec still misalign — fixed widths are what make separate panels read as
  one table.
- **Section panels hug their content.** Give the page grid a trailing `'1x'`
  gutter column and put panels in column 1. A panel stretched across the window
  around three narrow fields looks broken.
- **Value boxes never stretch.** A wide numeric box reads as a text field.
- **Wrapping text does not go inside a content-width panel** — it becomes a tall
  thin column of words. Banners and warnings span the page grid instead.
- **Successful actions report through `Page.setStatus`, never `uialert`.** A
  modal for routine success interrupts the user and blocks the App Testing
  Framework's gestures, so the next `press`/`type` in a test silently does
  nothing and an unrelated assertion fails later. `uialert` is for errors the
  user must acknowledge.
- **The footer summary bar is read-only.** It shows global state (factors,
  temperatures); it never sets any. Values that could be misread must name their
  own uncertainty — unequal fitting factors render `FF mixed a/b/c/d`, never a
  single number.
- **Test seams are public getters** returning real handles, so tests drive
  gestures rather than poking private state.

**Units** — ⚠ **`GUI_PORT_SPEC.md` §12 describes the original tool, not this
one.** The MATLAB build has **no unit layer**: US customary throughout, °C for
temperature (engine-native), with the °F display toggle and a metric system both
explicitly deferred and never built (`FastenerApp.m:159`, `:7151` — *"a metric
toggle is planned (Phase 4.12) but NOT"* implemented).

So there is no display↔internal conversion, no registry, no unit-toggle
round-trip to carry forward. If a unit layer is ever wanted, §12's guidance is
sound and worth following then — conversion **only** at the serialization
boundary, and the temperature convention stated once in `UNITS.md` and nowhere
else. See §F.

---

## E. Deliberately not carried forward

Recorded so the harvest isn't mistaken for a to-do list.

- **Bolt Sizing** — page dropped (`GUI2_SPEC.md` §3). Its `engine.boltSizingSweep`
  stays; item C1 above is still worth a test.
- **Joint cross-section preview** — `GUI_PORT_SPEC.md` §13, lowest value per
  hour, never built. Still deferred.
- **Preload method selector, direct-preload entry, creep-loss control,
  `ThermalRate` control** — removed from the first build on purpose (torque
  control only; `ThermalRate` retained for validation fixtures). Stay removed.
- **Dark mode** — deferred, not ruled out (`GUI2_SPEC.md` §15).

---

## F. Resolved — the scope questions

All four settled; the rule is in `GUI2_SPEC.md` §2, *"The displayed 9 is the
tool's scope."*

1. **Worst margin / governing check — not displayed anywhere.** Both span all
   15 checks (`analyze.m:269–277`), so either could name a row that isn't in
   the table. Nine colored rows carry the signal on their own. Bulk substitutes
   a **scoped pass count** (`7/9 pass`) for the engine's `WorstMargin` column.
   **Never recompute a minimum over the displayed subset.**
2. **Export scope — the displayed 9**, with the scope statement carried in the
   workbook and the PDF, prominent enough that a reviewer cannot mistake the
   file for a complete 5020B assessment.
3. **No unit layer for now.** US customary + °C, as today. Wanted eventually,
   so numeric formatting stays in centralized helpers (`fmtGeom`,
   `fmtOptional`, …) and is never inlined at call sites — that turns a future
   unit layer into an edit of a few functions rather than a sweep of every
   page. `GUI_PORT_SPEC.md` §12 is the design to follow when it happens.
4. **Warnings — moot, nothing to filter.** `Result.Warnings` rows are not tied
   to margin checks (`analyze.m:184`); the only sources are `PreloadNearYield`
   and `BoltLengthShort`, both joint-level. All warnings and the Fig. 8
   narrative always render in full.

Harvested in step 1 — see §B *"Shell / File operations"*. Three of those items
turned out to have **no first-pass behavior to carry forward**: Open Recent and
Import Joints were deferred and never built, and there is no `KeyPressFcn`
anywhere, so `F5` was never wired. All three are new builds against
`GUI2_SPEC.md` §4, not ports.
