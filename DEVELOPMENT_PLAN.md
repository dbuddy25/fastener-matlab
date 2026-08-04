# Development Plan — MATLAB Bolted-Joint Analysis Tool

> How we intend to build a NASA-STD-5020B bolted-joint margin tool, and the
> discipline we intend to build it with. Written before development starts.
> `MATLAB_TOOL_PRD.md` states the requirements; this states the approach.

---

## 1. What we are building, and why

A standalone MATLAB application that takes a described bolted joint and applied
loads and returns margins of safety to NASA-STD-5020B, with the governing
equation shown for every result.

It replaces hand-built, worksheet-by-worksheet joint checking. Such a check is
not necessarily wrong — the problem is that it cannot efficiently be
*demonstrated* right. Nothing re-checks it after an edit, a number does not say
which equation produced it, hundreds of joints from an FE run means hundreds of
copies of the same manual work, and review means reading formulas one cell at a
time.

For a safety-critical check, being right and being able to show you are right are
two different jobs. The second one is what we are building.

Success is not "the tool produces numbers." Success is **an analyst can defend
every number in a design review**, and a maintainer three years from now can see
why each was computed the way it was.

---

## 2. The principles that will shape the build

These are decided up front because they are expensive to retrofit.

### 2.1 The engine comes first, and owns all the arithmetic

We build a headless engine, validate it, and only then wrap it in a screen. No
analysis logic will live in the interface — every control calls an engine
function that already has a test behind it. The screen formats and displays; it
never computes.

Two payoffs: a screen bug cannot quietly change an answer, and the interface is
far cheaper to build on an engine that already works. It also means the tool is
scriptable from day one, which is what makes bulk analysis possible at all.

### 2.2 Every equation carries its citation, at the point of use

At each place an equation is implemented, the comment states three things
together: the **reference document**, the **equation number** if one exists, and
the **formula written out**. The same citation surfaces in the value the function
returns, so it reaches results tables and reports rather than living only in
source.

```matlab
% NASA-STD-5020B Eq. 19 — MS = PpMin / Psep - 1
MS = preload.PpMin / designLoads.Psep - 1;
```

No bare equation numbers, no formulas without a citation. This is the single
convention that makes the tool reviewable, and it is unenforceable after the
fact — so it applies from the first equation written.

### 2.3 Document hierarchy: 5020B governs; supplements only where it defers

1. **NASA-STD-5020B is the governing standard.** Where it gives the equation, we
   cite it.
2. **Supplements** (NASA TM-106943 "Chambers", TM-108377, RP-1228 "Barrett") are
   cited *only where 5020B itself relies on them* for a formula it does not
   print — thread-shear areas, bearing, the stiffness derivation. Before citing a
   supplement, confirm 5020B does not give the equation itself.
3. **Where no source gives the equation**, the code says so. We will label a
   derived convention as derived, in plain words, and never attach an invented
   equation number to it. A reader must always be able to tell a standard
   requirement from a house rule.

### 2.4 Prefer the specified value; derive only as a labelled fallback

Where a procured item carries a rated strength — a nut, an insert, a bolt — we
use the rating, not a calculation. 5020B is explicit about this for threaded
parts: they expand under load, so a computed engagement area flatters them.

Where no rating exists, we derive, and **the result states which basis produced
it**. "We used the spec value" and "we computed one" are different claims and the
output must distinguish them.

### 2.5 Degrade honestly; never guess, never fail closed without cause

A check that cannot be evaluated reports **not evaluated, with the missing input
named**. It does not return zero, does not substitute a plausible default, and
does not abort the whole analysis.

Where a conservative assumption is available in place of an exact value, we take
it and say so. An answer that is knowingly pessimistic is useful; an answer that
is silently optimistic is dangerous. When in doubt, the direction that costs
margin is the one to take.

### 2.6 Data carries its provenance

Hardware and material entries are seeded from their governing drawings, and each
entry records in free text where its numbers came from. Placeholder or stand-in
values say so **in the data**, not in a comment someone has to find.

The library separates **baseline** (shipped, reviewed) from **custom** (added by
a user), and saving writes only the custom entries — so a corrected baseline in a
later release actually reaches someone who already saved a library, instead of a
stale local copy winning forever.

### 2.7 Validate against a published answer, not against another implementation

The primary validation key is a **public worked example with printed answers**.
We will never validate margins against another implementation of the same
standard — that would prove only that we reproduced someone else's arithmetic,
including any errors in it.

Any such implementation is at most a *cross-check*, run second and recorded as an
outcome. Where the two disagree, the disagreement gets written up and adjudicated
against the standard, not resolved by assuming either is correct.

---

## 3. Phases

Built strictly in order. Each phase has an exit criterion that must hold before
the next begins.

### Phase 1 — Foundation

Project skeleton, the domain model, units convention.

The domain model is the vocabulary the whole engine speaks: bolt, joint, flange
layer, threaded member, washer, load case, factors, preload spec. Value classes
with validated properties, so an impossible joint cannot be constructed.

Units are fixed and documented once: US customary (in, lbf, psi) with a single
stated temperature convention, converted only at the interface boundary. Mixed
units inside the engine is a defect class we intend never to have.

*Exit: a joint can be constructed in code and inspected.*

### Phase 2 — Validated single-joint engine

Every margin check, one joint at a time, each validated as it lands.

