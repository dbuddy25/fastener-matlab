# Pre-compile manual checklist

**Run this in MATLAB, before `mcc`.** It is deliberately *not* a re-run of the
automated suite. The 842 tests already build every page programmatically and
make ~850 assertions about them; repeating that by hand proves nothing new.

What this covers is the complement — what a programmatic test **structurally
cannot see**:

- whether anything is *drawn* where a human would look for it,
- whether a real file dialog, a real `.xlsx` and a real PDF behave,
- whether the numbers on screen are the numbers the engine computed,
- whether the failure paths say something an analyst could act on.

**If you only have twenty minutes, do section B.**

> This is the *pre*-compile pass, in MATLAB. `MATLAB_BUILD_GUIDE.md` →
> "What to check first on the packaged app" is the *post*-compile pass, on the
> `.exe`. Different lists on purpose; neither replaces the other.

---

## A · Launch and shell

- [ ] `cd matlab`, then `fastenerTool`. Version banner prints, one window opens.
- [ ] No warnings, no stack traces, nothing red in the Command Window.
- [ ] **No library-failure alert on startup.** If one appears, stop — the status
      bar locks, and File → Save *and* Analyze are both disabled. Nothing below
      this line will work.
- [ ] Rail shows all ten entries under SETUP / SINGLE JOINT / BULK / REFERENCE.
- [ ] Click all ten. Each builds on first visit, nothing throws, nothing renders
      blank or half-height. *Pages build lazily — first click is the real test.*
- [ ] Active entry is pressed + bold, one at a time.
- [ ] **Resize: drag narrow, drag wide, maximize.** No overlap, no clipping,
      nothing vanishes. *Grids pass tests at construction size and fall apart at
      every other size — invisible to `verify`.*
- [ ] Footer summary bar shows FF, the four FS values, and the temperature trio.

## B · The number that matters — DABJ §9 built by hand

**Highest-value item here.** `tDabjCase` proves the *engine* reproduces the
published answer key. Nothing proves the **GUI** does — that what you type lands
in the fields the engine reads, and that the margins shown are the margins
returned. That path only runs when a human runs it, and it is the only test in
the project with published numbers behind it, so a mismatch is unambiguous.

Build the DABJ Section 9 joint through the UI. `+validation/dabjSection9.m` has
every input and flags its two assumptions.

Key inputs: 4 bolts, 3/8-24, body in shear, μ = 0.1, loading-plane factor 0.5,
rated ultimate 15,200 / yield 11,400 lbf, torque control 470 in-lbf ±20, nut
factor 0.15, uncertainty 0.25. Limit loads: bolt tensile 5,590, bolt shear
1,560, joint tensile total 16,090.

Watch the **"Required before Analyze: …"** label empty out as you go — that
gating is the page's own, and it is the only thing that enables the button.

Press **Analyze Single Joint**. It should auto-navigate to Results.

| Check | Expected | Tol |
|---|---|---|
| Tension-Ultimate | **+0.69** | ±0.01 |
| Separation | **+0.16** | ±0.01 |
| Bolt Yield | **+0.63** | ±0.01 |
| Shear-Ultimate | **+3.18** | ±0.01 |
| Interaction | **+0.59** (a = 1.59) | ±0.01 |
| Joint Slip | **−0.65** | ±0.01 |

- [ ] All six match.
- [ ] Preload readout: PpMax **11,070**, PpMin **6,470**, thermal Δ **180**.
- [ ] **Joint Slip shows as failing, and is colored as a failure.** The only
      negative margin in the set — so the only proof that pass/fail coloring is
      wired to `Status` at all.
- [ ] **Interaction reads as passing.** It reports R, passing iff R ≤ 1 — the
      opposite direction from every other row. A view that naively treats
      "negative = bad" gets this one backwards.
- [ ] All **15** checks listed, not just these six.
- [ ] Toggle **Cap MS > 5**. Shear-Ultimate (+3.18) stays visible; the display
      changes and **the title bar `*` does not appear** (display-only control).

*If a margin is off, stop. That is an engine or wiring defect and it outranks
everything else on this list.*

