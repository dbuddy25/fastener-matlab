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
- **A known-good worked example is the SOURCE OF TRUTH for the NUMBERS** — first a
  fully published textbook joint (DABJ course book §9), then a second wave of cases
  from our group's spreadsheet.

Every calculation we build gets checked against the answer key before we move on.

*Say:* We copy the *behavior* from Python, but we trust the *numbers* from a published, fully worked example — and later from our own spreadsheet cases for the checks it doesn't cover. That's the guardrail.

---

## Slide 6 — How we'll build it: five phases
Work proceeds through five ordered phases. Each phase is a series of small steps ≈ one work session each.

| Phase | In plain terms |
|-------|----------------|
| **1 — Foundation** | The skeleton: project setup + the data model *(done)* |
| **2 — Validated single-joint engine** | The brain: one joint, every number proven right |
| **3 — Headless Release** | A complete, usable tool driven from scripts — no screen yet |
| **4 — GUI** | The dashboard: the point-and-click screen |
| **5 — Packaging** | The shipping box: turn it into a Windows app |

*Say:* We build the brain first and prove it's right, *then* wrap it in a nice interface — not the other way around.

---

## Slide 7 — Phase 2: the validated engine (the real work)
- Builds up from preload → design loads → the **safety checks** → one "analyze this joint" call.
- **Every step is checked against the worked example's numbers.** No moving on until they match.
- Ends at a big milestone: **"Engine Validated"** — it runs correctly with no screen at all.

*Say:* This is 60–70% of the value. Once the engine is validated, colleagues could already use it from their own scripts.

---

## Slide 8 — Headless-first: a usable tool before the GUI
Phase 3 delivers a **complete, usable tool with no screen**: import a table of joints → analyze everything → export the margins to Excel.

- Value shows up **early** — colleagues can run real analyses from their own scripts.
- The GUI is still **100% committed** — Phase 4 builds it as a **thin shell** on top of the already-proven engine.
- Because no math lives in the screen, the GUI is cheaper to build and harder to break.

*Say:* This isn't GUI-or-no-GUI. We ship a working script-driven tool first, then put the point-and-click screen on top. The screen just presses buttons on math that's already validated.

---

## Slide 9 — Phases 4 & 5: finishing up
- **4 — GUI:** the 11-tab screen — joint setup, analysis, libraries, bulk runs, diagrams — every control calling the already-proven engine. (Professional PDF and Excel reports land in Phase 3, so design reviews are covered even before the GUI.)
- **5 — Packaging:** compile to a standalone `.exe` and do a final full validation of the packaged app.

*Say:* These make it something the whole group can pick up and use, not just the person who built it.

---

## Slide 10 — Why this is trustworthy
- It follows the **NASA-STD-5020A** standard (the governing spec for this kind of analysis).
- **Every calculation is validated against a known-good answer key** — the published worked example first, then our own spreadsheet cases — at every step and again on the final packaged app.
- The tool **shows its work** — the equations behind each verdict are in the report.

*Say:* For a safety-critical check, "trust me" isn't enough. The design is built so every number is traceable.

---

## Slide 11 — Roadmap / effort
- Each step ≈ one focused session; safe to stop between any two.
- The five phases in order: **Foundation (done) → Validated engine → Headless Release → GUI → Package.**
- Value shows up **early** — a working, validated, script-usable tool well before the GUI exists.

*Say:* This delivers usable value incrementally. We're not waiting until the very end to have something that works.

---

## Slide 12 — Ask / next steps
- Agreement to **start Phase 2** (the validated engine) against the published worked-example answer key.
- Input on the **second-wave validation cases** — which representative joints from our spreadsheet to lock in later for the checks the worked example doesn't reach (bearing, inserts, tapped holes).
- Awareness that a **usable script-driven tool arrives before the GUI** — the GUI follows as a thin shell on top.

*Say:* Nothing blocks the start — the primary answer key is already published. What I'll need from the group later is the second wave of validation joints from our spreadsheet.

---

### Appendix — the 15 checks (for the engineer in the room)
Tension (ultimate + yield) · shear (ultimate + tearout) · bearing (+ under-head) · bolt-thread shear · nut strength · insert failure modes · separation · slip · separation-before-rupture · combined tension–shear interaction · tapped-hole parent-thread shear.

*Say:* Only pull this slide up if someone asks "which checks, exactly?"
