# Fastener Analysis Tool (MATLAB)

Ground-up MATLAB build of a NASA-STD-5020A bolted-joint margin-of-safety
analysis tool, deployable as a standalone Windows executable.

## Docs (read these first)

- **`MATLAB_BUILD_GUIDE.md`** — the build sequence: five tracks (A–E), each a
  chain of small milestones with a "Done when" acceptance test.
- **`MATLAB_TOOL_PRD.md`** — the requirements spec (what to build + the rules).
- **`MATLAB_TOOL_DECK_OUTLINE.md`** — plain-English outline for a share-out deck.
- **`UNITS.md`** — the unit contract: English units (in, lbf, psi) with
  temperature in °C and CTE in 1/°C. Single source of truth for units.

## Source layout

```
matlab/
├── fastenerTool.m     entry point (A1 stub — prints version)
├── +model/            domain types: Bolt, Material, Joint, enums (Track A / A2)
├── +engine/           analysis math — the core (Track A)
├── +data/             library + case save/load, JSON (Track B)
├── +report/           PDF + XLSX export (Track C)
├── +gui/              App Designer app — built last (Track D)
└── tests/             validation + smoke tests (checked vs the spreadsheet)
```

## Run it (machine with MATLAB)

Open MATLAB, point the Current Folder at `matlab/`, then in the Command Window:

```matlab
fastenerTool                 % prints the version banner
runtests("tests")            % runs the smoke + model tests (should be all green)

% construct a joint (A2 acceptance):
b = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
               Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
               TensileStressArea=0.0200);
b.Pitch                      % -> 0.03125
```

> **Note:** developed on macOS (no MATLAB there), so acceptance is verified on the
> Windows/MATLAB work machine — `git pull` (or re-download), then run the above.

## Two authoritative references

- The **existing Python tool** defines *what to build* (features/workflow).
- The **group's spreadsheet** is the *source of truth for the numbers* — every
  margin is validated against it, not against the Python tool.

## Status

**A2 — Data model** complete. The `+model` package defines `Bolt`, `Material`,
`ThreadedMember`, `FlangeLayer`, `Joint`, and the enums (`ThreadSeries`,
`ThreadedMemberType`, `ShearPlaneCondition`); a full joint constructs in the
Command Window (see `+model/Joint.m`, exercised by `tests/tModel.m`).
Next: **A3 — validation set.** See `MATLAB_BUILD_GUIDE.md`.
