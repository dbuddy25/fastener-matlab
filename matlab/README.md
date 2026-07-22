# MATLAB Fastener Analysis Tool

Ground-up MATLAB rebuild of the NASA-STD-5020A bolted-joint analysis tool.
See the sibling docs (one level up) for the plan:

- `../MATLAB_BUILD_GUIDE.md` — build sequence & milestones (A1 → E3)
- `../MATLAB_TOOL_PRD.md` — requirements spec
- `../MATLAB_TOOL_DECK_OUTLINE.md` — stakeholder deck

## Layout

```
matlab/
├── fastenerTool.m     entry point (A1 stub — prints version)
├── +engine/           analysis math — the core (Track A)
├── +data/             library + case save/load, JSON (Track B)
├── +report/           PDF + XLSX export (Track C)
├── +gui/              App Designer app — built last (Track D)
└── tests/             validation + smoke tests (run against the spreadsheet)
```

The `+engine` package is kept fully independent of `+gui` — it must run
headless from the console.

## Run it (on a machine with MATLAB)

From the `matlab/` folder:

```matlab
fastenerTool                 % prints the version banner (A1)
runtests("tests")            % runs the smoke test — A1 "done when" check
```

> **Note:** developed on macOS (no MATLAB here), so the "stub runs" acceptance
> is verified on the Windows/MATLAB work machine. Just copy the `matlab/`
> folder over, `cd` into it in MATLAB, and run the two commands above.

## Current status

**A2 — Data model complete.** The `+model` package defines `Bolt`, `Material`,
`ThreadedMember`, `FlangeLayer`, `Joint`, and the enums (`ThreadSeries`,
`ThreadedMemberType`, `ShearPlaneCondition`) — a full joint can be constructed
in the Command Window (see the usage example in `+model/Joint.m`, exercised by
`tests/tModel.m`). Next: **A3**.
