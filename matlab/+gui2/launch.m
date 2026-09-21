function app = launch()
%LAUNCH  Open the rebuilt Fastener Analysis Tool GUI.
%   From the matlab/ folder (or with it on the path):
%
%       gui2.launch            % open the window
%       app = gui2.launch();   % open and keep the app handle
%
%   Thin wrapper: constructing gui2.FastenerApp opens the window.
%
%   +gui2 is the GUI (GUI2_SPEC.md).

app = gui2.FastenerApp();
end
