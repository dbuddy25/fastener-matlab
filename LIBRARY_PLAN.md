# Library Tiering and GUI Editing — design notes

> Notes only, written 2026-08-04. **Nothing here is built, and it is
> deliberately NOT next** — see §5 for what comes first and why.
>
> Requirement as stated: the material/hardware library is **admin-controlled**,
> but users can add **custom entries**.

---

## 1. Three tiers

| Tier | Writable by | Lives | Ships |
|---|---|---|---|
| **Seed** | nobody | install directory, read-only | in the repo (`+data/library.json`) |
| **Admin** | admin only | shared/network path, read-only to users | per program |
| **Custom** | the user | user-writable app-data path | never |

Lookup precedence: **Admin > Seed**, with Custom occupying its own namespace
(see §2.1 — it does not sit in this precedence chain at all).

---

## 2. The four rules that matter more than the tiering

### 2.1 A custom entry must never shadow an admin or seed entry

If a user can define `Al 7075-T73` with their own numbers and have it win over
the approved entry, admin control is defeatable by accident. **Block the name
collision at entry** and require a distinct name.

The failure this prevents: two engineers run the same case file and get
different margins, with nothing in either output explaining why.

### 2.2 The tier must travel into the result

A margin computed from a user-invented allowable is not the same evidence as one
computed from an approved allowable, and the report has to say so.

**The pattern already exists in this codebase** — `boltTensileAllowable` reports
whether it used a rated or a derived basis, and the `Decision` strings say
plainly when an assessment ran over an incomplete set. Do the same: every
material carries its tier, and any margin touching a Custom material is marked
as such in `Result`, the reports, and the GUI.

### 2.3 Case files must EMBED custom materials, not reference them

The sharpest trap. If a case file names a custom material and is opened on a
machine that does not have it, the outcomes are (a) a hard failure, or (b) far
worse, a *different* material carrying the same name.

- **Seed and Admin** materials: reference by name + library version (§2.4).
- **Custom** materials: **serialize the full definition inline into the case
  file.** Portability is then unconditional.

Precedent already in the repo: `validation.dabjExample8b` and
`validation.dabjSection9` construct their materials INLINE rather than pulling
from the library, precisely because the book's values differ from the seeded
ones. That is the same mechanism.

### 2.4 The admin library needs a version stamp

Recorded in every case file and every report. Without it, re-running a case from
last year after an allowable was revised returns a different margin and nothing
flags the change. Pair it with a checksum (§4).

---

## 3. Packaging constraint — decide this BEFORE the GUI work, not at Phase 5

A compiled MATLAB standalone **cannot reliably write inside its own install
directory** — on Windows that is typically under `Program Files`, read-only for
a normal user. So:

- the Seed library ships read-only and is **copied out on first run**;
- the Custom library lives in a user-writable path (`%APPDATA%` or equivalent);
- the Admin library is read from a configured path, never written by the app.

This is the same shape as the overlay design above, so building it this way now
costs nothing extra. Discovering it after the GUI writes directly to
`+data/library.json` means reworking the data layer under a shipped tool.

---

## 4. One honest limitation

In a standalone `.exe` with no server, **"admin-controlled" is a convention
backed by file permissions, not access control.** A determined user can point
the tool at their own file. Do not design as though it is enforceable.

What *is* achievable, and what actually matters for an audit, is making
tampering **detectable**: checksum the Admin library at load, record the
checksum and version in every report, and surface a mismatch loudly.

---

## 5. Why this is not next

This is a convenience feature. Ahead of it sit correctness gaps that bound what
the tool can honestly be used for:

| Rank | Item | Why it outranks this |
|---|---|---|
| 1 | **Bolt-bending guard** | `fbu = 0` in every interaction criterion. 5020B §4.4.4 exempts close-tolerance and interference fits — but **nothing checks that condition**, so a clearance-fit or gapped joint reads non-conservatively and SILENTLY. Highest risk, and the cheap fix is detection (refuse or warn on the geometry that needs it), not implementing bending |
| 2 | **Job B — mixed-modulus stiffness** | A steel fitting on an aluminium panel is refused outright; with a temperature excursion the whole analysis errors. Highest value: method is settled and error bounds measured (`STIFFNESS_PLAN.md`) |
| 3 | **Phase 3.4 independent validation** | Every margin is currently checked against fixtures written by the same author as the code. Self-consistency, not independent agreement |
| 4 | **Phase 5 packaging** | Needed before anyone can use it without MATLAB |
| 5 | This document | |

Note the ordering of 1 and 2: **bending is the higher risk, Job B is the higher
value.** A refused joint is a visible, safe failure; a silently unconservative
margin is not. The bending *guard* is small enough that it should not wait
behind Job B.
