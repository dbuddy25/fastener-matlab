# PRD — In-App User Guide

Status: **approved 2026-09-22; phase (a) next.** Delete this file once phase (d) ships;
live rules move into `GUI_SPEC.md` and `CONVENTIONS.md`.

## 1. Problem

`Help > User Guide` builds a PDF on demand with Report Generator
(`+report/userGuide.m`) from eight hand-written chapters of plain paragraphs
(`+report/userGuideChapters.m`).

| Complaint | Cause |
|---|---|
| Looks bad | Only `Paragraph` objects: no tables, no styling, none of the calc report's table machinery |
| Wrong content | Written as prose about the app, not tied to any page or field; nothing keeps it current |
| Walls of text | 3–5 long sentences per paragraph, no screenshots, no structure below chapter level |

It is also **unproven**: the test machine has no Report Generator, so
`tUserGuide/itBuildsAPdf` has never run. The first real build would be a user
clicking Help in the packaged `.exe`.

## 2. Goals / non-goals

**Goals**
- An analyst new to the tool can get from an empty case to a reviewed margin
  table using the guide and nothing else.
- Every field on every page is documented, and that documentation **cannot
  drift** from the app without a failing test.
- Help is one click from wherever the analyst is stuck.
- Opens offline, on a locked-down work machine, from the packaged `.exe`.

**Non-goals**
- Teaching 5020B or bolted-joint theory. The reader already knows it.
- Command Window / headless workflows. Those stay in `USER_GUIDE.md`.
- A PDF version. The browser can print it if one is ever needed.
- Equation derivations. Those stay in `ENGINE_CHECKS.md`.

## 3. Reader

**An analyst new to the tool**, fluent in 5020B and bolted joints. They open
the guide to answer one of these questions:

| Question | Where the guide answers it |
|---|---|
| What goes in this field, in what units? | The page's field table |
| Why is this field greyed out / blank / amber? | The page's "What you'll see" section |
| Which page comes next? | The page's "Next" line |
| What does this margin row check, and against which equation? | Results → the 15-check table |
| Why is a row `—` instead of a number? | Results → NotEvaluated |
| Where did this allowable come from? | Materials & Hardware section |

## 4. Format and structure

**Hand-written HTML + one CSS file + images, bundled with the app, opened in the
system browser.**

```
docs/userguide/
  index.html            landing: what the tool does, the rail, where to start
  guide.css
  pages/<pageId>.html   one per rail page (template + generated fragments)
  fragments/<pageId>-fields.html   GENERATED — never hand-edited
  img/<pageId>*.png     GENERATED — never hand-edited
  limits.html           what the tool does not do
  sources.html          where the numbers come from (hierarchy, citations)
```

`pageId` is the stable rail id (the contract in `FastenerApp.pageSpecs`), so file
names and "?" links key off something that already must not change:

| Rail | pageId | Section |
|---|---|---|
| SETUP | `Project` | Project |
| | `Factors` | Factors |
| | `TempLoads` | Temp Loads |
| SINGLE JOINT | `BoltSizing` | Bolt Sizing |
| | `JointConfig` | Joint Config |
| | `Results` | Single Joint Results |
| BULK 1–4 | `DefinedJoints` | Defined Joints |
| | `ElementMapping` | Element Mapping |
| | `ElementForces` | Element Forces |
| | `BulkAnalysis` | Bulk Analysis |
| REFERENCE | `HardwareLibrary` | Materials & Hardware |

One file per page, not one long file with `#anchors`. That sidesteps the fragment
risk in §8 and keeps each page short.

### Page template (every rail page, same order)

1. **Purpose**: 2–3 sentences. What this page is for and when you use it.
2. **Screenshot**: generated, in a known populated state.
3. **Fields**: the generated table, with columns *Group · Field · What it means*.
4. **What you'll see**: the behaviors that surprise a new user on that page,
   in bullets. These are the A-rules seen from the analyst's side:
   - amber `—` means *not evaluated*, never *pass* (A1);
   - the amber stale banner after any edit (A3);
   - greyed-out fields filled from the library, and `Custom` to override (A5);
   - required dropdowns that start blank on purpose (A6);
   - engagement cleared when the threaded-member type changes (A9);
   - import reporting per row (A10).
5. **Next**: one line naming the next page, linked.

Hard limits: **no paragraph over 3 sentences**; anything tabular goes in a table.

