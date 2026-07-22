# CLAUDE.md — Fastener Analysis Tool (MATLAB)

## Project

Ground-up MATLAB build of a NASA-STD-5020A bolted-joint margin-of-safety tool,
packaged as a standalone Windows `.exe`. See `MATLAB_BUILD_GUIDE.md` (sequence),
`MATLAB_TOOL_PRD.md` (requirements).

## Critical rules

- **No AI/tool attribution in commits or files.** No `Co-Authored-By` lines,
  no mention of the assistant, no session links. Plain commit messages only.
- **Two references, different jobs:** the existing Python tool defines *what to
  build*; the group's spreadsheet is the *source of truth for the numbers*.
  Validate every margin against the spreadsheet, never against the Python tool.
- **Build in track order.** A (engine) → B (data) → DECISION GATE → C/D → E.
  Don't start the GUI (Track D) until the gate is decided.
- **Engine is GUI-independent** and must run headless from the Command Window.

## Engineering ground rules (must be exactly right)

- **Interaction:** NASA-STD-5020A **Eq. 20–23** — not the simpler R²+R² form.
  Different exponents for threads-in-shear vs body-in-shear.
- **Thermal preload:** included, per TFSR 5.
- **Separation-before-rupture:** 5020A Fig 8 decision tree; the 0.75–0.85 × Ptu
  band conservatively assumes rupture when bolt-elongation data is unavailable.
- **Temperature:** engine works internally in **°F** (CTE data is in/in/°F);
  convert only at the GUI boundary.
- **Bolt length (nut config):** grip + nut height + 2·pitch.
- **Nut strength:** spec-rated ultimate load from the library, not a
  thread-stripping calc (5020A §4.2.2.8).
- **Flanges** = clamped stack only; insert/tapped-hole material is independent.

## Tech

- MATLAB (App Designer GUI, built last), JSON for library + cases.
- Licensing available: MATLAB Compiler, Report Generator, Database Toolbox.
- Run: open MATLAB, `cd matlab`, then `fastenerTool` / `runtests("tests")`.
