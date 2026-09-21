function app = launch()
%LAUNCH  Open the rebuilt Fastener Analysis Tool GUI.
%   From the matlab/ folder (or with it on the path):
%
%       gui.launch            % open the window
%       app = gui.launch();   % open and keep the app handle
%
%   Thin wrapper: constructing gui.FastenerApp opens the window.
%
%   +gui is the GUI (GUI_SPEC.md).

app = gui.FastenerApp();
end
