# Fastener Analysis Tool (MATLAB)

Ground-up MATLAB build of a NASA-STD-5020A bolted-joint margin-of-safety
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

## Source layout

```
matlab/
├── fastenerTool.m     entry point (Phase 1 stub — prints version)
├── +model/            domain types: Bolt, Material, Joint, enums (Phase 1)
├── +engine/           analysis math — the core (Phases 2–3)
├── +data/             library loader (`data.Library` + `library.json`, Phase 2.2); case save/load later (Phase 3)
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

**Phase 2.5 (ultimate-tension margin + separation gate) complete; next Phase 2.6 (separation + bolt-yield margins).**
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
`tests/tDabjCase.m`). See `MATLAB_BUILD_GUIDE.md`.