## C · Two invariants worth attacking directly

Both are stated design rules, both are cheap to break, neither is obvious.

- [ ] **Programmatic repopulation never dirties the case.** With a clean saved
      case: navigate all ten pages, change the joint filter, toggle Failures
      Only / Show Supplemental / Cap MS > 5, select table rows. **The `*` must
      never appear.**
- [ ] **A failed analysis never clears a result.** After section B, set a bad
      temperature trio (Hot < Cold) and Analyze. You should get an alert, the
      **previous result must still be on the Results page**, and the rail glyph
      must go amber/stale. A cleared result here would silently lose work.

## D · Case files round-trip

- [ ] **File → Save As** — real dialog, file lands where you chose.
- [ ] **File → New** clears everything.
- [ ] **File → Open** the saved file. Every value returns — analyst name and
      factors too, not just the joint.
- [ ] Re-run Analyze. **Same margins as section B.**
- [ ] Edit one field → title shows `*`. Save → it clears.
- [ ] **Open Recent** lists it. Open from there.
- [ ] Save, delete the file outside MATLAB, then Open Recent it. Polite "no
      longer on disk", entry removed, no throw.
- [ ] **Close the window with unsaved changes.** Dialog appears; **Esc cancels**
      (Cancel is both default and the Esc action). Then Discard and confirm it
      actually closes — the close is the *continuation* of that dialog, so this
      is worth watching rather than assuming.

## E · Things only eyes can catch

- [ ] **View Cross-Section** on Joint Config. A to-scale axial section in a
      separate window — the one place where "wrong" means *looks wrong*, and no
      assertion can see it.
      - Layers stack in physical order; washers where washers go.
      - Proportions match the real joint (3/8 bolt, 0.75 grip).
      - Nothing drawn outside the axes.
- [ ] Change bolt diameter with it open. **It repaints.**
- [ ] Close and reopen. **One window, not two** (shell-owned singleton).
- [ ] Close the main window with it open. It goes too.
- [ ] Rail **stale/loaded glyphs** appear and clear as pages gain and lose data.
- [ ] On Element Mapping, create a **duplicate element id** (amber) and a
      **blank/unknown joint name** (pale red). Both colorings visible.

## F · External handoffs — the real compile-risk surface

Every item depends on something outside the `.m` files — exactly what compiling
disturbs. **Record the behavior now** so you can tell a build regression from a
pre-existing gap.

- [ ] **Help → About** shows a version.
- [ ] **Help → User Guide.** **This has never executed anywhere.** Report
      Generator is absent from the test machine, so `tUserGuide/itBuildsAPdf`
      skips — that is the 1 incomplete in the 842. If you have Report Generator,
      this is its first-ever run: progress dialog, then the PDF opens from
      `prefdir`. If you don't, the guard at `+report/userGuide.m:51` reports
      "unavailable". **Write down which one you got.**
- [ ] **Results → Save PDF Report...** Opens in a real viewer, carries the
      version stamp, margins match section B. *Slowest action in the app —
      `report.singleJointReport` re-runs `engine.analyze` internally.*
- [ ] **The PDF reports what was analyzed, not what is on screen.** Analyze,
      then change the bolt count *without* re-analyzing, then Save PDF. The PDF
      must show the **analyzed** joint. (It uses `ResultInputs` by design; this
      is the check that proves it.)
- [ ] **Results → Export Table...** as `.xlsx`. Open it: three sheets
      (Results / Summary / About), headers, units and numbers intact.
- [ ] Export again **over the same filename**. `report.exportResults` deletes
      the existing file first — confirm you get a clean new file, not a
      corrupt or half-written one.
- [ ] **Help → References.** Opens. For the 9 copyrighted PDFs that never ship,
      **Open** should be disabled or explain itself — never error.
- [ ] **Choose folder** on References persists. Restart the app; still set.

## G · Bulk workflow

- [ ] **Element Forces → Export Template...**, open in Excel (README + two load
      case sheets), fill a few rows.
- [ ] **Import Workbook...** it back. The **min/max range columns** match what
      you typed — that preview is the units sanity check, and an
      order-of-magnitude error shows up here or nowhere.
