function v = toolVersion()
%TOOLVERSION  The tool's version string. THE ONE PLACE IT IS DEFINED.
%   v = toolVersion() returns the semantic version of the Fastener
%   Analysis Tool as a (1,1) string, e.g. "0.1.0".
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
%     MINOR  one per completed build phase/step that lands user-visible
%            capability — Headless Release, GUI complete, and so on.
%     PATCH  fixes and corrections between those.
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

v = "0.1.0";
end
