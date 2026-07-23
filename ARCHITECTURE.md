# Architecture — MATLAB Fastener Analysis Tool

How the pieces fit together. **This is a living document** — it describes what is
built today and where it is headed. Each section is tagged:

- ✅ **Built** — exists and tested now
- ⏳ **Planned** — designed, not yet implemented (phase noted)

**Current state: through Phase 3.6 — the HEADLESS RELEASE is complete.
Validated single-joint engine + joint stiffness + the member-strength checks +
the thread-strength checks (ALL 15 checks implemented) + FEM force resolution +
bulk input parsers + the bulk orchestrator + XLSX export + the one-call
`engine.runBulk` workflow.** `engine.analyze(joint, loadCase, factors)` runs the whole engine
in one call — preload (`engine.preload`), design loads (`engine.designLoads`),
and every margin check (`marginTensionUlt` with the Fig. 8 gate,
`marginBoltYield`, `marginShearUlt`, `marginInteraction`, `marginSeparation`,
`marginSlip`, `marginBearing`, `marginShearTearout`, `marginBearingUnderHead`,
`marginBoltThreadShear`, `marginNutStrength`, `marginInsert`,
`marginTappedParentThread`) — and returns the standard `engine.Result`. One call reproduces
all six DABJ §9 margins (+0.69 / +0.63 / +3.18 / +0.59 / +0.16 / −0.65,
governed by the deliberate slip failure); checks whose inputs are not
configured report `NotEvaluated`. ✅ Phase 3.1a adds `engine.stiffness(joint)` — bolt/member
stiffness (Shigley 30° conical frustum; through-bolt/nut only) and the
stiffness factor phi (NASA-STD-5020B Eq. 9), validated against DABJ Example
8-b (Kb 2.39e6 / Kc 4.73e6 / Phi 0.336, `validation.dabjExample8b` +
`tests/tStiffness.m`), with new model fields to support it (`model.Washer`,
`Bolt.HeadBearingDiameter`, `Joint.HeadWasher`/`NutWasher`/
`BodyLengthInGrip`/`FrustumAngle`). ✅ Phase 3.1b wires it in:
`engine.preload` computes the thermal preload change from the joint
stiffness (NASA TM-106943 Eq. 10, thickness-weighted member CTE) when no
`ThermalRate` override is set (the DABJ §9 case keeps its override, so the
answer key is untouched), and `engine.marginTensionUlt` computes the real
rupture-branch margin (NASA-STD-5020B Eq. 10 via phi and n) when the
Fig. 8 gate is not assured — falling back to `NotEvaluated` only if the
stiffness geometry is missing. The yield-side rupture form (5020B Eq. 11)
is deferred (see the TODO in `engine.marginBoltYield`). ✅ Phase 3.2 adds
the three member checks NASA-STD-5020B §4.4.2 requires (5020B prints no
member equations; the math is NASA TM-106943): `engine.marginBearing`
(Eq. 72-74, worst flange layer over ultimate/yield; allowable validated
vs DABJ Ex 5-b, 14,760 lbf), `engine.marginShearTearout` (Eq. 69-71,
per-layer opt-in via `FlangeLayer.EdgeDistance`/`CheckShearTearout`;
e/D < 1.5 flagged as outside validity; hand-derived pin), and
`engine.marginBearingUnderHead` (Eq. 75 annulus vs the bolt axial load
Pb = PpMax + n·phi·PtL, 5020B Eq. 8; hand-derived pin on the Ex 8-b
geometry; NotEvaluated when the stiffness geometry is missing). New
`FlangeLayer` fields: `HoleDiameter`, `EdgeDistance`, `CheckShearTearout`
(`tests/tBearing.m`). ✅ Phase 3.3 completes the check set with the four
thread-strength checks, using the GROUP'S method — thread-shear area
`As = 0.75·π·E·Le` (E = thread pitch diameter, new `Bolt.PitchDiameter`;
Le = engagement length, new `ThreadedMember.EngagementLength`), then
`Pult = Fsu·As` and `MS = Pult/Pb − 1` (NASA TM-106943 Eq. 63-65 /
76-77 / 79 basis — the group substitutes the 0.75·π pitch-diameter area
on both sides; 5020B prints no thread-shear equations) against the design
bolt load `Pb = PpMax + FFU·FSU·n·φ·PtL` (5020B Eq. 8 form,
`engine.boltDesignLoad`; φ = 1 assumed for threaded-in configs where the
stiffness frustum is deferred — conservative). Both sides of the
thread-stripping pair are checked — `engine.marginBoltThreadShear` (bolt
Fsu) vs `engine.marginNutStrength` (nut Fsu) or
`engine.marginTappedParentThread` (parent Fsu) — and the weaker governs
via the WorstMargin pick. The tapped-parent check closes the
long-standing tapped-hole gap; its area/allowable are cross-checked
against DABJ Example 6-a (0.0999 vs 0.0986 in², 2,698 vs 2,660 lb —
within 1.5%; DABJ's 0.70 judgment knockdown is deliberately NOT applied).
Inserts use the MANUFACTURER (Heli-Coil) rated pull-out load — one spec
value on `ThreadedMember.RatedUltimateLoad` (`engine.marginInsert`,
carried on the insert internal-thread row; the external-thread row stays
NotEvaluated by design) — not a thread-shear calc (`tests/tThreadShear.m`).
✅ Phase 3.5a adds FEM force resolution — `engine.resolveForces(F, axis)`
projects one element's 6-DOF force vector onto the bolt axis (new
`model.BoltAxis` enum + `Joint.BoltAxis` field, default Z): axial = signed
force along the axis, shear = RSS of the two transverse forces, bending =
RSS of the transverse moments (informational; torsion ignored). This is a
single-fastener (CBUSH) geometric projection — no bolt-pattern moment
distribution, no 5020B equation. `engine.loadCaseFromForces(F, axis, ...)`
wraps it into a per-bolt `model.LoadCase` (PtL = |axial| if `Reversible`,
else max(axial, 0) — compression doesn't load the bolt in tension; PsL =
shear; `ScaleFactor` applied before resolution; joint-level loads stay NaN
— multi-bolt totals come from the mapping table in 3.5b). Hand-derived
3-4-5 pins in `tests/tForces.m`.
✅ Phase 3.5b adds the bulk input parsers — `data.loadJointLibrary(file, lib)`
reads a joint-definition table (.csv/.xlsx, one row per joint;
case-insensitive columns, blanks keep model defaults; Bolt / BoltMaterial /
BoltSpec / HostMaterial / Flange{k}Material cells are LIBRARY KEYS resolved
through `data.Library`; ThreadEngagement accepts inches or a "1.5D"
diameter-multiple) into `{Name, model.Joint}` structs, and
`data.loadElements(file)` reads an element + forces table
(`element_id`, `joint_name`, `load_case`, FX..MZ, `scale`, `reversible`)
into the struct `engine.resolveForces` consumes. Template CSVs with the
exact headers ship at `+data/templates/`; the joint template's first row is
the DABJ §9 class-problem joint expressed in the schema, checked against
the `validation.dabjSection9` in-code build by `tests/tBulkParsers.m`
(including a `ThermalRate` column → `PreloadSpec.ThermalRate` override so
the template's thermal preload needs no stiffness geometry).
✅ Phase 3.5c adds the bulk orchestrator — `engine.analyzeBulk(jointLibrary,
elements, factors)` maps `loadCaseFromForces` → `analyze` over every
element and returns a writetable-ready results table, one row per element:
ElementId/JointName/LoadCase, the resolved per-bolt Axial/Shear, the 15
margin MS columns, WorstMargin/GoverningCheck, and an Error column (a
missing joint or a failed analyze marks that row with the message and NaN
margins — the batch never aborts). The headless data flow is now fully
wired: `loadJointLibrary` + `loadElements` → `analyzeBulk` → table.
End-to-end the pipeline reproduces the DABJ §9 per-bolt margins from the
template CSV (`tests/tBulk.m`). Limitation: bulk is single-fastener by
nature (each FEM element = one bolt, per-bolt loads only), so a
`SlipMode.Joint` joint's slip check is NotEvaluated in bulk — joint-level
totals need bolt-pattern aggregation (future work).
✅ Phase 3.6 completes the Headless Release — the `+report` area now exists:
`report.exportResults(T, file)` writes the analyzeBulk results table to
`.xlsx` (a Results sheet + a Summary sheet with total/Pass/Fail/Error
counts) or `.csv` by extension, returning the resolved path (thin by
design — the table is already export-ready; PDF comes later, Phase 3.8).
`engine.runBulk(jointLibFile, elementsFile, factors, outFile)` is the
one-call headless workflow — library load → `loadJointLibrary` +
`loadElements` → `analyzeBulk` → optional `exportResults` — with factors
defaulting to `model.Factors()`. A runnable reference script lives at
`matlab/examples/run_bulk_example.m` (runs the bundled templates, writes
`bulk_results.xlsx` next to itself). The headless data flow is now fully
realized end to end: files in → margins out (`tests/tExport.m`).

---

## 1. The big picture

The tool takes a **description of a bolted joint**, runs it through the
**NASA-STD-5020B margin checks**, and **presents the result**. Three responsibilities,
kept in separate layers so each can be built and tested on its own:

```
   ┌──────────┐      ┌───────────┐      ┌──────────────┐
   │  +model  │ ───▶ │  +engine  │ ───▶ │ +report/+gui │
   │  (nouns) │      │  (math)   │      │  (present)   │
   └──────────┘      └───────────┘      └──────────────┘
   describe a joint   compute margins    show the answer
      ✅ Phase 1         ⏳ Phases 2–3       ⏳ Phases 3–4
```

**Golden rule:** the **engine never depends on the GUI**, and **everything is reachable
headless.** The primary target is a **Headless Release** (Phase 3) — a fully usable tool
driven from the Command Window (define joints in a table → analyze → export margins)
*before* the GUI exists. The **GUI is a committed deliverable** (Phase 4), but it is a
**thin shell over the headless API**: every control calls an already-tested function,
and no analysis logic lives in the GUI. Headless-first is a down payment on the GUI,
not a detour from it.

---

## 2. The data flow (target)

The single flow everything is organized around:

```
  model.Joint + model.LoadCase + model.Factors  ──▶  engine.analyze(joint, loadCase, factors)
        (✅ Phase 2.1)                                       (✅ 2.9 solver)
                                                                  │
                                              engine.Result  ──▶  report / gui
                                            (✅ 2.9 result object) (⏳ Phases 3–4)
```

- **Input:** one `model.Joint` — a fully-described joint (✅ you can build this today) —
  plus a `model.LoadCase` (the applied loads) and `model.Factors` (safety + fitting
  factors), both passed to `analyze()` rather than stored on the Joint (✅ Phase 2.1).
- **Engine:** resolves loads, computes preload/stiffness, runs all 15 margin checks,
  applies the interaction and separation logic. (✅ core built and DABJ-validated
  through Phase 2.9; stiffness landed in 3.1, the member checks in 3.2, and the
  thread checks in 3.3 — all 15 checks now run in the same `analyze()` call.)
- **Output:** one `engine.Result` object — the 15 margins, each with pass/fail status
  (`Pass|Fail|NotEvaluated`), the governing equation/method, plus `WorstMargin`,
  `GoverningCheck`, the Fig 8 `Narrative`, and `asTable()`. Every consumer (report, GUI,
  bulk table) reads this *one* shape, so nothing re-derives numbers. (✅ Phase 2.9.)
- **Bulk (front of the pipe — ✅ 3.5a):** FEM element forces → per-bolt loads:
  `engine.resolveForces(F, joint.BoltAxis)` → `engine.loadCaseFromForces(...)`
  → a `model.LoadCase` → `engine.analyze(joint, lc, factors)`. Each FEM
  element models one bolt (CBUSH); the resolution is a pure axis projection
  + RSS, no bolt-pattern moment distribution.
- **Bulk (table input — ✅ 3.5b):** `data.loadJointLibrary(file, lib)` turns a
  joint-definition table into `model.Joint` objects (library keys resolved via
  `data.Library`), and `data.loadElements(file)` turns an element + forces table
  into the per-element struct for `engine.resolveForces`. Template CSVs with the
  exact column headers ship at `+data/templates/`.
- **Bulk (orchestrator — ✅ 3.5c):** the same flow mapped over many elements → a
  results table: `engine.analyzeBulk(jointLibrary, elements, factors)` — one row
  per element (identity + resolved Axial/Shear + the 15 margin MS columns +
  WorstMargin/GoverningCheck + Error; bad rows are marked, never abort the
  batch). Joint-mode slip is NotEvaluated in bulk (per-bolt loads only; joint
  totals need pattern aggregation — future).

### Headless usage — the primary path (✅ Headless Release, Phase 3.6)

You don't build many joints by hand — you **describe them in a table and import them.**
This is the whole product for an engineer who lives in MATLAB/Excel, no GUI required —
one call end to end:

```matlab
T = engine.runBulk("my_joints.csv", "my_elements.csv", ...   % ✅ 3.6 — the whole pipeline
                   model.Factors(), "margins.xlsx");
```

which is exactly this flow, each piece independently usable:

```matlab
lib     = data.Library.load();                          % ✅ 2.2  — hardware/material catalog
jl      = data.loadJointLibrary("my_joints.csv", lib);  % ✅ 3.5b — table → model.Joint per row
el      = data.loadElements("my_elements.csv");         % ✅ 3.5b — element forces table
results = engine.analyzeBulk(jl, el, factors);          % ✅ 3.5c — all 15 margins per element
report.exportResults(results, "margins.xlsx");          % ✅ 3.6  — answers out (+Summary sheet)
```

For the few-by-hand case, library lookups keep it terse:
`b = lib.bolt("#10-32 UNF"); m = lib.material("A286");`. Precedent: the Python tool
already works this way (`joint_library.csv`, `mapping_template.csv`). The **Headless
Release** = the validated engine (Phase 2) + table input, bulk analysis, and XLSX
export (Phase 3). The GUI wraps exactly these calls later.

---

## 3. Package map

```
matlab/
├── fastenerTool.m   ✅ entry-point stub (prints version)   — Phase 1
├── +model/          ✅ domain types (the "nouns")           — Phase 1 (+2.1 additions)
├── +engine/         ✅ `preload` (2.4), `designLoads` + `marginTensionUlt` (2.5), `marginSeparation` + `marginBoltYield` (2.6), `marginShearUlt` + `marginInteraction` (2.7), `marginSlip` (2.8), `analyze` + `Result` (2.9), `stiffness` (3.1a) + wiring into thermal preload & tension rupture (3.1b), `marginBearing` + `marginShearTearout` + `marginBearingUnderHead` (3.2), `marginBoltThreadShear` + `marginNutStrength` + `marginInsert` + `marginTappedParentThread` + `boltDesignLoad` (3.3) — all 15 checks; `resolveForces` + `loadCaseFromForces` (3.5a); `analyzeBulk` (3.5c) — the bulk orchestrator; `runBulk` (3.6) — the one-call headless workflow
├── +data/           ✅ library loader (`Library` + `library.json`, 2.2); bulk parsers (`loadJointLibrary` + `loadElements` + `templates/`, 3.5b); ⏳ case save/load — Phase 3
├── +validation/     ✅ DABJ §9 answer-key case (`dabjSection9`, 2.3) + Example 8-b stiffness case (`dabjExample8b`, 3.1a)
├── +report/         ✅ XLSX export (`exportResults`, 3.6); ⏳ PDF — Phase 3.8
├── +gui/            ⏳ App Designer app (thin shell)        — Phase 4
├── examples/        ✅ runnable headless reference (`run_bulk_example.m`, 3.6)
└── tests/           ✅ smoke + model tests; ⏳ validation   — throughout
```

Package classes reference each other with the `model.` / `engine.` prefix.

---

## 4. The domain model (`+model`) — ✅ built (Phases 1 + 2.1)

The vocabulary the whole engine speaks. All are **value classes** with name-value
constructors, input validation, and unit comments (see `UNITS.md`). Physical
inputs that have no sensible default use **NaN** ("unconfigured") with
NaN-tolerant validators, so garbage fails loud instead of silently defaulting.

| Type | What it is | Notable fields |
|------|-----------|----------------|
| `Bolt` | Bolt geometry + threads (no material) | `NominalDiameter`, `ThreadsPerInch`, `TensileStressArea`, `MinorDiameter`, `PitchDiameter` (E, thread-shear area — ✅ 3.3), `BodyDiameter`, `HeadBearingDiameter` (washer-face dia d_wf, ✅ 3.1a); computed `Pitch`, `MinorArea`, `BodyArea` |
| `Material` | Strength + thermal props, any role | `Ftu`,`Fty`,`Fsu`,`Fbru`,`Fbry`,`E`,`CTE` |
| `ThreadedMember` | What the bolt threads into | `Type` (Nut/Insert/TappedHole), `Material`, `RatedUltimateLoad` (spec Pult / Heli-Coil rated pull-out), `EngagementLength` (Le, thread-shear area — ✅ 3.3) |
| `FlangeLayer` | One layer of the clamped stack | `Material`, `Thickness`; `HoleDiameter` (dh, under-head bearing annulus), `EdgeDistance` (e, tear-out), `CheckShearTearout` (per-layer opt-in) — ✅ 3.2 |
| `Washer` | Washer under head or nut (✅ 3.1a) | `Thickness`, `OuterDiameter`; rigid in the frustum — enters kc via the contact dia dc and kb via added clamped length |
| `Joint` | The whole joint, ties it together | `Bolt`, `BoltMaterial`, `FlangeStack`, `ThreadedMember`, `PreloadSpec`, `BoltCount`, `FrictionCoefficient`, `LoadingPlaneFactor`, bolt spec allowables, temps (order-validated), `ShearPlane`, `SlipMode` (single-fastener default / joint / disabled slip check), `HeadWasher`/`NutWasher` + `BodyLengthInGrip` (L1) + `FrustumAngle` (stiffness inputs, ✅ 3.1a); computed `GripLength` |
| `PreloadSpec` | Full preload definition (✅ Phase 2.1) | **Replaced the scalar `Preload`** on `Joint`: `Method` (TorqueControl/DirectPreload), `NominalTorque` + fractional `TorqueTolerance` (5020B c-factor form, Eq. 3/4/5/24; `TorqueMin`/`TorqueMax`/`CMax`/`CMin` are derived Dependent props), nut factor K, `Uncertainty` Γ, relaxation/creep, `ThermalRate`, `SeparationCritical`, `NominalPreload` |
| `LoadCase` | Applied loads for one case (✅ Phase 2.1) | Per-bolt + joint-level limit loads (joint-level NaN → engine derives); **passed to `analyze()`, not stored on the Joint** |
| `Factors` | Safety + fitting factors (✅ Phase 2.1) | `FSU`,`FSY`,`FSSep`,`FFU`,`FFY`,`FFSep`,`FSSlip` (DABJ defaults); also passed to `analyze()`, not stored on the Joint |
| `ThreadSeries` | enum | `UNC`, `UNF` |
| `ThreadedMemberType` | enum | `Nut`, `Insert`, `TappedHole` |
| `ShearPlaneCondition` | enum | `ThreadsInShear`, `BodyInShear` |
| `PreloadMethod` | enum (✅ Phase 2.1) | `TorqueControl`, `DirectPreload` |
| `SlipMode` | enum | `SingleFastener` (default; 5020B Eq. 86), `Joint` (5020B Eq. 84, joint totals), `Disabled` |
| `BoltAxis` | enum (✅ 3.5a) | `X`, `Y`, `Z` — global axis the fastener acts axially along; `Joint.BoltAxis` (default `Z`) drives `engine.resolveForces` |

**Why one `Material` for every role:** a bolt material and a flange material are the
same *kind* of thing; flanges just also use the bearing fields (`Fbru`/`Fbry`) that
bolts ignore. Keeping them one type lets a shared alloy serve both roles; the
"which material goes where" distinction is a *library* concern (the `+data` area,
Phase 2.2), not a type.

---

## 5. Key design decisions (and why)

- **Headless-first, GUI as a thin shell** — the tool is made fully usable from the
  Command Window (the Headless Release) before the GUI is built, so value shows up
  early. The GUI is **committed**, but it only wires controls to the already-tested
  headless API — no logic lives in it. This keeps the no-GUI path first-class and
  makes the GUI cheaper and more robust to build.
- **One `Result` object** (✅ 2.9) — every consumer reads the same computed output; no
  double-math between report and GUI. Unbuilt checks report `NotEvaluated` (a
  first-class status), so real results ship without fake numbers.
- **Units: English + °C** — inch/lbf/psi with temperature in °C and CTE in 1/°C. One
  contract, documented in `UNITS.md`; conversion only at the GUI boundary.
- **Validate against a known-good answer key, not the Python tool** — the Python app
  defines *features*; the numbers are validated against the **DABJ course book §9
  public worked example** (primary), with a second wave of cases from the group's
  spreadsheet later (Phase 3.4).
- **Domain rules baked in** — flanges = the clamped stack only (not the threaded
  interface); tapped-hole parent-thread shear is a distinct check (✅ 3.3).
- **The group's thread-shear method** (✅ 3.3) — thread stripping uses the group's
  practice `As = 0.75·π·E·Le` (pitch diameter × engagement, 3/4·π coefficient on
  BOTH sides), not TM-106943's printed 5/8 external form and not DABJ §6's H28
  tolerance form with judgment knockdown; and inserts use the MANUFACTURER
  (Heli-Coil) rated pull-out load — one spec value — not the TM three-mode split.

---

## 6. Testing & validation

- **Structural tests (✅ now):** `tests/tModel.m` proves the model constructs,
  composes, computes its derived fields (`Pitch`, `GripLength`), and rejects bad input.
  `tests/tLibrary.m` proves the library serves the DABJ bolt/material/spec by key
  and errors clearly on unknown keys. `tFastenerToolSmoke.m` proves the entry point runs. Tests add the source folder to
  the path via a `PathFixture`, so they pass regardless of the current folder.
  `tests/tDabjCase.m` proves the DABJ §9 validation case builds and pins the
  book's expected numbers.
- **Validation answer key (✅ Phase 2.3):** `validation.dabjSection9()` encodes the
  **DABJ §9 worked example** — the full Joint/LoadCase/Factors built from the
  library, plus every published intermediate (preloads, design loads) and the six
  published margins, with tolerances. Engine steps (⏳ Phase 2.4 onward) replay
  this case — and later group-spreadsheet cases (Phase 3.4) — and assert a numeric
  match. This is the guardrail against silent drift in a safety-critical tool.

---

## 7. Phase ↔ architecture map

| Layer / capability | Phase | Status |
|--------------------|-------|--------|
| Skeleton + domain model (`+model`) | 1 — Foundation | ✅ |
| Model finalization (`PreloadSpec`, `LoadCase`, `Factors`) | 2.1 | ✅ |
| Library seed (`+data`) | 2.2 | ✅ |
| Validation answer key (DABJ §9, `+validation`) | 2.3 | ✅ |
| Preload (`engine.preload`, validated vs DABJ §9) | 2.4 | ✅ |
| Design loads + ultimate-tension margin w/ separation-before-rupture gate (`engine.designLoads`, `engine.marginTensionUlt`) | 2.5 | ✅ |
| Separation + bolt-yield margins (`engine.marginSeparation`, `engine.marginBoltYield`) | 2.6 | ✅ |
| Ultimate-shear + tension-shear interaction margins (`engine.marginShearUlt`, `engine.marginInteraction`) | 2.7 | ✅ |
| Slip margin (`engine.marginSlip`, DABJ Eq. 84) | 2.8 | ✅ |
| Single-joint solver + `Result` (`engine.analyze`) | 2.9 | ✅ |
| Joint stiffness, 30° frustum (`engine.stiffness`, validated vs DABJ Ex. 8-b) | 3.1a | ✅ |
| Stiffness wiring: thermal preload (TM-106943 Eq. 10) + tension rupture branch (5020B Eq. 10; yield-side Eq. 11 deferred) | 3.1b | ✅ |
| Member checks: bearing (TM-106943 Eq. 72-74, validated vs DABJ Ex 5-b) + shear tear-out (Eq. 69-71) + bearing-under-head (Eq. 75) | 3.2 | ✅ |
| Thread checks: bolt-thread shear + nut strength + tapped-hole parent thread (group 0.75·π·E·Le method; tapped-parent cross-checked vs DABJ Ex 6-a) + insert via Heli-Coil rated pull-out — all 15 checks implemented | 3.3 | ✅ |
| Second validation wave (group-spreadsheet cases) | 3.4 | ⏳ |
| FEM force resolution (`engine.resolveForces` + `loadCaseFromForces`, `Joint.BoltAxis`) | 3.5a | ✅ |
| Table input (`data.loadJointLibrary` + `data.loadElements` + template CSVs) | 3.5b | ✅ |
| Bulk analysis (`engine.analyzeBulk`) + XLSX export (`report.exportResults`) + one-call `engine.runBulk` — **Headless Release** | 3.5c–3.6 | ✅ |
| Case save/load, presets, PDF reports | 3.7–3.8 | ⏳ |
| GUI (`+gui`) | 4 | ⏳ |
| Packaging (`.exe`) | 5 | ⏳ |

---

*Update this doc as each phase step lands — flip ⏳ to ✅ and fill in the real shapes
(especially the `Result` object) once they exist.*
