%RUN_BULK_EXAMPLE  Headless bulk analysis, end to end (Phase 3.6 reference).
%   The "how to use the tool with no GUI" script: loads the bundled
%   template tables (the joint template's first row is the DABJ Sec. 9
%   class problem; the settings template carries the global temperatures
%   and the DABJ safety/fitting factors), runs the whole pipeline in one
%   call via engine.runBulk (library load -> parse joints -> parse
%   settings -> apply global temps -> parse elements -> analyze ->
%   export), writes bulk_results.xlsx next to this script (Results sheet
%   + a Summary sheet with Pass/Fail/Error counts), and prints a one-line
%   summary.
%
%   To analyze your own hardware, copy the three templates from
%   matlab/templates/, fill them in, and point the calls below at
%   your copies:
%       T = engine.runBulk("my_joints.csv", "my_elements.csv", ...
%                          "my_settings.csv", "margins.xlsx");
%
%   Run from anywhere — paths resolve relative to this script, and the
%   source folder is added to the path automatically.

exampleDir = fileparts(mfilename("fullpath"));   % .../matlab/examples
matlabDir  = fileparts(exampleDir);              % .../matlab
addpath(matlabDir);                              % +model/+data/+engine/+report

jointFile    = fullfile(matlabDir, "templates", "joint_library_template.csv");
elementsFile = fullfile(matlabDir, "templates", "elements_template.csv");
settingsFile = fullfile(matlabDir, "templates", "settings_template.csv");
outFile      = fullfile(exampleDir, "bulk_results.xlsx");

T = engine.runBulk(jointFile, elementsFile, settingsFile, outFile);

fprintf("%d elements analyzed, worst margin %.3f — results written to %s\n", ...
    height(T), min(T.WorstMargin), outFile);
