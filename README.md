# Fastener Analysis Tool (MATLAB)

Ground-up MATLAB build of a NASA-STD-5020A bolted-joint margin-of-safety
analysis tool, deployable as a standalone Windows executable.

## Docs (read these first)

- **`MATLAB_BUILD_GUIDE.md`** — the build sequence: five tracks (A–E), each a
  chain of small milestones with a "Done when" acceptance test.
- **`MATLAB_TOOL_PRD.md`** — the requirements spec (what to build + the rules).
- **`MATLAB_TOOL_DECK_OUTLINE.md`** — plain-English outline for a share-out deck.

## Source layout

```
matlab/
├── fastenerTool.m     entry point (A1 stub — prints version)
├── +engine/           analysis math — the core (Track A)
├── +data/             library + case save/load, JSON (Track B)
├── +report/           PDF + XLSX export (Track C)
├── +gui/              App Designer app — built last (Track D)
└── tests/             validation + smoke tests (checked vs the spreadsheet)
```

## Run it (machine with MATLAB)

Open MATLAB, point the Current Folder at `matlab/`, then in the Command Window:

```matlab
fastenerTool                 % prints the version banner  (A1)
runtests("tests")            % runs the smoke test — A1 "done when" check
```

## Two authoritative references

- The **existing Python tool** defines *what to build* (features/workflow).
- The **group's spreadsheet** is the *source of truth for the numbers* — every
  margin is validated against it, not against the Python tool.

## Status

**A1 — Project skeleton** complete (scaffold + stub + smoke test).
Next: **A2 — data model.** See `MATLAB_BUILD_GUIDE.md`.
