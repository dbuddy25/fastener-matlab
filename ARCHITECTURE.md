# Architecture — MATLAB Fastener Analysis Tool

How the pieces fit together. **This is a living document** — it describes what is
built today and where it is headed. Each section is tagged:

- ✅ **Built** — exists and tested now
- ⏳ **Planned** — designed, not yet implemented (milestone noted)

**Current state: through milestone A2 (data model).** No analysis math exists yet.

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
      ✅ A2              ⏳ A4–A15          ⏳ Track C/D
```

**Golden rule:** the **engine never depends on the GUI**. It runs headless from the
Command Window. The GUI is a thin layer on top, built last (Track D) — and only if
the audience needs it (the "decision gate" after Tracks A+B).

---

## 2. The data flow (target)

The single flow everything is organized around:

```
  model.Joint  ──▶  engine.analyze(joint, factors)  ──▶  engine.Result  ──▶  report / gui
   (✅ built)              (⏳ A12 solver)              (⏳ result object)     (⏳ C/D)
```

- **Input:** one `model.Joint` — a fully-described joint (✅ you can build this today).
- **Engine:** resolves loads, computes preload/stiffness, runs all 15 margin checks,
  applies the interaction and separation logic. (⏳ built up piece by piece, A4–A15.)
- **Output:** one `engine.Result` object — the 15 margins, pass/fail, and the
  governing equation behind each. Every consumer (report, GUI, bulk table) reads this
  *one* shape, so nothing re-derives numbers. (⏳ defined alongside the solver, A12.)
- **Bulk:** the same flow mapped over many joints/load cases → a results table. (⏳ A14.)

---

## 3. Package map

```
matlab/
├── fastenerTool.m   ✅ entry-point stub (prints version)   — A1
├── +model/          ✅ domain types (the "nouns")           — A2
├── +engine/         ⏳ analysis math (the core)             — Track A (A4–A15)
├── +data/           ⏳ library + case save/load (JSON)      — Track B
├── +report/         ⏳ PDF + XLSX export                    — Track C
├── +gui/            ⏳ App Designer app (built last)        — Track D
└── tests/           ✅ smoke + model tests; ⏳ validation   — throughout
```

Package classes reference each other with the `model.` / `engine.` prefix.

---

## 4. The domain model (`+model`) — ✅ built (A2)

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

**Why one `Material` for every role:** a bolt material and a flange material are the
same *kind* of thing; flanges just also use the bearing fields (`Fbru`/`Fbry`) that
bolts ignore. Keeping them one type lets a shared alloy serve both roles; the
"which material goes where" distinction is a *library* concern (Track B), not a type.

---

## 5. Key design decisions (and why)

- **Layered, engine-first, GUI-last** — value shows up early (a validated headless
  engine is usable from scripts before any screen exists) and the biggest, riskiest
  chunk (GUI) is deferred until proven necessary.
- **One `Result` object** (⏳) — every consumer reads the same computed output; no
  double-math between report and GUI.
- **Units: English + °C** — inch/lbf/psi with temperature in °C and CTE in 1/°C. One
  contract, documented in `UNITS.md`; conversion only at the GUI boundary.
- **Validate against the spreadsheet, not the Python tool** — the Python app defines
  *features*; the group's spreadsheet is the source of truth for *numbers*.
- **Domain rules baked in** — flanges = the clamped stack only (not the threaded
  interface); nut strength uses the spec-rated ultimate load, not a thread-stripping
  calc; tapped-hole parent-thread shear is a distinct check (A13).

---

## 6. Testing & validation

- **Structural tests (✅ now):** `tests/tModel.m` proves the model constructs,
  composes, computes its derived fields (`Pitch`, `GripLength`), and rejects bad input.
  `tFastenerToolSmoke.m` proves the entry point runs. Tests add the source folder to
  the path via a `PathFixture`, so they pass regardless of the current folder.
- **Numerical validation (⏳ A3 onward):** each engine milestone will replay a
  `validation_cases` set — real joints with expected margins from the group's
  spreadsheet — and assert a numeric match. This is the guardrail against silent
  drift in a safety-critical tool.

---

## 7. Milestone ↔ architecture map

| Layer / capability | Milestone(s) | Status |
|--------------------|-------------|--------|
| Entry-point skeleton | A1 | ✅ |
| Domain model (`+model`) | A2 | ✅ |
| Validation set (answer key) | A3 | ⏳ next |
| Preload, stiffness, forces | A4–A5 | ⏳ |
| The 15 margin checks | A6–A11, A13 | ⏳ |
| Single-joint solver + `Result` | A12 | ⏳ |
| Bulk analysis | A14 | ⏳ |
| Data layer (`+data`) | Track B | ⏳ |
| Reports (`+report`) | Track C | ⏳ |
| GUI (`+gui`) | Track D | ⏳ |
| Packaging (`.exe`) | Track E | ⏳ |

---

*Update this doc as each milestone lands — flip ⏳ to ✅ and fill in the real shapes
(especially the `Result` object) once they exist.*
