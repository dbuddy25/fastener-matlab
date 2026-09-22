# Architecture — MATLAB Fastener Analysis Tool

How the pieces fit together.

**What it is.** A NASA-STD-5020B bolted-joint margin tool. One call runs the
whole engine on one joint:

```matlab
r = engine.analyze(joint, loadCase, factors)   % -> engine.Result
```

preload (`engine.preload`, with the thermal change and the stiffness it
needs), design loads (`engine.designLoads`), and all fifteen margin checks —
tension ultimate with the Fig. 8 separation-before-rupture gate, tension yield,
shear, tension-shear interaction, separation, slip, bearing, shear tear-out,
bearing under head, bolt-thread shear, nut strength, insert pull-out and
internal thread, tapped-hole parent thread. Checks whose inputs are not
configured report `NotEvaluated`, never a fake number. `ENGINE_CHECKS.md` has
one row per check; `ENGINE_FLOW.md` is the same engine as diagrams.

**Validated** against the DABJ course book §9 public worked example — all six
published margins (+0.69 / +0.63 / +3.18 / +0.59 / +0.16 / −0.65, governed by
the deliberate slip failure) — and Example 8-b for stiffness. `VALIDATION.md`
records what each check is proven against.

**Three ways in.** Headless one-call bulk (`engine.runWorkbook` /
`engine.runBulk`: a workbook of joints and FE element forces in, a margins
workbook out), the Command Window on one joint, and the GUI (`fastenerTool`),
which is a thin shell over exactly the same calls.

---

## 1. The big picture

The tool takes a **description of a bolted joint**, runs it through the
**NASA-STD-5020B margin checks**, and **presents the result**. Three responsibilities,
kept in separate layers so each can be built and tested on its own:

```
   ┌──────────┐      ┌───────────┐      ┌──────────────┐
   │  +model  │ ───▶ │  +engine  │ ───▶ │+report/+gui │
   │  (nouns) │      │  (math)   │      │  (present)   │
   └──────────┘      └───────────┘      └──────────────┘
   describe a joint   compute margins    show the answer
```

**Golden rule:** the **engine never depends on the GUI**, and **everything is reachable
headless** — define joints in a table, analyze, export margins, all from the
Command Window. The GUI is a **thin shell over the headless API**: every control
calls an already-tested function, and no analysis logic lives in the GUI.

---

## 2. The data flow

The single flow everything is organized around:

```
  model.Joint + model.LoadCase + model.Factors  ──▶  engine.analyze(joint, loadCase, factors)
                                                                  │
                                              engine.Result  ──▶  report / gui
```

- **Input:** one `model.Joint` — a fully-described joint —
  plus a `model.LoadCase` (the applied loads) and `model.Factors` (safety + fitting
  factors), both passed to `analyze()` rather than stored on the Joint.
- **Engine:** resolves loads, computes preload/stiffness, runs all 15 margin checks,
  applies the interaction and separation logic — all 15 checks in the same
  `analyze()` call.
- **Output:** one `engine.Result` object — the 15 margins, each with pass/fail status
  (`Pass|Fail|NotEvaluated`), the governing equation/method, plus `WorstMargin`,
  `GoverningCheck`, the Fig 8 `Narrative`, and `asTable()`. Every consumer (report, GUI,
  bulk table) reads this *one* shape, so nothing re-derives numbers.
- **Bulk (front of the pipe):** FEM element forces → per-bolt loads:
  `engine.resolveForces(F, joint.BoltAxis)` → `engine.loadCaseFromForces(...)`
  → a `model.LoadCase` → `engine.analyze(joint, lc, factors)`. Each FEM
  element models one bolt (CBUSH); the resolution is a pure axis projection
  + RSS, no bolt-pattern moment distribution.
