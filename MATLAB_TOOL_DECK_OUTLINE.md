# MATLAB Fastener Analysis Tool — Share-out Deck Outline

> Slide-by-slide talking points for a share-out. Mixed audience — managers
> plus engineers who aren't bolt specialists. Copy each block into a slide; the
> **Say:** lines are speaker notes, the bullets go on the slide.
>
> Written to stand on its own: it assumes the room has heard nothing about this
> before. Start at the problem, end at what I need.

---

## Slide 1 — Title
**A MATLAB Tool for Bolted-Joint Analysis**
Built to NASA-STD-5020B. Validated against a published worked example.

*Say:* Every bolted joint we fly has to be shown strong enough. This is a
purpose-built tool for that check, with its work shown — where each number came
from, how we know it's right, and what it needs next.

---

## Slide 2 — The problem we started with
A bolted-joint margin has to survive review, and an ad-hoc calculation doesn't.

- **It can't be tested.** Nothing re-checks the arithmetic after an edit. A
  changed number is caught by whoever happens to notice.
- **It can't be traced.** A result on its own doesn't say which equation, or
  which standard, it came from.
- **It doesn't scale.** Hundreds of joints out of a FEM run means hundreds of
  copies of the same hand check.
- **It's hard to review.** "Is this right?" gets answered by reading formulas
  left to right.

*Say:* None of this says the answers were wrong. It says you can't efficiently
*demonstrate* that they're right — and for a safety-critical check, being right
and showing you're right are two different jobs.

---

## Slide 3 — What we built instead
An engineer describes a bolted joint → the tool says **whether it's strong
enough, and why.**

1. **Describe the joint** — bolt, the stack of parts clamped, nut or insert, how
   tight it's torqued, temperature.
2. **Apply the loads** — one case by hand, or hundreds pulled from a FEM run.
3. **Get the answer** — 15 pass/fail checks, governing equation shown for each.
4. **Report it** — Excel and PDF, ready for a design review.

*Say:* Inputs in, verdict out — with the math shown, so it survives review.

---

## Slide 4 — The decision that shaped everything: engine first, screen second
Five phases, built strictly in order.

| Phase | In plain terms | Status |
|---|---|---|
| 1 — Foundation | Project skeleton and data model | ✅ |
| 2 — Validated engine | The brain: one joint, every number proven | ✅ |
| 3 — Headless release | A complete tool driven from scripts, no screen | ✅ |
| 4 — Interface | The point-and-click screen | ✅ mostly |
| 5 — Packaging | Turn it into a Windows app | ⬜ |

**No analysis logic lives in the interface.** Every control calls an engine
function that already has a test behind it. The screen formats and displays; it
never computes.

*Say:* We built the brain first and proved it right, then wrapped it in a screen.
Because no math lives in the interface, a screen bug cannot quietly change an
answer — and the screen was far cheaper to build on an engine that already
worked.

---

## Slide 5 — How we know the numbers are right
- Every calculation is checked against a **published worked example** — the DABJ
  course book §9 joint, whose answers are printed in the book.
- **198 automated checks** re-verify the whole tool on one command.
- **A disagreement stops the work.** It caught several real mistakes during the
  build, including one that would have coloured every failing margin green.
- Every equation in the code cites its **source document and equation number at
  the point it is used**.

*Say:* For a safety-critical check, "trust me" isn't enough. The tool re-proves
itself against a published answer every time we touch it. That test count is the
number I'd watch.

---

## Slide 6 — What it can do today
- **One joint at a time** — pick hardware from dropdowns, get 15 margins with the
  governing check called out and its derivation open. A check it cannot evaluate
  says so and names the missing input; it never guesses (see Slide 10).
- **Hundreds at a time** — map FEM element IDs to joints, import forces one load
  case per sheet, run the batch, export a formatted workbook.
- **Preliminary sizing** — sweep every bolt size for the lightest that passes,
  before committing to a design.
- **Argues with you before you have a number** — a bolt too short for the stack,
  a preload above yield, a force file that doesn't match your model.
- **Hardware library** — 33 bolt sizes, 30 materials, plus nuts and washers
  seeded from their governing drawings, so geometry and rated loads come off the
  spec sheet instead of being typed in.

*Say:* The "argues with you" one is where the time is saved. The tool objects
*before* you have an answer, not after review.

---

## Slide 7 — What rebuilding surfaced ⭐
Rebuilding meant justifying every number. That turned up real issues.

| Finding | Consequence |
|---|---|
| **Nut strength should be capped at the nut's rated load** — 5020B is explicit; nuts spread under load, so a calculated area flatters them | A calculated-only check can read **better than reality** |
| **The allowable belongs to the whole fastening system, not the bolt** — a nut weaker than the bolt sets the limit | Changes which failure the joint is judged against, and can flip how the joint is assumed to fail |
| **An insert's strength belongs to the metal it's screwed into**, not a single catalogue number | The same insert in aluminium and in titanium is not the same strength |
| **`#10-32` tensile stress area is 0.0200 in²** — the ASME formula and the ASME table agree; a 0.01970 value in circulation does not | A size we actually use |
| **A dozen fine-thread minor diameters contradicted their own stress areas** in the source data we started from | Two columns of one table can't both be right |
| **A temperature convention is easy to document backwards** — the ΔT sign is now stated once in `UNITS.md` and re-stated at each point of use | Prose that contradicts the code silently inverts every thermal margin |

*Say:* This is the part I didn't expect. Rebuilding forces you to justify every
number, and that's where these surfaced. All of them are written up.