- [ ] Set a **Scale** ≠ 1 on one load case. The detail table reflects it
      (scale is applied on display and never comes from the file).
- [ ] Save two joints via **Save to Defined Joints**; try a duplicate name and
      confirm the overwrite prompt.
- [ ] **Element Mapping** — map ids. Try **+ Bulk Add...** (its own dialog) and
      the bulk-assign row.
- [ ] **Run Bulk Analysis with something deliberately missing** — no mapping, or
      a joint name that isn't defined. The gate must name the problem *and* give
      you a **"Go to <page>"** button that actually navigates.
- [ ] Fix it, run for real. Progress dialog appears; **Cancel mid-run** keeps
      the partial table and says "Cancelled — n of N".
- [ ] Run to completion. All three tiers populate.
- [ ] **`Failures Only` is ON by default** — if everything passes the table
      looks empty. Untick it and confirm rows appear. *Worth knowing before you
      mistake a working run for a broken one.*
- [ ] **Cross-check one element** against a single-joint run of the same joint.
      Easiest via **Show in Single Joint Analysis** on a By Element row. They
      must agree — Bulk and Results share `MarginView` so they cannot drift, and
      this is the check that proves it.
- [ ] **Export...** the bulk table. It exports the **complete** table, not the
      filtered view — verify the row count in the success alert matches the
      unfiltered total, not what's on screen.
- [ ] Edit any case field → Bulk goes stale, Export locks until re-run. (Known
      over-conservative: editing the analyst name does this too.)

## H · Materials & Hardware, and persistence

- [ ] Six tabs populate: Materials, Bolts, Bolt Specs, Nuts, Washers, Inserts.
      Note **Bolt Specs is empty by design** (the DABJ fixture entry was removed).
- [ ] **Source** filter: All / Baseline / Custom.
- [ ] **Add…** a custom material. Required-field validation refuses a blank.
- [ ] **Duplicate as Custom…** an existing entry — key uniquifies to `(Custom)`.
- [ ] The new material **appears in the Joint Config dropdowns without a
      restart** (`LibraryChanged` wiring).
- [ ] **Save Library**, quit MATLAB entirely, relaunch, reopen. **The custom
      entry is still there.** *This writes to `userpath`/`prefdir`, not the case
      file — it is the same mechanism the packaged app depends on because
      `Program Files` is not writable. Proving it here means a post-compile
      failure is a path problem, not a logic one.*

## I · Deliberate abuse

Error paths are written blind and read by an analyst on a deadline.

- [ ] Analyze with **required fields blank** — the gate names what's missing in
      words, not identifiers.
- [ ] **Negative diameter**, **zero preload**, text in a numeric field. Refused
      clearly; no raw MATLAB error text reaches a dialog.
- [ ] **Cold > Hot** on Temp Loads — rejected, and the field **reverts** to the
      last valid value.
- [ ] Import a **non-workbook file** as forces.
- [ ] Import a workbook with the **wrong sheet layout**.
- [ ] Import a workbook that **parses but yields zero usable rows** — this has
      its own alert, and it is the dangerous silent case if it doesn't fire.
- [ ] **Delete a defined joint that has elements mapped to it.** The confirm
      must *count the orphans* it will create.

---

## Before you compile

- [ ] `runTests` — full suite, still **841 pass / 0 fail / 1 incomplete**.
- [ ] Every section-B margin matched.
- [ ] You wrote down what Help → User Guide did.
- [ ] Custom library entry survived a full restart (H).
- [ ] Anything found here is fixed, or consciously accepted.

**Then build, expecting the first one to fail.** `MATLAB_BUILD_GUIDE.md` §5.2
has the `mcc` line and its five post-build checks.

`library.json` is the one `-a` you must not forget — it is data, so dependency
analysis never sees it. If the library fails to load in the `.exe`, the first
suspect is already documented: `data.Library.defaultPath()` resolves it from
`mfilename` with no `isdeployed` branch, and `ctfroot` is the branch to add.
That fix was deliberately left to be written against a real build rather than
guessed at — so a failure there is the plan working, not the plan breaking.