- **Bulk (table input):** `data.loadJointLibrary(file, lib)`
  turns a joint-table into `model.Joint` objects (library keys resolved via
  `data.Library`; header-row auto-detect, AxialX/Y/Z direction marks, boltSpec
  auto-lookup, On-gated washers), `data.loadSettings(file)` supplies the GLOBAL
  temperatures + `model.Factors`, and `data.loadElements(file)` turns an
  element + forces table into the per-element struct for
  `engine.resolveForces`. Template CSVs with the exact column headers ship at
  `matlab/templates/`; `data.makeTemplate(outFile)` generates the
  five-sheet fill-in workbook (Joints/Elements/Settings + `Lists` dropdown
  sources + the `Fields` data dictionary).
- **Bulk (orchestrator):** the same flow mapped over many elements
  → a results table: `engine.analyzeBulk(jointLibrary, elements, factors)` — one
  row per element (identity + resolved Axial/Shear + the 15 margin MS columns +
  WorstMargin/GoverningCheck + Error + Note; bad rows are marked, never abort
  the batch). Joint-mode slip aggregates the bolt pattern (`pattern_id`, or
  joint name when blank) into the Eq. 84 joint totals, gated by the nf check
  (pattern element count must equal `Joint.BoltCount`; mismatch → Slip NaN +
  Note). Pattern torsion not modeled (Eq. 84 scope).

### Headless usage

You don't build many joints by hand — you **describe them in a table and import them.**
For an engineer who lives in MATLAB/Excel — one workbook, one call end to end:

```matlab
f = data.makeTemplate("my_joints.xlsx");   % the fill-in workbook
% ... fill the Joints / Elements / Settings sheets in Excel ...
T = engine.runWorkbook("my_joints.xlsx", "margins.xlsx");   % single-workbook run
```

or, with the three inputs in separate files:

```matlab
T = engine.runBulk("my_joints.csv", "my_elements.csv", ...   % the whole pipeline
                   "my_settings.csv", "margins.xlsx");
```

which is exactly this flow, each piece independently usable:

```matlab
lib     = data.Library.load();   % hardware/material catalog
jl      = data.loadJointLibrary("my_joints.csv", lib);   % table → model.Joint per row
s       = data.loadSettings("my_settings.csv");   % global temps + factors
                                                        %          (runBulk applies the temps
                                                        %           to every jl(i).Joint)
el      = data.loadElements("my_elements.csv");   % element forces table
results = engine.analyzeBulk(jl, el, s.Factors);   % all 15 margins per element
report.exportResults(results, "margins.xlsx");   % answers out (+Summary sheet)
```

For the few-by-hand case, library lookups keep it terse:
`b = lib.bolt("#10-32 UNF"); m = lib.material("A286");`. The GUI wraps exactly
these calls.

---

## 3. Package map

```
matlab/
├── fastenerTool.m   entry point: version banner + gui.launch
├── +model/          domain types (the "nouns")
├── +engine/         the math: `preload`, `stiffness`, `designLoads`, the fifteen `margin*` checks,
│                    `analyze` + `Result`; bulk (`resolveForces`, `analyzeBulk`, `runBulk`, `runWorkbook`);
│                    `boltSizingSweep` (the sizing screen). Shared primitives in `+engine/private`.
├── +data/           library loader (`Library` + `library/` — one JSON per part, plus user drop-in files);
│                    bulk parsers (`loadJointLibrary`, `loadElements`, `loadSettings`, `templates/`);
│                    workbook template (`makeTemplate`); case save/load (`saveCase`/`loadCase` via
│                    `toStruct`/`fromStruct`); factor presets
├── +validation/     DABJ §9 answer-key case (`dabjSection9`) + Example 8-b stiffness case (`dabjExample8b`)
├── +report/         XLSX export (`exportResults`); single-joint PDF report (`singleJointReport`, via MATLAB Report Generator)
├── +gui/           THE GUI — programmatic uifigure app, `classdef < handle` on
│                    `uigridlayout`; rail + card shell over `AppState`; eleven pages
├── userguide/       Help → User Guide: static HTML + CSS, one file per rail page (USER_GUIDE_PRD.md)
├── examples/        runnable headless reference (`run_bulk_example.m`)
└── tests/           smoke + model tests; validation
```

