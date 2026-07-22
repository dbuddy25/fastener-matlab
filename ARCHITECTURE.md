# Architecture — MATLAB Fastener Analysis Tool

How the pieces fit together. **This is a living document** — it describes what is
built today and where it is headed. Each section is tagged:

- ✅ **Built** — exists and tested now
- ⏳ **Planned** — designed, not yet implemented (phase noted)

**Current state: through Phase 1 (Foundation — skeleton + data model).** No analysis
math exists yet.

---

## 1. The big picture

The tool takes a **description of a bolted joint**, runs it through the
**NASA-STD-5020A margin checks**, and **presents the result**. Three responsibilities,
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
        (✅ Joint; ⏳ 2.1)                                    (⏳ 2.9 solver)
                                                                  │
                                              engine.Result  ──▶  report / gui
                                            (⏳ result object)   (⏳ Phases 3–4)
```

- **Input:** one `model.Joint` — a fully-described joint (✅ you can build this today) —
  plus a `model.LoadCase` (the applied loads) and `model.Factors` (safety + fitting
  factors), both passed to `analyze()` rather than stored on the Joint (⏳ Phase 2.1).
- **Engine:** resolves loads, computes preload/stiffness, runs all 15 margin checks,
  applies the interaction and separation logic. (⏳ built up piece by piece, Phases 2–3.)
- **Output:** one `engine.Result` object — the 15 margins, each with pass/fail status
  (`Pass|Fail|NotEvaluated`), the governing equation/method, plus `WorstMargin`,
  `GoverningCheck`, the Fig 8 `Narrative`, and `asTable()`. Every consumer (report, GUI,
  bulk table) reads this *one* shape, so nothing re-derives numbers. (⏳ defined
  alongside the solver, Phase 2.9.)
- **Bulk:** the same flow mapped over many joints/load cases → a results table:
  `engine.analyzeBulk(cases, factors)`. (⏳ Phase 3.5.)

### Headless usage — the primary path (⏳ Headless Release)

You don't build many joints by hand — you **describe them in a table and import them.**
This is the whole product for an engineer who lives in MATLAB/Excel, no GUI required:

```matlab
lib     = data.Library.load();                    % ⏳ 2.2 — hardware/material catalog
cases   = data.loadJoints("my_joints.xlsx", lib); % ⏳ 3.5 — table → joints + load cases
results = engine.analyzeBulk(cases, factors);     % ⏳ 3.5 — all 15 margins per joint
writetable(results, "margins.xlsx");              % ⏳ 3.6 — answers out
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
├── +engine/         ⏳ analysis math (the core)             — Phases 2–3
├── +data/           ⏳ library + case save/load (JSON)      — Phases 2–3
├── +report/         ⏳ PDF + XLSX export                    — Phase 3
├── +gui/            ⏳ App Designer app (thin shell)        — Phase 4
└── tests/           ✅ smoke + model tests; ⏳ validation   — throughout
```

Package classes reference each other with the `model.` / `engine.` prefix.

---

## 4. The domain model (`+model`) — ✅ built (Phase 1)

The vocabulary the whole engine speaks. All are **value classes** with name-value
constructors, input validation, and unit comments (see `UNITS.md`).

| Type | What it is | Notable fields |
|------|-----------|----------------|
| `Bolt` | Bolt geometry + threads (no material) | `NominalDiameter`, `ThreadsPerInch`, `TensileStressArea`; computed `Pitch` |
| `Material` | Strength + thermal props, any role | `Ftu`,`Fty`,`Fsu`,`Fbru`,`Fbry`,`E`,`CTE` |
| `ThreadedMember` | What the bolt threads into | `Type` (Nut/Insert/TappedHole), `Material`, `RatedUltimateLoad` |
| `FlangeLayer` | One layer of the clamped stack | `Material`, `Thickness` |
| `Joint` | The whole joint, ties it together | `Bolt`, `BoltMaterial`, `FlangeStack`, `ThreadedMember`, `Preload`, temps, `ShearPlane`; computed `GripLength` |
| `ThreadSeries` | enum | `UNC`, `UNF` |
| `ThreadedMemberType` | enum | `Nut`, `Insert`, `TappedHole` |
| `ShearPlaneCondition` | enum | `ThreadsInShear`, `BodyInShear` |

### Planned additions — ⏳ Phase 2.1 (model finalization)

| Type | What it is | Notes |
|------|-----------|-------|
| `PreloadSpec` | Full preload definition | **Replaces the scalar `Preload`** on `Joint`: torque min/max, nut factor K, uncertainty Γ, relaxation/creep, thermal |
| `LoadCase` | Applied loads for one case | Per-bolt + joint-level loads; **passed to `analyze()`, not stored on the Joint** |
| `Factors` | Safety + fitting factors | Also passed to `analyze()`, not stored on the Joint |

Plus field additions: `Joint` gains `BoltCount`, `FrictionCoefficient`,
`LoadingPlaneFactor`, and bolt spec allowables; `Bolt` gains `MinorDiameter` and
`BodyDiameter` (with dependent `MinorArea`/`BodyArea`).

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
- **One `Result` object** (⏳) — every consumer reads the same computed output; no
  double-math between report and GUI.
- **Units: English + °C** — inch/lbf/psi with temperature in °C and CTE in 1/°C. One
  contract, documented in `UNITS.md`; conversion only at the GUI boundary.
- **Validate against a known-good answer key, not the Python tool** — the Python app
  defines *features*; the numbers are validated against the **DABJ course book §9
  public worked example** (primary), with a second wave of cases from the group's
  spreadsheet later (Phase 3.4).
- **Domain rules baked in** — flanges = the clamped stack only (not the threaded
  interface); nut strength uses the spec-rated ultimate load, not a thread-stripping
  calc; tapped-hole parent-thread shear is a distinct check (Phase 3.3).

---

## 6. Testing & validation

- **Structural tests (✅ now):** `tests/tModel.m` proves the model constructs,
  composes, computes its derived fields (`Pitch`, `GripLength`), and rejects bad input.
  `tFastenerToolSmoke.m` proves the entry point runs. Tests add the source folder to
  the path via a `PathFixture`, so they pass regardless of the current folder.
- **Numerical validation (⏳ Phase 2.3 onward):** each engine step will replay the
  validation case(s) — joints with published expected margins, seeded by the **DABJ
  §9 worked example** and expanded with group-spreadsheet cases in Phase 3.4 — and
  assert a numeric match. This is the guardrail against silent drift in a
  safety-critical tool.

---

## 7. Phase ↔ architecture map

| Layer / capability | Phase | Status |
|--------------------|-------|--------|
| Skeleton + domain model (`+model`) | 1 — Foundation | ✅ |
| Model finalization (`PreloadSpec`, `LoadCase`, `Factors`) | 2.1 | ⏳ next |
| Library seed (`+data`) | 2.2 | ⏳ |
| Validation answer key (DABJ §9) | 2.3 | ⏳ |
| Preload + core margins | 2.4–2.8 | ⏳ |
| Single-joint solver + `Result` | 2.9 | ⏳ |
| Remaining checks + second validation wave | 3.1–3.4 | ⏳ |
| Table input + bulk analysis + XLSX (Headless Release) | 3.5–3.6 | ⏳ |
| Case save/load, presets, PDF reports | 3.7–3.8 | ⏳ |
| GUI (`+gui`) | 4 | ⏳ |
| Packaging (`.exe`) | 5 | ⏳ |

---

*Update this doc as each phase step lands — flip ⏳ to ✅ and fill in the real shapes
(especially the `Result` object) once they exist.*
