function captureUserGuideScreens()
%CAPTUREUSERGUIDESCREENS  Screenshot every rail page into userguide/img/.
%   Run from anywhere in MATLAB, before building the .exe:
%       captureUserGuideScreens
%
%   Loads the sample joint from templates/ (not a course-book case) plus
%   its template element forces, runs the single-joint and bulk analyses,
%   expands every collapsible group, and saves img/<pageId>.png for each
%   page. The images are gitignored: they are build output, bundled by
%   `mcc -a userguide`, and the guide hides any image that is missing.

here = fileparts(mfilename("fullpath"));          % .../matlab/tools
src  = fileparts(here);                           % .../matlab
addpath(src);
out = fullfile(src, "userguide", "img");
if ~isfolder(out)
    mkdir(out);
end

app = gui.FastenerApp();
closer = onCleanup(@() delete(app));
s = app.State;

jl = data.loadJointLibrary( ...
    fullfile(src, "templates", "joint_library_template.csv"), s.Library);
sample = jl(1);

% Single joint: the template joint at element 1001's forces, split over
% its four bolts for the per-bolt loads, joint totals for slip.
s.Joint    = sample.Joint;
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

app.navigateTo("BulkAnalysis");
bulk = app.page("BulkAnalysis");
runBtn = bulk.runButton();
runBtn.ButtonPushedFcn(runBtn, []);
fo = bulk.failOnlyCheck();
if fo.Value
    fo.Value = false;
    fo.ValueChangedFcn(fo, []);
end

% exportapp fails on a window that extends past the screen, which the
% default 1250x820 does on a scaled laptop display.
scr = get(groot, "ScreenSize");
app.Fig.Position = [20 50 min(1250, scr(3) - 40) min(820, scr(4) - 110)];
figure(app.Fig);
drawnow

failed = strings(0, 1);
for id = app.pageIds()
    app.navigateTo(id);
    p = app.page(id);
    for t = p.collapsedGroups()
        p.expandGroup(t);
    end
    drawnow
    pause(0.5)
    f = char(fullfile(out, id + ".png"));
    msg = "";
    for attempt = 1:2
        try
            exportapp(app.Fig, f);
            msg = "";
            break
        catch err
            msg = string(err.message);
            figure(app.Fig);
            pause(1.5)
        end
    end
    if msg ~= ""
        % exportapp has failed on the six-table Hardware Library page;
        % a screen grab of the window is the fallback.
        try
            frame = getframe(app.Fig);
            imwrite(frame.cdata, f);
            fprintf("saved   %s  (screen grab: exportapp said %s)\n", f, msg);
            continue
        catch err
            msg = msg + "; getframe fallback: " + err.message;
        end
    end
    if msg == ""
        fprintf("saved   %s\n", f);
    else
        failed(end + 1) = id + ": " + msg; %#ok<AGROW>
        fprintf("FAILED  %s  (%s)\n", id, msg);
    end
end
if isempty(failed)
    fprintf("All %d pages captured.\n", numel(app.pageIds()));
else
    fprintf("%d page(s) not captured:\n  %s\n", numel(failed), strjoin(failed.', newline + "  "));
end
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
