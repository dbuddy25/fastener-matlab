function v = toolVersion()
%TOOLVERSION  The tool's version string. THE ONE PLACE IT IS DEFINED.
%   v = toolVersion() returns the semantic version of the Fastener
%   Analysis Tool as a (1,1) string, e.g. "0.3.0".
%
%   WHY A FUNCTION AT THE PATH ROOT rather than a constant on a class.
%   The version is needed by three unrelated layers — the command-line
%   entry point (fastenerTool), the GUI shells (gui.FastenerApp,
%   gui2.AppState) and the report layer — and it had been copy-pasted
%   into each of them. Three literals, no rule saying they must agree,
%   and nothing that would fail if they drifted: a report could then
%   claim one version while the window title claimed another. Root
%   level, package-neutral, so no layer has to depend on another's
%   package just to read it.
%
%   WHAT IT IS NOT. It is deliberately not derived from git, and carries
%   no commit hash or build stamp. This is a single-developer tool; the
%   provenance a margin report needs is "which released version of the
%   tool", which is exactly this string, and a hash would be noise on a
%   title page. It also means the value is identical whether the tool
%   runs from source or from the packaged .exe, with no build step
%   required to make that true.
%
%   VERSIONING RULE (semantic versioning, MAJOR.MINOR.PATCH):
%     MAJOR  reserved for the first validated packaged release (1.0.0)
%            and any later break in analysis behaviour or case-file
%            compatibility.
%     MINOR  one per completed CAPABILITY — something an analyst can now
%            do end to end — rather than per numbered build step. The two
%            are not the same: the single-joint path became usable while
%            steps 6-10 were still untouched, and a version that could not
%            move until step 10 would have stamped every report of that
%            work 0.1.0.
%     PATCH  fixes and corrections between those.
%
%   WHAT EACH VERSION MEANT. Kept here because this string is stamped on
%   every PDF and workbook the tool writes, and a reader holding one of
%   those needs somewhere that says what it was:
%     0.1.0  Foundation, validated engine, headless single-joint analysis.
%     0.2.0  Single joint complete in the GUI: configure, analyse, read the
%            margins, and export or report them. Six of the fifteen checks
%            were computed and not displayed — every view and every export
%            said so.
%     0.3.0  Bolt bending (TFSR 11 / NASA-STD-5020B §4.4.4). The fbu term
%            is computed and carried into the Eq. 20/22 interaction
%            criterion, from a typed moment or from the FE moments the
%            bulk path already resolved; a clearance-or-gapped joint gets
%            an answer instead of NotEvaluated. Eq. 21/23 (plastic
%            bending, needs Fbu) stay out. Bearing-under-head and
%            bolt-thread shear became displayed rows in this line too, so
%            eleven of the fifteen checks are now shown.
%     0.4.0  The BULK path, end to end in the GUI: map FE elements to
%            defined joints, import a force workbook (one load case per
%            sheet), run every element against every load case, read the
%            answer in three tiers, and export the complete result set.
%            All fifteen checks are displayed and exported by this line —
%            nothing is computed and hidden. Still NOT a complete
%            NASA-STD-5020B assessment: yield and separation under
%            combined loading (TFSR 11) are required and unimplemented,
%            and every export says so.
%     0.5.0  THE THREADED-INSERT PATH, corrected and reachable. Two
%            NASA-STD-5020B readings landed here, and BOTH MOVE NUMBERS an
%            analyst may already have reported — read this entry before
%            comparing a 0.5.0 report against an earlier one.
%            (a) §4.4.1 names TWO insert allowables and the tool had them
%            BACKWARDS: it computed pull-out from the parent and printed it
%            under "Insert internal-thread", while the internal-thread row
%            — which p26 requires to come from the item's SPECIFIED
%            strength, not thread-stripping analysis — was never evaluated.
%            The rows are now the right way round, the pull-out row is no
%            longer capped by the rating (the rating is the OTHER
%            allowable), and "the lower value should be used" is applied
%            across the two rather than hidden inside one. gui2 also could
%            not reach either check until this line — it never resolved the
%            insert catalogue — so Heli-Coil joints read differently, and
%            less optimistically, from here on.
%            (b) §4.4.2's Pty-allow is the fastening SYSTEM's, not the
%            bolt's. Eq. 15 and Eq. 17 now take the minimum over the bolt
%            and the internally threaded part. Magnitudes and attribution
%            move; the SIGN never did, so no earlier report ever showed a
%            Pass the standard calls a Fail.
%            TFSR 11's yield and separation under combined loading remain
%            required and unimplemented, and every export still says so.
%
%     0.6.0  EQUATION AUDIT corrections. Every equation in +engine was
%            checked against the source PDFs — NASA-STD-5020B, TM-106943,
%            NASM33537 — and TWO MOVE NUMBERS. Read this before comparing
%            a 0.6.0 report against an earlier one.
%            (a) BOLT THREAD SHEAR was ~29% UNCONSERVATIVE. The area was
%            computed as 0.75·pi·E·Le — TM-106943 Eq. 76's INTERNAL-thread
%            coefficient on the PITCH diameter — while the row cited
%            Eq. 63, which prints 5·pi·Le·D_minor,int/8 on the minor
%            diameter of the mating internal thread. The old form was
%            declared in a comment but justified as "one consistent area
%            basis", which does not hold: the same substitution is
%            conservative on the internal side and unconservative on this
%            one. That row now reads LOWER, and can newly govern.
%            (b) THERMAL PRELOAD ignored washers while the bolt stiffness
%            spanned them. TM-106943 Eq. 10 carries one L, shared by its
%            bolt and joint terms. The error was exactly
%            (alpha_washer - alpha_bolt)·t_washer and vanishes when they
%            match; with steel washers under an A-286 bolt the old form ran
%            ~17% HIGH, so thermal preload now reads slightly LOWER there.
%            Also: an unset material CTE used to default to ZERO — read as
%            "does not expand" — and now defaults to NaN, so a thermal run
%            with a coefficient missing REFUSES and names what to fix
%            instead of returning a confident number. A joint that used to
%            analyse may now ask for a library update; that is the point.
%            Citations corrected throughout (Fsy = Fty/sqrt(3) is 5020B
%            Eq. 63; the rupture margin is Eq. 7, not Eq. 10). Two audit
%            findings against shipped behaviour were investigated and
%            REJECTED — the §4.4.2 yield and Figure 8 system allowables are
%            both correct as shipped; see COMPLIANCE.md.
%
%   THIS IS NOT THE CASE-FILE FORMAT VERSION, and the two must never be
%   tied together. gui2.AppState.CaseFormat
%   ("fastener-analysis-matlab-v1") changes only when the saved-case
%   schema breaks, which is rare and unrelated to tool releases; the
%   hardware library's own schemaVersion is independent again. Bumping
%   this string must never invalidate a user's saved cases.
%
%   Consumers: fastenerTool, gui.FastenerApp, gui2.AppState,
%   report.singleJointReport, report.exportResults.

v = "0.6.0";
end
