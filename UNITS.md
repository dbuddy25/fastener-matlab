# Units Contract — MATLAB Fastener Analysis Tool

This tool uses **one fixed internal unit system**. There is no unit-aware type — a
`double` is just a number — so every value MUST be supplied in the units below.
The only unit conversion anywhere in the tool is temperature, at the GUI boundary.

## Canonical internal units

| Quantity | Unit | Notes |
|----------|------|-------|
| Length, diameter, thickness, grip | inch (in) | |
| Area | in² | e.g. tensile stress area `At` |
| Force, preload | pound-force (lbf) | |
| Stress / strength (`Ftu`,`Fty`,`Fsu`,`Fbru`,`Fbry`,`E`) | psi | |
| Temperature | **degree Celsius (°C)** | the engine computes in °C |
| Coefficient of thermal expansion (`CTE`) | **1/°C** (= in/in/°C) | must match the °C basis |

The system is **US-customary structural (in, lbf, psi) with Celsius temperature** — a
deliberate mixed system, chosen because the group works in °C.

## The temperature rule
- The **engine works internally in °C**; thermal preload uses `ΔT(°C) × CTE(1/°C)`.
- The GUI may let the user enter/display °F, but it **converts to °C at the boundary** —
  the engine never sees Fahrenheit (GUI unit toggle: milestone D12).
- CTE and temperature must always share the °C basis. A CTE given in in/in/°F is wrong
  here; multiply a per-°F CTE by **1.8** to get 1/°C.

## Enforcement
Units are a **convention, not enforced by the type system**. Safeguards:
- Every physical property in `+model` carries its unit in a code comment.
- **This file is the single source of truth** — update it if the convention ever changes.
- Library / imported data (Track B) must be normalized to these units on the way in.