Order within the phase follows dependency, not the order checks appear in a
report: preload → design loads → tension → separation → shear → interaction →
slip → the assembled result object. Bearing, tear-out and the thread-strength
checks follow once the design-load convention is settled.

**A check is not done when it computes — it is done when it is pinned.** Either
against the published worked example, or by a hand derivation shown longhand in
the test so a reader can check it without running anything.

*Exit: the worked example reproduces, and one command re-verifies every check.*

### Phase 3 — Headless release

A complete, usable tool driven from scripts: table-based joint and load input,
bulk analysis over many joints, formatted export.

This phase exists because it forces the engine's interface to be honest before a
screen hides it. If the analysis is awkward to call from a script, it is badly
factored, and that is much cheaper to discover here than after a GUI is built on
top of it.

*Exit: hundreds of joints run from a workbook and export a reviewable result.*

### Phase 4 — Interface

A thin shell over the engine: a guided form for one joint, results with the
governing check called out and its derivation open, the bulk workflow, a hardware
browser.

The form's value is not data entry — it is the reactive logic. Selecting a thread
size cascades through bolt lengths, washer dimensions, clearance holes, thread
engagement and the preload readout. It should object *before* an answer exists: a
bolt too short for the stack, a preload above yield, a force file that does not
match the model.

Validation is layered: continuous required-field checking that disables Analyze
with a message naming what is missing; conditional fields that appear only when
they apply; and a run-time gate that lists problems and points at where to fix
them.

*Exit: an analyst who has not seen the engine can complete a real analysis.*

### Phase 5 — Packaging

Compile to a standalone Windows executable and **re-validate the packaged
application**. A packaged build is a different artifact from a scripted one, and
the validation suite has to pass against it, not just against the source.

*Exit: the executable reproduces the answer key.*

---

## 4. Validation strategy

**The published worked example is the spine.** It runs automatically on every
change. One command re-verifies the whole tool, and a disagreement stops work
rather than being triaged later.

**Hand-derived pins cover what the example does not.** Not every check appears in
a published example. For those, the test carries the derivation longhand in a
comment — the numbers, the equation, the arithmetic — so the pin is checkable by
reading rather than by trusting whoever wrote it.

**Proprietary cross-checks are recorded, not committed.** Cases built from
non-public data are verified locally and only the *outcome* is recorded: verified,
agreement within X%, inputs not in repository. This costs reproducibility on
those specific cases and we will say so plainly rather than let a future
maintainer discover it.

**Regression guards on the answer key.** The validated example's governing check
and worst margin are asserted in the tests of unrelated features, so a change
anywhere that disturbs the answer key fails loudly and immediately.

---

## 5. How we intend to handle the things that will go wrong

Every one of these will happen. Deciding the response now is cheaper than
deciding it under pressure.

### 5.1 When a source value is missing

**Do not invent it.** Not a strength, not an area, not a rating. A fabricated
number in a safety-critical library is the worst defect available to us, and it
is invisible once written.

The response is to seed what is available, mark the gap in the data itself, and
raise it as a question. A stand-in is acceptable if it is labelled as one and
errs conservative — and the label goes in the entry, not in a commit message.

### 5.2 When a configuration is not yet supported

Defer it deliberately, with the deferral written where a reader will hit it, and
**measure its reach before parking it.** A gap in a leaf function is a missing
feature. A gap in something with many dependents may bound what the tool can
analyse at all.

Reach is not the same as call count: a caller that substitutes a conservative
default degrades, while a caller with no fallback stops. Both look identical on a
dependency graph. Read the fallback paths, not just the edges.

### 5.3 When the tool disagrees with an independent check

Write it up before resolving it. Every divergence gets recorded with what each
side does and which one the standard supports. Some will be errors on the other
side, some ours, and some legitimate differences of convention — and the record
is what lets someone else adjudicate rather than take our word for it.

### 5.4 When the standard does not answer the question

Say so explicitly, choose the conservative reading, and label it a derived
convention. Do not attach a citation that does not exist. The moment the tool
cites something it cannot support, every other citation in it becomes suspect.

---

## 6. Decisions we expect to face

Named now so they are recognised as decisions rather than defaults:

- **Which interaction criterion** — the standard offers variants with and without
  plastic bending credit; the second needs a material property we may not have.
- **Whether bending is carried** — the standard makes it conditional on fit class
  and load path, which argues the joint should declare its case rather than the
  engine assuming one globally.
- **How far the stiffness model goes** — the frustum method is straightforward
  for a through-bolt joint with uniform clamped material and materially harder
  otherwise. A conservative fallback may be sufficient.
- **Which values the library ships** — every seeded number is a claim we are
  making on behalf of the analyst.

Each of these is an engineering decision, not an implementation detail. Each is
settled deliberately, and the answer is recorded with its date and reasoning.

---

## 7. Definition of done

The tool is done when:

1. Every check reproduces its answer key, automatically, on every change.
2. Every equation names its source document and equation number where the reader
   will see it.
3. Every derived convention is labelled as derived.
4. Every check that cannot be evaluated says so and names the missing input.
5. Every divergence from an independent check is written up and adjudicated.
6. The scope boundaries are stated plainly enough that nobody discovers one
   during a design review.
7. The packaged executable reproduces the answer key.

Points 3, 4 and 6 are the ones that will be tempting to skip. They are the ones
that make the rest of it trustworthy.
