function file = packageToolbox(args)
%PACKAGETOOLBOX  Build the .mltbx a colleague installs with a double-click.
%   file = packageToolbox() recaptures the user guide's screenshots
%   (captureUserGuideScreens, several minutes), then writes
%   build/FastenerTool_v<version>.mltbx at the repo root and returns its
%   path. See PACKAGING.md.
%   file = packageToolbox(Screens=false) keeps the screenshots already in
%   userguide/img, for a quick rebuild when no page changed.
%
%   Recapturing by default means a release never ships screenshots of an
%   older build: the images are gitignored, so nothing else keeps them in
%   step with the pages.
%
%   The toolbox is what a user runs: code, library, templates, the user
%   guide and its screenshots, the Calculation Map and the examples.
%   Developer-only files stay out: tests/, tools/, +testing, +validation
%   (the course-book answer-key cases) and runTests.m. The
%   identifier stays fixed, so installing a newer version replaces the
%   older one instead of sitting beside it.
arguments
    args.Screens (1,1) logical = true
end
if args.Screens
    captureUserGuideScreens();
end

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
opts.ToolboxFiles = shippedFiles(src);
opts.OutputFile = file;
matlab.addons.toolbox.packageToolbox(opts);
fprintf("Built %s\n", file);
end

function f = shippedFiles(src)
% Every file under src except the developer-only ones.
d = dir(fullfile(src, "**", "*"));
d = d(~[d.isdir]);
f = string(fullfile({d.folder}, {d.name}))';
rel = replace(extractAfter(f, strlength(string(src)) + 1), "\", "/");
devOnly = startsWith(rel, ["tests/", "tools/", "+testing/", "+validation/"]) | ...
    rel == "runTests.m" | startsWith(string({d.name})', ".") | endsWith(rel, ".asv");
f = f(~devOnly);
end