---

## Slide 8 — One worth walking through: the thread-form question
**Asked:** are our thread stress areas ~8% low? The textbook's rated loads imply
an area 8.2% larger than ours — identically on ultimate and yield, so an *area*
difference, not a strength one.

**Answered — no.** NAS1351/NAS1352 specify **UNRF**, not UNJ. UNR rounds the
thread root but keeps standard diameters, so the ASME area we use is correct.
UNJ, the form with the enlarged root that gives the bigger area, is a different
specification.

**The trap it left, which is the real finding:** the textbook's tables assume
UNJF, so its allowables are sized for a larger thread area than our hardware
has. **Never pair the book's rated loads with a real NAS part.** The one bolt
entry that does is labelled fixture-only in the library for exactly this reason.

*Say:* I'm showing this one because the answer mattered less than what it
uncovered. The hardware was fine. The hazard was two sources that look
compatible and aren't.

---

## Slide 9 — Validation, and one trade we made
- The **published textbook example** runs automatically on every change, and
  covers everything it touches.
- A second wave of acceptance cases is verified **locally**, with only the
  *outcome* recorded — "verified locally, <date>, agreement within X%, inputs
  not in repo."

**The trade, named plainly:** case data that can't be published stays out of the
repository entirely, and we give up reproducibility on those particular cases. A
future maintainer can see *that* they passed, not re-run them.

*Say:* Traceability without the data. I'd rather state the cost up front than let
someone discover it later.

---

## Slide 10 — What's left
| | |
|---|---|
| **Bolt bending** *(deliberately deferred)* | 5020B §4.4.4 says bending typically need not be accounted for with close-tolerance or interference fits — which is what we mostly build. Omitted on that basis. **The condition matters:** a joint with clearance, or shear across a gap or spacer, does need it. |
| **Exact stiffness for inserts and tapped holes** | The conical-frustum model is built for through-bolt nut joints with a uniform clamped modulus. For inserts, tapped holes and mixed-material stacks it falls back to a conservative assumption rather than an exact stiffness factor — those joints still analyse, just pessimistically. Buys accuracy, not capability. |
| **Insert allowables in the library** | Bolts, nuts and washers now come from their drawings. Inserts are still typed in by hand. |
| **Packaging** | Compile to a standalone `.exe`, then re-validate the packaged app. |
| **Documentation** | User guide and equation reference as shipped PDFs. |

*Say:* None of these block using the tool, and two are deliberate. Bending is
omitted because the standard says it typically isn't needed for the close-
tolerance fits we mostly build. What I'd ask you to remember is the condition
attached: if you have real clearance, or shear crossing a gap or a spacer, the
standard does want bending, and the tool won't tell you that. The stiffness item
is different in kind — those joints analyse fine today, just conservatively.
Everything here is written up with what closing it would take.

---

## Slide 11 — What this needs next
1. **Material properties — specifically CTE.** The library carries handbook
   placeholders today. The standard requires CTE for thermal preload, so every
   thermal margin currently traces back to a placeholder value.
2. **A reviewer for the design-decisions write-up** — where this tool takes a
   position the sources leave open, someone should sanity-check that I've called
   the right one correct.
3. **Confirm one asymmetry:** the tool computes ultimate-only for tapped holes,
   but ultimate *and* yield for inserts. That gap is deliberate and called out
   rather than papered over — is ultimate-only acceptable for tapped holes?
4. **Real cases run through it** by someone other than me, to build confidence
   before anyone relies on it.

*Say:* The tool is at the point where more eyes are worth more than more code.

---

## Slide 12 — Why this is trustworthy
- Follows **NASA-STD-5020B**, and every equation cites its source document and
  equation number **at the point it's used**.
- **Validated against a published worked example**, re-checked automatically on
  every change.
- **Shows its work** — each verdict carries its governing equation and the
  decision narrative behind it.
- **Where the standard gives no equation, the code says so** rather than
  inventing a citation.
- **Where a value is a placeholder or a stand-in, the entry says so** — in the
  data itself, not in a comment someone has to go find.

*Say:* The last two are the ones I'd defend hardest. There are places where the
standard gives no formula and we use a derived convention. The code states that
outright, so nobody mistakes it for something it isn't.

---

### Appendix A — the 15 checks (for the engineer in the room)
Tension (ultimate + yield) · shear (ultimate + tearout) · bearing (+ under-head) ·
bolt-thread shear · nut strength · insert pull-out · tapped-hole parent-thread
shear · separation · slip · separation-before-rupture · combined tension–shear
interaction.

*Say:* Only pull this up if someone asks "which checks, exactly?"

### Appendix B — how the hardware library works
Entries are **baseline** (shipped, reviewed) or **custom** (added by a user).
Saving writes only the custom ones, so a corrected baseline value in a later
release actually reaches someone who has already saved a library — a stale local
copy can't silently win forever. Every entry also carries free-text provenance
naming the document its numbers came from.

*Say:* This is what stops the library drifting into private local copies that
never get a correction.

### Appendix C — where the documentation lives
| File | What it holds |
|---|---|
| `VALIDATION.md` | Every check, its answer-key source, and its status |
| `TOOL_DIFFERENCES.md` | Every design decision where this tool takes a position, and why |
| `MATLAB_BUILD_GUIDE.md` | The five-phase plan and where each step landed |
| `GUI_PORT_SPEC.md` | The interface design and the decisions behind it |
| `USER_GUIDE.md` | How to run it |

*Say:* If someone asks "how do I know X was considered" — it's in one of these.
