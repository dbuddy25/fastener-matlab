# Packaging — sending the tool to a colleague

The tool ships as a **MATLAB toolbox file (`.mltbx`)**. Your colleague
double-clicks it, MATLAB installs it as an Add-On with the path set, and they
type `fastenerTool`. There is no `.exe`: users run it inside MATLAB.

## 1. Build it (you)

In MATLAB, from the repo's `matlab/` folder:

```matlab
rehash path                  % OneDrive: make sure MATLAB sees every file
runTests                     % full suite green first
addpath tools
captureUserGuideScreens      % optional: puts screenshots in the guide
packageToolbox
```

Output: `build/FastenerTool_v0.7.0.mltbx` at the repo root (git-ignored).
Bump `toolVersion.m` before building a release that changes numbers, so a
report always names the build that made it.

## 2. What to send

| Send | Why |
|---|---|
| `FastenerTool_v0.7.0.mltbx` | The whole tool |
| The note in section 4 | Install steps and what to try |
| Optionally `dabj9_answer_key.json` (from `makeAnswerKeyCase`) | A known case to open first |

Nothing else. The reference PDFs are not included (most are copyrighted);
Help → References lists them and can open the colleague's own copies.

## 3. What your colleague needs

| Need | Detail |
|---|---|
| MATLAB | R2023a or newer (built and tested on R2026a) |
| Toolboxes | None for the analysis. **MATLAB Report Generator** only for Save PDF Report |
| Excel | Not required: exports are written without Excel |

## 4. Note to send with it

> **Fastener Analysis Tool v0.7.0 — for testing**
>
> 1. Double-click `FastenerTool_v0.7.0.mltbx`. MATLAB opens and installs it
>    (Add-Ons). Accept the prompt.
> 2. In the Command Window, type `fastenerTool`.
> 3. **Help → User Guide** explains every page. **? Help for this page** (status
>    bar, bottom right) opens the section for the page you're on.
> 4. Try a joint you know the answer to. Check the margins against your own
>    numbers, then **Export Table…** and **Save PDF Report…** on Results.
> 5. Send back: anything wrong, anything confusing, and the version from
>    **Help → About**.
>
> Your custom library entries are saved in your MATLAB user folder
> (`Documents\MATLAB\fastener_library.json`), not inside the toolbox, so they
> survive updates. To update, install the newer `.mltbx`; it replaces this one.
> To remove, **Home → Add-Ons → Manage Add-Ons**.

## 5. Checks before sending

- [ ] `runTests`: 0 failed.
- [ ] Install the `.mltbx` on your own machine, **restart MATLAB**, and from any
      folder that is *not* the repo: `fastenerTool`, open the answer-key case,
      Analyze, Help → User Guide, Help → Calculation Map. (This proves the
      toolbox carries everything, not your repo on the path.)
- [ ] Uninstall it again (Manage Add-Ons) so it doesn't shadow your repo copy.

If the installed copy and your repo are both on the path, MATLAB uses
whichever comes first, a confusing way to test the wrong code. Uninstall
after checking.
