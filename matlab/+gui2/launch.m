function app = launch()
%LAUNCH  Open the rebuilt Fastener Analysis Tool GUI.
%   From the matlab/ folder (or with it on the path):
%
%       gui2.launch            % open the window
%       app = gui2.launch();   % open and keep the app handle
%
%   Thin wrapper: constructing gui2.FastenerApp opens the window.
%
%   +gui2 is the second-pass GUI (GUI2_SPEC.md). It is built alongside the
%   first-pass +gui, and BOTH stay launchable until the last page lands —
%   gui.launch remains the working tool while this one is incomplete. Case
%   files interchange freely: both read and write the same
%   "fastener-analysis-matlab-v1" container.

app = gui2.FastenerApp();
end
