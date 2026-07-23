# Fastener Analysis Tool (MATLAB)

Ground-up MATLAB build of a NASA-STD-5020B bolted-joint margin-of-safety
analysis tool, deployable as a standalone Windows executable.

## Docs (read these first)

- **`USER_GUIDE.md`** — ⭐ **start here to actually use the tool** — a from-scratch
  walkthrough: setup, single-joint analysis, and the bulk spreadsheet workflow.
- **`MATLAB_BUILD_GUIDE.md`** — the build sequence: five phases (1–5), each a
  chain of small steps with a "Done when" acceptance test.
- **`MATLAB_TOOL_PRD.md`** — the requirements spec (what to build + the rules).
- **`MATLAB_TOOL_DECK_OUTLINE.md`** — plain-English outline for a share-out deck.
- **`ARCHITECTURE.md`** — how the pieces fit together (layers, data flow, design
  decisions); a living doc, updated as each phase step lands.
- **`UNITS.md`** — the unit contract: English units (in, lbf, psi) with
  temperature in °C and CTE in 1/°C. Single source of truth for units.
- **`VALIDATION.md`** — the validation coverage matrix: every check/scenario, its
  answer-key source, and whether it's validated ✅ / hand-derived ✍️ / pending ⏳.
  A living doc — every new check adds a row.

## Source layout

```
matlab/
├── fastenerTool.m     entry point (Phase 1 stub — prints version)
├── +model/            domain types: Bolt, Material, Joint, enums (Phase 1)
├── +engine/           analysis math — the core (Phases 2–3)
├── +data/             library loader (`data.Library` + `library.json`, Phase 2.2); bulk parsers (`loadJointLibrary`/`loadElements` + `templates/`, Phase 3.5b); global settings (`loadSettings` — temps + factors); case save/load later (Phase 3)
├── +report/           XLSX export (`report.exportResults`, Phase 3.6); PDF later (Phase 3.8)
├── +gui/              App Designer app — thin shell over the engine (Phase 4)
├── examples/          runnable reference scripts (`run_bulk_example.m`)
└── tests/             validation + smoke tests (checked vs the worked example)
```

## Run it (machine with MATLAB)

Open MATLAB, point the Current Folder at `matlab/`, then in the Command Window:

```matlab
fastenerTool                 % prints the version banner
runtests("tests")            % runs the smoke + model tests (should be all green)

% construct a joint (Phase 1 acceptance):
b = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
               Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
               TensileStressArea=0.0200);
b.Pitch                      % -> 0.03125
```

> **Note:** developed on macOS (no MATLAB there), so acceptance is verified on the
> Windows/MATLAB work machine — `git pull` (or re-download), then run the above.

## Headless bulk analysis (the Headless Release workflow)

Describe your joints and element forces in two tables, put the global analysis
settings (temperatures + factors) in a third, then get every margin in one
call — no GUI involved:

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

- **Input templates** (exact column headers/keys, first joint row = the DABJ
  §9 worked example, settings = the §9 temperatures + factors):
  `matlab/templates/joint_library_template.csv`, `elements_template.csv`,
  and `settings_template.csv` — copy, fill in, run.
- **Runnable reference**: `matlab/examples/run_bulk_example.m` runs the bundled
  templates end to end and writes `bulk_results.xlsx` next to itself.

## Two authoritative references

- The **existing Python tool** defines *what to build* (features/workflow).
- A **validation "answer key"** is the *source of truth for the numbers* — every
  margin is validated against it, not against the Python tool. Primary key: the
  **DABJ course book §9 public worked example**; the group's spreadsheet supplies
  a later second wave of cases (Phase 3.4).

## Status

