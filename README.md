# Fastener Analysis Tool (MATLAB)

Ground-up MATLAB build of a NASA-STD-5020B bolted-joint margin-of-safety
analysis tool, deployable as a standalone Windows executable.

## Docs (read these first)

- **`USER_GUIDE.md`** — ⭐ **start here to actually use the tool** — a from-scratch
  walkthrough: setup, single-joint analysis, and the bulk workbook workflow.
- **`MATLAB_BUILD_GUIDE.md`** — the build sequence: five phases (1–5), each a
  chain of small steps with a "Done when" acceptance test.
- **`MATLAB_TOOL_PRD.md`** — the requirements spec (what to build + the rules).
- **`ARCHITECTURE.md`** — how the pieces fit together (layers, data flow, design
  decisions); a living doc, updated as each phase step lands.
- **`UNITS.md`** — the unit contract: English units (in, lbf, psi) with
  temperature in °C and CTE in 1/°C. Single source of truth for units.
- **`VALIDATION.md`** — the validation coverage matrix: every check/scenario, its
  answer-key source, and whether it's validated ✅ / hand-derived ✍️ / pending ⏳.
  A living doc — every new check adds a row.
- **`MARGIN_REVIEW.md`** — the row-by-row review of all fifteen margins against
  NASA-STD-5020B, walked with the engineer of record (complete, 2026-08-17).
  Records what changed, what was confirmed correct, and the open assumptions
  that are decisions rather than gaps.

## Source layout

```
matlab/
├── fastenerTool.m     entry point — prints the version banner and opens the GUI (`+gui2`)
├── +model/            domain types: Bolt, Material, Joint, enums (Phase 1)
├── +engine/           analysis math — the core (Phases 2–3); bulk entry points `runBulk` (three files) + `runWorkbook` (one workbook, Step 2c)
├── +data/             library loader (`data.Library` + `library.json`, Phase 2.2); bulk parsers (`loadJointLibrary`/`loadElements` + `templates/`, Phase 3.5b); global settings (`loadSettings` — temps + factors); workbook template generator (`makeTemplate` — Joints/Elements/Settings + Lists + Fields dictionary sheets, Step 2b); case save/load (`saveCase`/`loadCase` via generic `toStruct`/`fromStruct`, Phase 3.7); factor presets (`factorPreset`/`saveFactorPreset`, Phase 3.7)
├── +report/           XLSX export (`report.exportResults`, Phase 3.6); single-joint PDF report (`report.singleJointReport`, Phase 3.8, via MATLAB Report Generator)
├── +gui/              FIRST-PASS programmatic uifigure app (`gui.launch`) — a thin
│                      shell over the engine, deliberately plain .m rather than a
│                      binary .mlapp so it diffs in git (Phase 4). LEGACY and now
│                      fully superseded -- its Materials & Hardware DB tab was the
│                      last thing it still had, and step 9 rebuilt it. Deleted at
│                      step 10; do not build against it
├── +gui2/             the rebuilt GUI (`gui2.launch`, GUI2_SPEC.md) — what
│                      `fastenerTool` opens. Adds the bulk workflow, the joint
│                      cross-section view and the gate/allowables panels; nothing
│                      in it may call into `+gui`
├── examples/          runnable reference scripts (`run_bulk_example.m`)
└── tests/             validation + smoke tests (checked vs the worked example)
```

## Run it (machine with MATLAB)

Open MATLAB, point the Current Folder at `matlab/`, then in the Command Window:

```matlab
fastenerTool                 % version banner, then opens the GUI
runTests                     % the FULL suite -- note the capital T. `runtests`
                             % (lowercase) is MATLAB's own and skips this
                             % project's end-of-run failure summary

% construct a joint (Phase 1 acceptance):
b = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
               Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
               TensileStressArea=0.0200);
b.Pitch                      % -> 0.03125
```

> **Note:** developed on macOS (no MATLAB there), so acceptance is verified on the
> Windows/MATLAB work machine — `git pull` (or re-download), then run the above.

## Headless bulk analysis (the Headless Release workflow)

The streamlined flow is ONE workbook in, one margins workbook out — no GUI,
no CSV splitting:

```matlab
f = data.makeTemplate("my_joints.xlsx");            % generate the fill-in template
% ... fill the Joints / Elements / Settings sheets in Excel ...
T = engine.runWorkbook("my_joints.xlsx", "margins.xlsx");
```

`engine.runWorkbook` reads the Joints/Elements/Settings sheets by name (both
table readers auto-detect the header row, so the template's friendly banner
rows need no cleanup), applies the global temperatures + factors, analyzes
every element, and writes the results (`outFile` optional; it must differ
from the input workbook — the tool refuses to clobber the filled sheets).

If the three inputs live in separate files instead, the split form runs the
same pipeline:

```matlab
T = engine.runBulk("joint_library.csv", "elements.csv", "settings.csv", "margins.xlsx");
```

