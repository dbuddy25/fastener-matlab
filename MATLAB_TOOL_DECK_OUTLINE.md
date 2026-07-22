# MATLAB Fastener Analysis Tool — Presentation Outline (plain-English)

> Slide-by-slide talking points for a share-out deck. Written for a mixed audience (managers + engineers who aren't bolt specialists). Copy each block into a slide; the **Say:** lines are speaker notes, the bullets are what goes on the slide.

---

## Slide 1 — Title
**A MATLAB Tool for Bolted-Joint Analysis**
Rebuilding our fastener margin-of-safety workflow, from scratch, in MATLAB.

*Say:* This is a proposal + roadmap for building our own MATLAB app that checks whether bolted joints are strong enough, to the NASA-STD-5020A standard.

---

## Slide 2 — The problem today
- Bolt-strength checks live in a **spreadsheet** (and a separate Python app).
- Spreadsheets are easy to break, hard to audit, and don't scale to hundreds of bolts.
- We want a **single, trusted, standalone tool** everyone in the group can run.

*Say:* Every project re-checks the same kinds of joints. Today that's manual spreadsheet work. We want to standardize it.

---

## Slide 3 — What the tool does (in one breath)
An engineer describes a bolted joint → the tool tells them **if it's strong enough, and why.**

1. **Describe the joint** — bolt size/material, the stack of parts being clamped, the nut/insert, how tight it's torqued, temperature.
2. **Apply the loads** — one case, or hundreds pulled from a finite-element model.
3. **Get the answer** — 15 pass/fail safety checks, with the governing equations shown.
4. **Report it** — PDF and Excel, ready for a design review.

*Say:* Think of it as: inputs in, a verdict out — with the math shown so it survives review.

---

## Slide 4 — Why MATLAB
- The group already **works in MATLAB** and has the licenses (Compiler, Report Generator).
- Compiles to a **standalone Windows `.exe`** — no MATLAB needed to run it (just a free runtime).
- Keeps the whole thing in **one ecosystem** we own and can maintain.

*Say:* We're not tied to the Python app — MATLAB fits how this group already works.

---

## Slide 5 — Two reference points (this is important)
- **The existing Python app tells us WHAT to build** — the features and workflow.
- **Our group's spreadsheet is the SOURCE OF TRUTH for the NUMBERS.**

Every calculation we build gets checked against the spreadsheet before we move on.

*Say:* We copy the *behavior* from Python, but we trust the *numbers* from our own validated spreadsheet. That's the guardrail.

---

## Slide 6 — How we'll build it: five "tracks"
Work is split into five ordered lanes. Each lane is a series of small steps ≈ one work session each.

| Track | In plain terms |
|-------|----------------|
| **A — Engine** | The brain: all the strength math |
| **B — Data** | The filing cabinet: bolt/material library, save/load |
| **C — Reports** | The paperwork: PDF + Excel output |
| **D — GUI** | The dashboard: the point-and-click screen (built last) |
| **E — Packaging** | The shipping box: turn it into a Windows app |

*Say:* We build the brain first and prove it's right, *then* wrap it in a nice interface — not the other way around.

---

## Slide 7 — Track A: the engine (the real work)
- Builds up from preload → forces → each of the **15 safety checks** → one "analyze this joint" button.
- **Every step is checked against the spreadsheet numbers.** No moving on until they match.
- Ends at a big milestone: **"Engine Validated"** — it runs correctly with no screen at all.

*Say:* This is 60–70% of the value. Once the engine is validated, colleagues could already use it from their own scripts.

---

## Slide 8 — The decision gate
After the engine + data are done, we **stop and decide**:

> Do we actually need to build the full point-and-click screen — or is a script-driven tool enough?

- The screen (GUI) is the **single biggest chunk of work** (~65% of the old app's code).
- We only build it if the audience truly needs it.

*Say:* This is deliberate. We don't sink months into a GUI until we've confirmed people want one. It's an off-ramp to save effort.

---

## Slide 9 — Tracks C, D, E: finishing up
- **C — Reports:** professional PDF and Excel output for design reviews.
- **D — GUI:** the 11-tab screen — joint setup, analysis, libraries, bulk runs, diagrams.
- **E — Packaging:** compile to a standalone `.exe` and do a final full validation against the spreadsheet.

*Say:* These make it something the whole group can pick up and use, not just the person who built it.

---

## Slide 10 — Why this is trustworthy
- It follows the **NASA-STD-5020A** standard (the governing spec for this kind of analysis).
- **Every calculation is validated against our spreadsheet** — at every milestone and again on the final packaged app.
- The tool **shows its work** — the equations behind each verdict are in the report.

*Say:* For a safety-critical check, "trust me" isn't enough. The design is built so every number is traceable.

---

## Slide 11 — Roadmap / effort
- Each milestone ≈ one focused session; safe to stop between any two.
- Rough order: **Engine → Data → (decide) → Reports → GUI → Package.**
- Value shows up **early** — a working, validated engine well before the GUI exists.

*Say:* This delivers usable value incrementally. We're not waiting until the very end to have something that works.

---

## Slide 12 — Ask / next steps
- Agreement to **start Track A** (engine) against a validation set from the spreadsheet.
- Input on the **validation cases** — which ~10–20 representative joints to lock in as the "answer key."
- A decision-maker for the **GUI gate** when we get there.

*Say:* The one thing I need to start is the validation set — the joints and expected answers we'll build against.

---

### Appendix — the 15 checks (for the engineer in the room)
Tension (ultimate + yield) · shear (ultimate + tearout) · bearing (+ under-head) · bolt-thread shear · nut strength · insert failure modes · separation · slip · separation-before-rupture · combined tension–shear interaction · tapped-hole parent-thread shear.

*Say:* Only pull this slide up if someone asks "which checks, exactly?"