### Voice

| Where | Voice | Example |
|---|---|---|
| Prose (Purpose, What you'll see, Next) | **Imperative**, no "you" | "Pick the nut spec. Material, rated load and engagement fill in and lock. For your own values, set the spec to `Custom`." |
| Field tables (generated from tooltips) | **Reference**: field name, then what it sets | "**Nut spec**: sets material, rated load and engagement from the library (locked). `Custom` unlocks them." |

The tooltip review in phase (b) brings every tooltip into the reference voice.

### Import file formats (hand-written, on the importing page)

Tooltips cannot describe a file, so each import gets a hand-written table: the
file type, the sheet/column layout, units, and what the reader skips.

| Page | File | Layout |
|---|---|---|
| Element Forces | `.xlsx` | One sheet per load case (the sheet name is the load case name); columns `element_id, FX, FY, FZ, MX, MY, MZ`; rows with a blank `element_id` are skipped. **Export Template...** writes this shape |
| Element Mapping | `.csv` / `.txt` | Mapping columns, as the reader expects them (confirm in phase (b)) |

A test pins each documented column list to the reader's, so a changed reader
fails `runTests` until the guide follows.

## 5. Results section (the one page with extra content)

Beyond the template, `Results.html` carries:

- **The 15-check table**, with columns *# · Check · Governing equation · Pass
  rule · NotEvaluated when*. Condensed from `ENGINE_CHECKS.md` "The 15 checks",
  with a link there for derivations.
- **Three rows that are not margins**, called out on their own:
  - **Interaction** reports a ratio `R` and passes when `R ≤ 1`, the opposite
    direction from `MS ≥ 0`. It never governs the worst margin, but a failing
    `R` still fails the summary.
  - **Separation-before-rupture** is a decision, not a number.
  - **Insert external-thread** always reads NotEvaluated. Row 12 carries the
    pull-out.
- **NotEvaluated ≠ pass**: why "ALL CHECKS PASS" never appears while a row is `—`.
- **Reading the Method column**: it names the equation that ran and the basis
  of the allowable.

The table is hand-maintained and small (15 rows). A test pins its row names to
the engine's row names, so adding a check without documenting it fails.

## 6. Visual design

- One `guide.css`, no external fonts, scripts or CDN. It must work offline.
- A left nav matching the rail (sections SETUP / SINGLE JOINT / BULK /
  REFERENCE), top-of-page breadcrumb, a readable measure (~75 characters).
- Colors reuse the app's pass / fail / amber semantics, so the guide and app
  agree on what amber means.
- Light by default, with `prefers-color-scheme: dark` support; `@media print`
  hides the nav.
- Screenshots have alt text (the page name + state) and a max width.
- No JavaScript is required to read any page. Search is left to the browser's
  Ctrl+F.

## 7. Docs-build pipeline

A new script **`matlab/tools/buildUserGuide.m`**, run by Dan on Windows before
each release (it cannot run on the Mac side).

| Step | Output |
|---|---|
| Build `fastenerTool` headless, then drive it into scripted states, reusing the `tGui*` fixture setup | — |
| Load a neutral sample joint (a plain two-plate joint with a nut; no course-book case), so Joint Config and Results show real numbers | — |
| `exportapp` each rail page | `docs/userguide/img/<pageId>.png` |
| Walk each page's component tree; every control with a non-empty `Tooltip` becomes a row. Pair it with its label (the `uilabel` in the same grid row, the column to the left, the `addLabelledText` pattern in `JointConfigPage.m`). Group by the page's collapsible group title | `docs/userguide/fragments/<pageId>-fields.html` |
| Splice each fragment into its `pages/<pageId>.html` between marker comments | updated page HTML |

The output is **committed**, so every guide change shows up as a reviewable diff.

**Consequence:** tooltips become the field documentation. Phase (b) includes a
tooltip review, and from then on a tooltip edit counts as a docs edit.

**Controls without a label or a tooltip**: the script lists them and does not
fail. The drift test (§9) decides what is allowed.

## 8. App integration

| Item | Spec |
|---|---|
| Help > User Guide | Opens `index.html` |
| "?" on every page | One helper on `gui.Page` puts a "?" button in the page header, opening `pages/<pageId>.html`. Pages get it by inheritance, not per-page code |
| Opening | `web(url, "-browser")` with a `file:` URL, which replaces the `winopen` path in `gui.openExternal` for the guide. Must be verified in MATLAB and in the packaged `.exe` on Dan's machine (see risks) |
| Locating files | A single `gui.userGuidePath(pageId)` resolves relative to the app root, with a `ctfroot` branch when `isdeployed`. `data.Library.defaultPath` has the same unfixed gap; fix both the same way |
| Packaging | `mcc ... -a ../docs/userguide`, next to the existing `-a +data/library` (`PRECOMPILE_CHECKLIST.md`) |
| Missing guide | If the file isn't found, show an alert naming the path. Never fail silently |

**Risks**

| Risk | Mitigation |
|---|---|
| `web -browser` behaves differently in a compiled app | Verify in the `.exe` in phase (a). The fallback is `winopen` on the file, which works because §4 uses one file per page and needs no `#anchors` |
| Work-machine browser blocks `file:` URLs | Also caught in phase (a). The fallback is `uihtml` in a figure window |
| `exportapp` on hidden or collapsed groups | The script expands every group before capture |

## 9. Acceptance criteria and tests

| Criterion | Enforced by |
|---|---|
| Every rail page has `pages/<pageId>.html` and a fields fragment | Test: iterate `FastenerApp.pageSpecs` |
| Every tooltip-bearing control appears in its page's committed fragment (**drift test**) | Test: harvest live, compare with the committed fragment. A tooltip added or changed without re-running the build fails `runTests` |
| Every `<img>` and link inside `docs/userguide` resolves | Test: parse the HTML, `isfile` each target |
| The 15-check table matches the engine's row names | Test |
| "?" exists on every page and targets that page's file | Test on the `gui.Page` helper (asserts the URL, doesn't open a browser) |
| No external URLs in the guide (offline) | Test: no `http` in `src`/`href` except citation links in `sources.html` |
| Opens in the packaged `.exe` | `PRECOMPILE_CHECKLIST.md` gains: "Help > User Guide and every '?' open the right page" |

