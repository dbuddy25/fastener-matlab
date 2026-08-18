function app = launch()
%LAUNCH  Open the rebuilt Fastener Analysis Tool GUI.
%   From the matlab/ folder (or with it on the path):
%
%       gui2.launch            % open the window
%       app = gui2.launch();   % open and keep the app handle
%
%   Thin wrapper: constructing gui2.FastenerApp opens the window.
%
%   +gui2 is the second-pass GUI (GUI2_SPEC.md), and since GUI step 10 the
%   only one. It was built alongside a first-pass +gui package with both
%   kept launchable until the last page landed, so there was never a window
%   with no working tool; +gui was deleted once that condition was met. The
%   case container is unchanged by any of that —
%   "fastener-analysis-matlab-v1", the same format both builds wrote.

app = gui2.FastenerApp();
end
