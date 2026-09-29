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
% The release fingerprint (toolIntegrity) ships inside the package and is
% removed from the checkout afterwards: there, edits are the point.
toolIntegrity(Write=true, Root=string(src));
fingerprint = fullfile(src, "integrity.json");
removeFingerprint = onCleanup(@() delete(fingerprint)); %#ok<NASGU>
opts.ToolboxFiles = shippedFiles(src);
opts.OutputFile = file;
matlab.addons.toolbox.packageToolbox(opts);
checkPackage(file, src);
fprintf("Built %s\n", file);
end

function checkPackage(file, src)
% Fail the build, not the colleague: every shipped library, template and
% user guide file must be inside the .mltbx (a zip), counted against the
% source folders.
tmp = string(tempname);
cleanup = onCleanup(@() rmdir(tmp, 's'));
inside = replace(string(unzip(file, tmp)), "\", "/");
need = ["+data/library/materials", "+data/library/bolts", "+data/library/nuts", ...
        "+data/library/washers", "+data/library/inserts", "+data/library/boltSpecs", ...
        "templates", "userguide", "calcmap"];
bad = strings(0, 1);
for n = need
    want = numel(dir(fullfile(src, n, "*.*"))) - 2;   % minus . and ..
    got = nnz(contains(inside, "/" + n + "/"));
    if got < want
        bad(end + 1) = sprintf("%s: %d of %d files", n, got, want); %#ok<AGROW>
    end
end
if ~any(endsWith(inside, "/integrity.json"))
    bad(end + 1) = "integrity.json (the release fingerprint) missing";
end
if ~isfile(fullfile(src, "+data", "library", "library.json")) || ...
        ~any(endsWith(inside, "/+data/library/library.json"))
    bad(end + 1) = "+data/library/library.json missing";
end
if ~isempty(bad)
    error("packageToolbox:missingFiles", ...
        "The .mltbx is missing files it must ship:\n  %s", strjoin(bad, newline + "  "));
end
end

function f = shippedFiles(src)
% Every file under src except the developer-only ones.
d = dir(fullfile(src, "**", "*"));
d = d(~[d.isdir]);
f = string({d.folder})' + filesep + string({d.name})';
rel = replace(extractAfter(f, strlength(string(src)) + 1), "\", "/");
devOnly = startsWith(rel, ["tests/", "tools/", "+testing/", "+validation/"]) | ...
    rel == "runTests.m" | startsWith(string({d.name})', ".") | endsWith(rel, ".asv");
f = f(~devOnly);
end