**Phase 3 Headless Release complete** — full 15-check engine + bulk table
workflow (parse → resolve → analyze → XLSX), including joint-slip
bolt-pattern aggregation with the nf check (3.5d). Next: 3.7 (case
save/load, presets), 3.8 (PDF), then Phase 4 (GUI).
The `+model` package defines `Bolt`, `Material`, `ThreadedMember`, `FlangeLayer`,
`Joint`, `PreloadSpec`, `LoadCase`, `Factors`, and the enums (`ThreadSeries`,
`ThreadedMemberType`, `ShearPlaneCondition`, `PreloadMethod`); a full joint
constructs in the Command Window (see `+model/Joint.m`, exercised by
`tests/tModel.m`). The `+data` package holds the hardware/material library:
`data.Library.load()` serves the DABJ case's bolt + materials by key
(`lib.bolt("3/8-24 UNF")`, `lib.material("A-286")`, exercised by
`tests/tLibrary.m`). The `+validation` package encodes the answer key:
`validation.dabjSection9()` builds the DABJ §9 joint/loads/factors from the
library and pins every published intermediate and margin (exercised by
`tests/tDabjCase.m`). The `+engine` package computes the preloads, design
loads, and six DABJ-validated margin checks, and
`engine.analyze(joint, loadCase, factors)` runs them all in one call,
returning the standard `engine.Result` — the 15-check margin table
(`Pass|Fail|NotEvaluated`), `WorstMargin`/`GoverningCheck`, the Fig. 8
narrative, and `asTable()` for export (one `analyze()` call reproduces all
six DABJ §9 margins in `tests/tDabjCase.m`). `engine.stiffness(joint)`
computes bolt/member stiffness and the stiffness factor phi (Shigley 30°
conical frustum; phi per NASA-STD-5020B Eq. 9), validated against DABJ
Example 8-b via `validation.dabjExample8b()` (exercised by
`tests/tStiffness.m`), and is wired in (3.1b): `engine.preload` computes
the thermal preload change from the joint stiffness (NASA TM-106943
Eq. 10) when no `ThermalRate` override is supplied, and
`engine.marginTensionUlt` computes the real rupture-branch margin
(NASA-STD-5020B Eq. 10 via phi) when the Fig. 8 gate is not assured
(the yield-side rupture form, 5020B Eq. 11, is deferred). Phase 3.2 adds
the three member-strength checks required by NASA-STD-5020B §4.4.2, with
the working equations from NASA TM-106943 (Chambers): bolt bearing on
the flanges (`engine.marginBearing`, Eq. 72-74, allowable validated
against DABJ Example 5-b: Pbr = 14,760 lbf), flange shear tear-out
(`engine.marginShearTearout`, Eq. 69-71, hand-derived pin; e/D < 1.5
flagged as outside validity), and bearing under the head/nut
(`engine.marginBearingUnderHead`, Eq. 75 annulus + Eq. 74 MS form on the
bolt axial load Pb = PpMax + n·phi·PtL per 5020B Eq. 8, hand-derived pin
on the Example 8-b geometry) — all wired into `analyze()`
(`tests/tBearing.m`), with new `FlangeLayer` fields `HoleDiameter`,
`EdgeDistance`, and `CheckShearTearout`. Phase 3.3 completes the 15-check
set with the four thread-strength checks, using the GROUP'S method: thread
shear area `As = 0.75·π·E·Le` (E = pitch diameter, `Bolt.PitchDiameter`;
Le = engagement, `ThreadedMember.EngagementLength`) with `Pult = Fsu·As`
and `MS = Pult/Pb − 1` (NASA TM-106943 Eq. 63-65/76-77/79 basis; Pb per
NASA-STD-5020B Eq. 8) — `engine.marginBoltThreadShear` (bolt Fsu),
`engine.marginNutStrength` (nut Fsu), and
`engine.marginTappedParentThread` (parent Fsu — closes the long-standing
tapped-hole gap; area/allowable cross-checked vs DABJ Example 6-a within
1.5%) — while inserts use the manufacturer (Heli-Coil) rated pull-out load
directly (`engine.marginInsert`), one spec value on the insert
internal-thread row (`tests/tThreadShear.m`). Phase 3.5a adds FEM force
resolution: `engine.resolveForces(F, axis)` projects one element's 6-DOF
force vector onto the bolt axis (`model.BoltAxis`, new `Joint.BoltAxis`
field, default Z) — axial = signed force along the axis, shear = RSS of
the two transverse forces (single-fastener CBUSH projection; no
bolt-pattern moment distribution) — and
`engine.loadCaseFromForces(F, axis, ...)` turns that into a per-bolt
`model.LoadCase` (`Reversible`/`ScaleFactor` options; hand-derived 3-4-5
pins in `tests/tForces.m`). Phase 3.5b adds the bulk input parsers:
`data.loadJointLibrary(file, lib)` reads a joint-table (.csv or .xlsx, one
row per joint, library keys resolved through `data.Library`; header-row
auto-detect, `AxialX/Y/Z` bolt-direction marks, boltSpec auto-lookup for
the rated loads, On-gated washers, `Nut*`/`Helicoil*` threaded-member
columns; no temperature columns — temps are global settings) into
`model.Joint` objects, `data.loadElements(file)` reads an element + forces
table (`element_id`/`joint_name`/FX..MZ per row) into the struct consumed
by `engine.resolveForces`, and `data.loadSettings(file)` reads the global
settings key/value file (NominalTempC/HotTempC/ColdTempC + the eight
factor keys → a `model.Factors`). Template files with the exact column
headers live at `matlab/templates/` — the joint template's first row
is the DABJ §9 class-problem joint expressed in the table schema
(`tests/tBulkParsers.m` parses the templates and checks that row against
the same numbers `validation.dabjSection9` builds in code; the row carries
a `ThermalRate` override, 12.978 lbf/°C, so its thermal preload matches the
in-code build without stiffness geometry). Phase 3.5c ties it together:
`engine.analyzeBulk(jointLibrary, elements, factors)` maps the pipeline
(`loadCaseFromForces` → `analyze`) over every element and returns a
writetable-ready results table — one row per element with the resolved
per-bolt Axial/Shear, all 15 margin MS columns, WorstMargin/GoverningCheck,
and an Error column (a missing joint or a failed analyze marks the row,
never aborts the batch). The end-to-end run reproduces the DABJ §9
per-bolt margins from the template CSV (`tests/tBulk.m`). Phase 3.5d adds
joint-slip bolt-pattern aggregation: for a `SlipMode.Joint` joint the
orchestrator groups the element's pattern (optional `pattern_id` elements
column — the physical joint instance — falling back to the joint name),
vector-sums the scaled forces into the NASA-STD-5020B Eq. 84 joint totals,
and evaluates joint slip ONLY when the pattern's element count equals
`Joint.BoltCount` (the nf check — a mismatch leaves Slip NaN with a `Note`
column saying why, never a silently wrong margin). A four-element pattern
splitting the §9 joint totals reproduces the book's joint-slip −0.65
end-to-end; pattern torsion is not modeled (same scope as Eq. 84).
Single-fastener slip — the default — evaluates normally per element.
Phase 3.6 completes the Headless Release: `report.exportResults(T, file)`
writes the results table to `.xlsx` (Results sheet + a Summary sheet with
Pass/Fail/Error counts) or `.csv` by extension, and
`engine.runBulk(jointFile, elementsFile, settingsFile, outFile)` runs the
whole pipeline — library load → parse → apply global settings temps to
every joint → resolve → analyze → export — in one call (settings optional:
empty/omitted → `model.Factors()` defaults with the joints' own
temperatures, and a `model.Factors` object in the slot is accepted for
back-compat; a runnable reference lives at
`matlab/examples/run_bulk_example.m`; exercised by `tests/tExport.m`).
See `MATLAB_BUILD_GUIDE.md`.
