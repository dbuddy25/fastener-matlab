function captureUserGuideScreens()
%CAPTUREUSERGUIDESCREENS  Screenshot every rail page into userguide/img/.
%   Run from anywhere in MATLAB, before building the .exe:
%       captureUserGuideScreens
%
%   Each page is captured from a FRESH app holding the sample case (the
%   template joint and forces, not a course-book case); only Bulk Analysis
%   gets a bulk run. One app driven through every page, with the bulk run
%   done, made exportapp fail on every page (Export unsuccessful), so no
%   state is carried between captures. exportapp can take a minute or
%   more per page.
%
%   The images are gitignored: they are build output, bundled by
%   `mcc -a userguide`, and the guide hides any image that is missing.

here = fileparts(mfilename("fullpath"));          % .../matlab/tools
src  = fileparts(here);                           % .../matlab
addpath(src);
out = fullfile(src, "userguide", "img");
if ~isfolder(out)
    mkdir(out);
end

probe = gui.FastenerApp();
ids = probe.pageIds();
delete(probe);

failed = strings(0, 1);
for id = ids
    app = gui.FastenerApp();
    closer = onCleanup(@() delete(app));
    loadSample(app, src);

    if id == "BulkAnalysis"
        app.navigateTo(id);
        bulk = app.page(id);
        runBtn = bulk.runButton();
        runBtn.ButtonPushedFcn(runBtn, []);
        fo = bulk.failOnlyCheck();
        if fo.Value
            fo.Value = false;
            fo.ValueChangedFcn(fo, []);
        end
    end

    app.navigateTo(id);
    p = app.page(id);
    for t = p.collapsedGroups()
        p.expandGroup(t);
    end

    f = char(fullfile(out, id + ".png"));
    t0 = tic;
    msg = "";
    for attempt = 1:2
        drawnow
        pause(0.5)
        try
            exportapp(app.Fig, f);
            msg = "";
            break
        catch err
            msg = string(err.message);
        end
    end
    if msg == ""
        fprintf("saved   %-16s %5.0f s\n", id, toc(t0));
    else
        failed(end + 1) = id + ": " + msg; %#ok<AGROW>
        fprintf("FAILED  %-16s %5.0f s  (%s)\n", id, toc(t0), msg);
    end
    clear closer
end

if isempty(failed)
    fprintf("All %d pages captured.\n", numel(ids));
else
    fprintf("%d page(s) not captured:\n  %s\n", numel(failed), ...
        strjoin(failed.', newline + "  "));
end
end

function loadSample(app, src)
s = app.State;
jl = data.loadJointLibrary( ...
    fullfile(src, "templates", "joint_library_template.csv"), s.Library);

% Single joint: the template joint at element 1001's forces, split over
% its four bolts for the per-bolt loads, joint totals for slip.
s.Joint    = jl(1).Joint;
s.LoadCase = model.LoadCase(Name = "Quasistatic", ...
    BoltTensileLimitLoad  = 5590 / 4, ...
    BoltShearLimitLoad    = 1560 / 4, ...
    JointTensileLimitLoad = 5590, ...
    JointShearLimitLoad   = 1560);
s.setResult(engine.analyze(s.Joint, s.LoadCase, s.Factors));

% Bulk: the template's joints, mapping and forces.
s.JointLibrary = struct('Name', {jl.Name}, 'Joint', {jl.Joint});
m = gui.AppState.emptyMapping();
m(1) = gui.AppState.mappingRow("1001", jl(1).Name, "PLATE-1");
m(2) = gui.AppState.mappingRow("1002", jl(1).Name, "PLATE-1");
m(3) = gui.AppState.mappingRow("1003", jl(2).Name);
s.Mapping = m;

el = gui.AppState.emptyElements();
el.Cases(1) = gui.AppState.elementCase("Quasistatic");
el.Cases(2) = gui.AppState.elementCase("Random Vibration", 1.5);
el.Rows(end + 1) = gui.AppState.elementRow("1001", "Quasistatic", ...
    forces(FX = 1560, FZ = 5590));
el.Rows(end + 1) = gui.AppState.elementRow("1002", "Quasistatic", ...
    forces(FX = -150, FY = 200, FZ = -800, MX = 10, MY = 5));
el.Rows(end + 1) = gui.AppState.elementRow("1003", "Random Vibration", ...
    forces(FX = 50, FY = 120, FZ = 400));
s.Elements = el;
end

function F = forces(opts)
arguments
    opts.FX (1,1) double = 0
    opts.FY (1,1) double = 0
    opts.FZ (1,1) double = 0
    opts.MX (1,1) double = 0
    opts.MY (1,1) double = 0
    opts.MZ (1,1) double = 0
end
F = gui.AppState.zeroForces();
for k = string(fieldnames(opts))'
    F.(k) = opts.(k);
end
end