The harvester is shared between the build script and the drift test (one
function, e.g. `gui.harvestFields(page)`), so they can never disagree about
what a field is.

## 10. Removals and doc fixes

| Remove | Replace with |
|---|---|
| `+report/userGuide.m`, `+report/userGuideChapters.m` | `docs/userguide/` |
| `tests/tUserGuide.m` | The tests in §9 (new `tUserGuideHtml.m`) |
| `FastenerApp.onHelpUserGuide` PDF build, progress dialog, `prefdir` cache | Open `index.html` |
| `GUI_SPEC.md` line on Help opening `USER_GUIDE.md` (stale) | The §8 behavior |
| `PRECOMPILE_CHECKLIST.md` user-guide PDF steps | The §9 checklist line |
| `ARCHITECTURE.md` / `README.md` mentions of the PDF guide | Pointer to `docs/userguide/` |

`USER_GUIDE.md` **stays**, as the headless / Command Window doc. Its intro
points to the in-app guide for GUI use.

With the user guide gone, Report Generator is needed only for the calc report.

## 11. Phasing

One push per phase, and a green `runTests` before the next one.

| Phase | Ships | Done when |
|---|---|---|
| **(a) Skeleton** | `docs/userguide/` with CSS, `index.html`, `limits.html`, `sources.html`, `Results.html` (hand-written, including the 15-check table); `gui.userGuidePath`; Help menu rewired; old PDF code and `tUserGuide` deleted; link/image/offline/15-row tests | Dan opens it from Help in MATLAB **and** in a test `.exe` |
| **(b) Build script** | `tools/buildUserGuide.m`, `gui.harvestFields`, screenshots + field fragments for all 11 pages, remaining page templates with Purpose/Next stubs; tooltip review | Dan runs the script; fragments and images committed |
| **(c) "?" links + drift test** | `gui.Page` helper, per-page test, drift test | `runTests` green; every "?" opens its page |
| **(d) Prose pass** | "Purpose" and "What you'll see" for each page, written with Dan one page at a time | Dan signs off each page |

## 12. Resolved decisions (2026-09-22)

| Question | Decision |
|---|---|
| Voice | Imperative prose, reference-style field tables (§4) |
| Course-book (DABJ) walkthrough | **No.** It is not a spec or standard; screenshots use a neutral sample joint (§7) |
| Import file formats | Documented in the guide, on the importing page (§4) |
