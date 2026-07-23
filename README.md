# Fastener Analysis Tool (MATLAB)

Ground-up MATLAB build of a NASA-STD-5020B bolted-joint margin-of-safety
analysis tool, deployable as a standalone Windows executable.

## Docs (read these first)

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
├── +data/             library loader (`data.Library` + `library.json`, Phase 2.2); bulk parsers (`loadJointLibrary`/`loadElements` + `templates/`, Phase 3.5b); case save/load later (Phase 3)
├── +report/           PDF + XLSX export (Phase 3)
├── +gui/              App Designer app — thin shell over the engine (Phase 4)
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

## Two authoritative references

- The **existing Python tool** defines *what to build* (features/workflow).
- A **validation "answer key"** is the *source of truth for the numbers* — every
  margin is validated against it, not against the Python tool. Primary key: the
  **DABJ course book §9 public worked example**; the group's spreadsheet supplies
  a later second wave of cases (Phase 3.4).

## Status

**Phase 3.5b (bulk parsers: joint library + elements) complete; next 3.5c
(analyzeBulk).**
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
`data.loadJointLibrary(file, lib)` reads a joint-definition table (.csv or
.xlsx, one row per joint, library keys resolved through `data.Library`)
into `model.Joint` objects, and `data.loadElements(file)` reads an
element + forces table (`element_id`/`joint_name`/FX..MZ per row) into the
struct consumed by `engine.resolveForces`. Template files with the exact
column headers live at `+data/templates/` — the joint template's first row
is the DABJ §9 class-problem joint expressed in the table schema
(`tests/tBulkParsers.m` parses both templates and checks that row against
the same numbers `validation.dabjSection9` builds in code).
See `MATLAB_BUILD_GUIDE.md`.