Package classes reference each other with the `model.` / `engine.` prefix.

### 3.1 Dependency graph — what calls what

Generated from source (comments stripped, so documentation mentions do not count
as calls). File counts: `+model` 16 · `+engine` 39 · `+engine/private` 8 ·
`+data` 16 · `+report` 5 · `+gui` 24 · `+validation` 2.

**The single-joint chain.** `analyze` is the only orchestrator — it calls 18
things and nothing calls back into it:

```
analyze
  ├─ preload ──────────────► stiffness
  ├─ preloadWatchdog ──────► preload
  ├─ designLoads
  ├─ boltLengthCheck
  ├─ marginTensionUlt ───► stiffness, separationBeforeRuptureGate
  ├─ marginTensionYield ─► boltTensileAllowable
  ├─ marginShearUlt
  ├─ marginInteraction ──► marginShearUlt, boltTensileAllowable
  ├─ marginSeparation
  ├─ marginSlip
  ├─ marginBearing
  ├─ marginShearTearout
  ├─ marginBearingUnderHead ► stiffness
  ├─ marginBoltThreadShear ─► boltDesignLoad ──► stiffness
  ├─ marginNutStrength ─────► boltDesignLoad, memberTensileUltAllowable
  ├─ marginInsert ──────────► boltDesignLoad, memberTensileUltAllowable
  └─ marginTappedParentThread ► boltDesignLoad, memberTensileUltAllowable
```

**Above and below.** `runBulk` / `runWorkbook` → `analyzeBulk` → `analyze`, with
`resolveForces` → `loadCaseFromForces` turning FE output into a `LoadCase`, and
`data.*` loaders plus `report.exportResults` at the edges. The GUI calls the same
entry points; no analysis logic lives in `+gui`.

**Shared primitives** (`+engine/private`, called bare), each existing so its
callers cannot disagree:

| Helper | Called by |
|---|---|
| `boltTensileAllowable` | `marginTensionYield`, `marginInteraction`, `preloadWatchdog`, `systemTensileAllowable` |
| `memberTensileUltAllowable` | `marginInsert`, `marginNutStrength`, `marginTappedParentThread`, `systemTensileAllowable` |
| `separationBeforeRuptureGate` | `boltDesignLoad`, `marginTensionUlt` |

### 3.2 Where the deferrals bite — read this before parking work

Fan-in, highest first: **`stiffness` 6** · `preload` 4 · `boltDesignLoad` 4 ·
`analyze` 3 · `marginShearUlt` 3 · `resolveForces` 3 · `analyzeBulk` 3.

**`engine.stiffness` is the most depended-on function in the engine.** Insert
and tapped-hole joints use the same closed-form frustum fed a shortened grip
`L = t1 + D/2` (Shigley & Mischke; validated against DABJ Table 8-3), and a
mixed-modulus flange stack uses a thickness-weighted harmonic-mean member
modulus (NASA TM-106943 Eq. 34), exact
when material boundaries coincide with the frustum knee and bounded-but-
unconservative otherwise. See `TOOL_DIFFERENCES.md` §7.5.

**Fan-in overstates the blast radius.** A call edge shows who *asks* for
stiffness, not who *fails* without it. Most callers degrade rather than stop
when a joint's frustum geometry is incomplete:

| Caller | Without `stiffness` |
|---|---|
| `preload` | No thermal case needs it at all, and a `PreloadSpec.ThermalRate` override bypasses the stiffness form outright (`preload.m:36`) |
| `boltDesignLoad` | A threaded-in joint whose frustum geometry is incomplete falls back to **phi = 1** — a conservative bound, since `phi = kb/(kb+kc) <= 1` charges the full external load to the bolt. The four thread checks still run. A fully-defined insert or tapped-hole joint now gets its real phi instead. Nut joints are NOT given the fallback — they still report NotEvaluated |
| `marginTensionUlt` | Eq. 6 does not contain phi, so a joint whose Fig. 8 gate is assured needs no stiffness. Only the Eq. 10 rupture branch does |
| `marginBearingUnderHead` | Genuinely needs it |

