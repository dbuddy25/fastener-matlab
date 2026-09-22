function app = fastenerTool()
%FASTENERTOOL  Entry point for the MATLAB fastener analysis tool.
%   Opens the GUI. From the matlab/ folder (or with it on the path):
%
%       fastenerTool             % open the window
%       app = fastenerTool();    % open and keep the app handle
%
%   It launches +gui.
%
%   The version banner is kept: it is the one line that tells a user which
%   build they are about to run, and toolVersion() is the single
%   definition of it (stamped on every PDF and workbook the tool writes).

    v = toolVersion();   % THE one definition -- see toolVersion.m
    fprintf("Fastener Analysis Tool (MATLAB) v%s\n", v);
    app = gui.launch();
end
