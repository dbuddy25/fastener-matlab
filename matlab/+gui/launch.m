function app = launch()
%LAUNCH  Open the Fastener Analysis Tool GUI (Phase 4).
%   The documented entry point for the GUI. From the matlab/ folder (or
%   with it on the path):
%
%       gui.launch            % open the window
%       app = gui.launch();   % open and keep the app handle
%
%   Thin wrapper: constructing gui.FastenerApp opens the window. See the
%   gui.FastenerApp header for what slice 1 covers and the "no analysis
%   logic in the GUI" rule.

app = gui.FastenerApp();
end