So incomplete geometry costs **accuracy, not capability**: those joints analyse,
just pessimistically — 20–30% conservatism can push a sizing study up a
diameter. Before parking work on anything, check its fan-in here, then read the
callers' fallback paths: the graph is generated from call edges and cannot see a
`catch` that substitutes a conservative default.

Regenerate this section from source rather than editing it by hand — it drifts
otherwise, as the package map above did.

---

## 4. The domain model (`+model`)

The vocabulary the whole engine speaks. All are **value classes** with name-value
constructors, input validation, and unit comments (see `UNITS.md`). Physical
inputs that have no sensible default use **NaN** ("unconfigured") with
NaN-tolerant validators, so garbage fails loud instead of silently defaulting.

| Type | What it is | Notable fields |
|------|-----------|----------------|
| `Bolt` | Bolt geometry + threads (no material) | `NominalDiameter`, `ThreadsPerInch`, `TensileStressArea`, `MinorDiameter`, `PitchDiameter` (E, thread-shear area — ✅ 3.3), `BodyDiameter`, `HeadBearingDiameter` (washer-face dia d_wf, ✅ 3.1a), `ThreadLength` (threaded length from the tip; feeds the `BodyLengthInGrip` fallback); computed `Pitch`, `MinorArea`, `BodyArea` |
| `Material` | Strength + thermal props, any role | `Ftu`,`Fty`,`Fsu`,`Fbru`,`Fbry`,`E`,`CTE` |
| `ThreadedMember` | What the bolt threads into | `Type` (Nut/Insert/TappedHole), `Material`, `RatedUltimateLoad` (spec Pult / Heli-Coil rated pull-out), `EngagementLength` (Le, thread-shear area — ✅ 3.3), `BearingDiameter` (nut-side bearing dia for under-nut bearing; falls back to the nut washer OD), `HostName` (cosmetic) |
| `FlangeLayer` | One layer of the clamped stack | `Name` (cosmetic), `Material`, `Thickness`; `HoleDiameter` (dh, under-head bearing annulus), `EdgeDistance` (e, tear-out), `CheckShearTearout` (per-layer opt-in) — ✅ 3.2 |
| `Washer` | Washer under head or nut | `Thickness`, `OuterDiameter`; `Material` + `InnerDiameter` carried for completeness (engine treats washers as rigid and uses only thickness + OD) — rigid in the frustum: enters kc via the contact dia dc and kb via added clamped length |
| `Joint` | The whole joint, ties it together | `Bolt`, `BoltMaterial`, `FlangeStack`, `ThreadedMember`, `PreloadSpec`, `BoltCount`, `FrictionCoefficient`, `LoadingPlaneFactor`, bolt spec allowables, temps (order-validated), `ShearPlane`, `SlipMode` (single-fastener default / joint / ignored slip check), `HeadWasher`/`NutWasher` + `BodyLengthInGrip` (L1; NaN → `engine.stiffness` computes a simplified fallback from `Bolt.ThreadLength` + nut height + pitch) + `FrustumAngle` (stiffness inputs, ✅ 3.1a); computed `GripLength` |
| `PreloadSpec` | Full preload definition | **Replaced the scalar `Preload`** on `Joint`: `Method` (TorqueControl/DirectPreload), `NominalTorque` + fractional `TorqueTolerance` (5020B c-factor form, Eq. 3/4/5/24; `TorqueMin`/`TorqueMax`/`CMax`/`CMin` are derived Dependent props), nut factor K, `Uncertainty` Γ, relaxation/creep, `ThermalRate`, `SeparationCritical`, `NominalPreload` |
| `LoadCase` | Applied loads for one case | Per-bolt + joint-level limit loads (joint-level NaN → engine derives); **passed to `analyze()`, not stored on the Joint** |
| `Factors` | Safety + fitting factors | `FSU`,`FSY`,`FSSep`,`FFU`,`FFY`,`FFSep`,`FSSlip` (DABJ defaults); also passed to `analyze()`, not stored on the Joint |
| `ThreadSeries` | enum | `UNC`, `UNF` |
| `ThreadedMemberType` | enum | `Nut`, `Insert`, `TappedHole` |
| `ShearPlaneCondition` | enum | `ThreadsInShear`, `BodyInShear` |
| `PreloadMethod` | enum | `TorqueControl`, `DirectPreload` |
| `SlipMode` | enum | `SingleFastener` (default; 5020B Eq. 86), `Joint` (5020B Eq. 84, joint totals), `Ignored` (renamed from `Disabled`; CSV/XLSX parsing accepts both) |
| `BoltAxis` | enum | `X`, `Y`, `Z` — global axis the fastener acts axially along; `Joint.BoltAxis` (default `Z`) drives `engine.resolveForces` |

