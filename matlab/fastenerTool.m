function app = fastenerTool()
%FASTENERTOOL  Entry point for the MATLAB fastener analysis tool.
%   Opens the GUI. From the matlab/ folder (or with it on the path):
%
%       fastenerTool             % open the window
%       app = fastenerTool();    % open and keep the app handle
%
%   IT LAUNCHES +gui2, which since GUI step 10 is the only GUI. There was
%   a first-pass +gui package alongside it for the whole rebuild — the
%   rule was that there is never a window with no working tool — and it
%   was deleted once the last page landed. Its final holdout was the
%   Materials & Hardware DB tab, which step 9 rebuilt.
%
%   WHAT THIS USED TO BE, because the gap is worth recording rather than
%   quietly closing: it was a Phase 1 stub that printed a version banner,
%   said "engine not built yet (Phase 1)", and returned. That stayed true
%   in the file long after the engine, the validated single-joint path and
%   both GUIs existed — so the documented entry point did nothing, and the
%   real one was a launch function typed by hand. Found by a dead-code
%   review, 2026-08-13.
%
%   The version banner is kept: it is the one line that tells a user which
%   build they are about to run, and toolVersion() is the single
%   definition of it (stamped on every PDF and workbook the tool writes).

    v = toolVersion();   % THE one definition -- see toolVersion.m
    fprintf("Fastener Analysis Tool (MATLAB) v%s\n", v);
    app = gui2.launch();
end
