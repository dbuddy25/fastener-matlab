function file = packageToolbox()
%PACKAGETOOLBOX  Build the .mltbx a colleague installs with a double-click.
%   file = packageToolbox() writes build/FastenerTool_v<version>.mltbx at
%   the repo root and returns its path. See PACKAGING.md.
%
%   The toolbox is the whole matlab/ folder: code, library, templates, the
%   user guide (with its screenshots, if captureUserGuideScreens has been
%   run on this machine), the Calculation Map, examples and tests. The
%   identifier stays fixed, so installing a newer version replaces the
%   older one instead of sitting beside it.
here = fileparts(mfilename("fullpath"));          % .../matlab/tools
src  = fileparts(here);                           % .../matlab
addpath(src);
v = toolVersion();

out = fullfile(fileparts(src), "build");
if ~isfolder(out)
    mkdir(out);
end
file = string(fullfile(out, "FastenerTool_v" + v + ".mltbx"));

opts = matlab.addons.toolbox.ToolboxOptions(src, "fastener-analysis-tool-5020b");
opts.ToolboxName = "Fastener Analysis Tool";
opts.ToolboxVersion = v;
opts.Summary = "NASA-STD-5020B bolted-joint margins of safety, single joint and bulk.";
opts.Description = "Run fastenerTool to open the app. Help > User Guide covers every page.";
% uihtml's sendEventToMATLAB (Calculation Map, R2023a) is the newest API used.
opts.MinimumMatlabRelease = "R2023a";
opts.OutputFile = file;
matlab.addons.toolbox.packageToolbox(opts);
fprintf("Built %s\n", file);
end