**Why one `Material` for every role:** a bolt material and a flange material are the
same *kind* of thing; flanges just also use the bearing fields (`Fbru`/`Fbry`) that
bolts ignore. Keeping them one type lets a shared alloy serve both roles; the
"which material goes where" distinction is a *library* concern (`+data`), not a
type.

---

## 5. Key design decisions (and why)

- **Headless-first, GUI as a thin shell** — the tool is fully usable from the
  Command Window; the GUI only wires controls to the already-tested headless
  API, and no logic lives in it.
- **One `Result` object** — every consumer reads the same computed output; no
  double-math between report and GUI. Unbuilt checks report `NotEvaluated` (a
  first-class status), so real results ship without fake numbers.
- **Units: English + °C** — inch/lbf/psi with temperature in °C and CTE in 1/°C. One
  contract, documented in `UNITS.md`; conversion only at the GUI boundary.
- **Validate against a known-good published answer key** — the numbers are validated
  against the **DABJ course book §9 public worked example**. A feature list is
  not an answer key:
  only a source that prints its own numbers can prove ours.
- **Domain rules baked in** — flanges = the clamped stack only (not the threaded
  interface); tapped-hole parent-thread shear is a distinct check.
- **The pitch-diameter thread-shear method** — thread stripping uses
  `As = 0.75·π·E·Le` (pitch diameter × engagement, 3/4·π coefficient on
  BOTH sides), not TM-106943's printed 5/8 external form and not DABJ §6's H28
  tolerance form with judgment knockdown. Insert pull-out is a computed shear
  area on the parent (`TOOL_DIFFERENCES.md` §1.5), falling back to a rated load
  only when no area resolves.
- **`engine.systemTensileAllowable` stays public, not `+engine/private/`** — it
  is the shared §4.4.1 fastening-system minimum, but ~14 tests call it
  directly (`tests/tSystemAllowable.m` and others), and privatizing it would
  buy nothing: every consumer (`engine.marginTensionUlt`,
  `engine.boltSizingSweep`'s threaded-member-context path) already
  lives inside `+engine/`, so the private/public boundary protects nothing
  a caller outside the package could misuse.

---

## 6. Testing & validation

`runTests` from the `matlab/` folder runs the suite; `runTests("engine")` skips
the GUI tests (seconds, not minutes) and `runTests("<PageName>")` runs one page.
Tests add the source folder to the path via a `PathFixture`, so they pass
regardless of the current folder.

- **The answer key.** `validation.dabjSection9()` encodes the DABJ §9 worked
  example — the full Joint/LoadCase/Factors, every published intermediate, and
  the six published margins with tolerances. `tests/tDabjCase.m` replays it
  through the engine and asserts a numeric match; several other files pin the
  same six numbers as a regression guard (`dabjSection9RegressionUnchanged`).
  This is the guardrail against silent drift in a safety-critical tool.
- **Hand-derived pins.** Every check with no book example carries its
  arithmetic inline in the test that pins it (`tests/tThreadShear.m`,
  `tBearing.m`, `tStiffness.m`, `tSystemAllowable.m`, …).
- **GUI tests** (`tests/tGui*.m`) build a real app per test method and drive
  real widgets with `matlab.uitest` gestures.
