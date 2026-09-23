function bisectExportapp()
%BISECTEXPORTAPP  Find what makes exportapp fail on the last page captured.
%   Temporary diagnostic. Run once and paste the output:
%       bisectExportapp
%   Round 1 showed the Hardware Library page captures fine on its own, so
%   this tests the two things that differ in captureUserGuideScreens:
%   every other page already built, and the sample data loaded.

here = fileparts(mfilename("fullpath"));
src = fileparts(here);
addpath(src);
out = tempname;
mkdir(out);

section("A. No data; every page built first");
app = gui.FastenerApp();
for id = app.pageIds()
    app.navigateTo(id);
end
app.navigateTo("HardwareLibrary");
attempt(app.Fig, "Hardware Library, built last");
app.navigateTo("Project");
attempt(app.Fig, "Project, after all pages built");
delete(app);

section("B. Sample data loaded; Hardware Library before the other pages");
app = gui.FastenerApp();
loadSample(app, src);
app.navigateTo("HardwareLibrary");
attempt(app.Fig, "Hardware Library, data loaded, few pages built");

section("C. As the capture script: data, bulk run, every page built and expanded");
app.navigateTo("BulkAnalysis");
bulk = app.page("BulkAnalysis");
b = bulk.runButton();
b.ButtonPushedFcn(b, []);
for id = app.pageIds()
    app.navigateTo(id);
    p = app.page(id);
    for t = p.collapsedGroups()
        p.expandGroup(t);
    end
end
attempt(app.Fig, "Hardware Library, everything done");
app.navigateTo("Project");
attempt(app.Fig, "Project, everything done");
app.navigateTo("BulkAnalysis");
attempt(app.Fig, "Bulk Analysis, everything done");
fprintf("  open figures: %d\n", numel(findall(groot, "Type", "figure")));
delete(app);

fprintf("\nDone.\n");

    function attempt(fig, label)
        drawnow
        pause(0.5)
        t = tic;
        try
            exportapp(fig, char(fullfile(out, "x.png")));
            fprintf("  OK    %-48s %5.1f s\n", label, toc(t));
        catch err
            fprintf("  FAIL  %-48s %5.1f s  (%s)\n", label, toc(t), err.message);
        end
    end
end

function loadSample(app, src)
s = app.State;
jl = data.loadJointLibrary( ...
    fullfile(src, "templates", "joint_library_template.csv"), s.Library);
s.Joint    = jl(1).Joint;
s.LoadCase = model.LoadCase(Name = "Quasistatic", ...
    BoltTensileLimitLoad = 5590 / 4, BoltShearLimitLoad = 1560 / 4, ...
    JointTensileLimitLoad = 5590, JointShearLimitLoad = 1560);
s.setResult(engine.analyze(s.Joint, s.LoadCase, s.Factors));
s.JointLibrary = struct('Name', {jl.Name}, 'Joint', {jl.Joint});
m = gui.AppState.emptyMapping();
m(1) = gui.AppState.mappingRow("1001", jl(1).Name, "PLATE-1");
m(2) = gui.AppState.mappingRow("1002", jl(1).Name, "PLATE-1");
m(3) = gui.AppState.mappingRow("1003", jl(2).Name);
s.Mapping = m;
el = gui.AppState.emptyElements();
el.Cases(1) = gui.AppState.elementCase("Quasistatic");
el.Cases(2) = gui.AppState.elementCase("Random Vibration", 1.5);
F = gui.AppState.zeroForces();
F1 = F; F1.FX = 1560; F1.FZ = 5590;
F2 = F; F2.FX = -150; F2.FY = 200; F2.FZ = -800; F2.MX = 10; F2.MY = 5;
F3 = F; F3.FX = 50; F3.FY = 120; F3.FZ = 400;
el.Rows(end + 1) = gui.AppState.elementRow("1001", "Quasistatic", F1);
el.Rows(end + 1) = gui.AppState.elementRow("1002", "Quasistatic", F2);
el.Rows(end + 1) = gui.AppState.elementRow("1003", "Random Vibration", F3);
s.Elements = el;
end

function section(t)
fprintf("\n%s\n", t);
end