That single call loads the hardware/material library, parses the joint table
(`data.loadJointLibrary`), the settings file (`data.loadSettings`), and the
element-forces table (`data.loadElements`), applies the global temperatures
(`NominalTempC`/`HotTempC`/`ColdTempC`) to every joint, runs all 15 margin
checks per element (`engine.analyzeBulk`) with the settings-built
`model.Factors`, and writes the results to `margins.xlsx`
(`report.exportResults` — a Results sheet plus a Summary sheet with
Pass/Fail/Error counts). The settings argument is optional (empty/omitted →
the built-in `model.Factors()` preset and the joints' default temperatures);
omit the output file to just get the results table back.

The joint table uses the joint-table layout: `Bolt`/`BoltMaterial` library
keys (with the rated loads auto-looked-up from a matching library boltSpec, or
an explicit `BoltSpec` override), an `AxialX`/`AxialY`/`AxialZ` mark for the
bolt direction, On-gated `HeadWasher*`/`NutWasher*` blocks, `Nut*` /
`HelicoilParent*` threaded-member columns, `Flange1..4*` layer blocks, and the
`NutFactor`/`Uncertainty`/`PreloadLoss`/`NominalTorque`/`TorqueTolerance`
preload group — no temperature columns (those are global settings). The reader
auto-detects the header row, so a friendly banner row above the column names
is fine.

- **Workbook template generator**: `data.makeTemplate("my_template.xlsx")`
  writes a five-sheet fill-in workbook — Joints/Elements/Settings input sheets
  (two-row header: friendly names above the MATLAB column names), a `Lists`
  sheet with the dropdown sources (bolt/material keys pulled live from the
  library), and a `Fields` sheet: the full data dictionary (MATLAB name,
  friendly name, description, units, default per column — the Excel
  Data-Validation tooltip text). See USER_GUIDE.md §4.
- **Input templates** (exact column headers/keys, first joint row = the DABJ
  §9 worked example, settings = the §9 temperatures + factors):
  `matlab/templates/joint_library_template.csv`, `elements_template.csv`,
  and `settings_template.csv` — copy, fill in, run.
- **Runnable reference**: `matlab/examples/run_bulk_example.m` runs the bundled
  templates end to end and writes `bulk_results.xlsx` next to itself.

## Two authoritative references

- **NASA-STD-5020B** (with the supplements it defers to) defines *what to
  compute* — the checks, the equations, and the rules they must obey.
- A **validation "answer key"** is the *source of truth for the numbers* — every
  margin is validated against a worked example with published answers, never
  against another implementation of the same standard (that would only prove the
  arithmetic was copied, errors included). Primary key: the **DABJ course book
  §9 public worked example**; checks it does not reach are pinned by documented
  hand derivations.

## Status

**Phases 1–3 complete; Phase 4 (GUI) substantially complete.** The tool runs
end to end: define a joint from library-backed dropdowns, analyze it, or map
FEM element IDs to joints, import forces one load case per sheet, run the
batch and export a formatted workbook.

Launch it with `cd matlab; fastenerTool`.

**What's left**, in the order it matters — see `MATLAB_BUILD_GUIDE.md`,
*"What remains"*, for the detail:

1. **Help menu, and delete `+gui`** (GUI step 10) — the last GUI step.
2. **UN vs UNJ thread form** — seeded stress areas may be ~8% conservative;
   see `VALIDATION.md`. Conservative, but it matters for sizing.
3. **Phase 5 packaging.**

Materials & Hardware (GUI step 9) landed 2026-08-17: all six library sections
browsable with their source citations visible, custom entries added or
duplicated from a baseline row, and persisted to a per-installation library
file. See `GUI2_SPEC.md` §16.

Separation-before-rupture on the threaded member — once listed here as the last
real engineering gap — is done: all three thread rows take their design load
from `engine.boltDesignLoad`, which applies the Fig. 8 gate through the shared
`separationBeforeRuptureGate` helper.

> **Phase 3.4 is dead, not deferred.** The planned second validation wave was
> to draw on non-public case data; that data is not going into this repository.
> Those checks are verified locally with only the outcome recorded (verified,
> agreement within X%, inputs not in repo). See `VALIDATION.md` and
> `TOOL_DIFFERENCES.md`.

`TOOL_DIFFERENCES.md` records every place this tool takes a deliberate position
where the standard leaves a choice open — what it does, and why.

### How it got here

The phase-by-phase build history used to be restated here in full. It is not
any more: `ARCHITECTURE.md` owns that narrative and is updated as each step
lands, and keeping a second copy in the front door meant two places to update
and one of them silently rotting — which is exactly what happened to the launch
command above. For the per-package detail see `ARCHITECTURE.md`; for the phase
sequence see `MATLAB_BUILD_GUIDE.md`; for the margin-by-margin review of the
engine against the standard see `MARGIN_REVIEW.md`.
