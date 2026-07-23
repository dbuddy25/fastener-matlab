function f = makeTemplate(outFile)
%MAKETEMPLATE  Generate the multi-sheet .xlsx bulk-input template (Step 2b).
%   f = data.makeTemplate(outFile) writes a fill-in workbook to outFile
%   (.xlsx) and returns the resolved (absolute) path. Five sheets:
%
%       Joints    — the joint-library table. TWO-ROW header: row 1 is
%                   FRIENDLY display names ("Bolt Size", "Slip Check", ...),
%                   row 2 is the MATLAB column names data.loadJointLibrary
%                   keys on (Bolt, SlipMode, ...). The reader's header-row
%                   auto-detect locks onto row 2, so the friendly row is
%                   purely informational. Rows 3–4 are the two shipped
%                   example rows (templates/joint_library_template.csv):
%                   the DABJ Section 9 class-problem joint and an insert
%                   (Helicoil) joint — so the workbook reproduces §9 as-is.
%       Elements  — the element + forces table (same two-row header idea;
%                   data.loadElements header-auto-detects the MATLAB-name
%                   row, so the friendly row needs no cleanup) with the
%                   three shipped example rows. Example row 1001 carries
%                   the DABJ §9 PER-BOLT limit loads (FZ 5590 / FX 1560 on
%                   the bolt-axis-Z §9 joint), so a fresh template run
%                   through engine.runWorkbook reproduces the published §9
%                   per-bolt margins — the workbook is self-validating.
%       Settings  — Setting | Value | Description. data.loadSettings reads
%                   columns 1–2 (key, value) and ignores everything else,
%                   so the Description column is safe decoration. Seeded
%                   with the DABJ §9 temperatures and factors.
%       Lists     — one column per dropdown source (ThreadedMember,
%                   SlipMode, Boolean, Bolts, Materials — the last two
%                   pulled live from data.Library.load()). Point Excel
%                   Data Validation at these columns (see USER_GUIDE.md).
%       Fields    — the data dictionary: MATLAB Name | Friendly Name |
%                   Description | Units | Valid / default, one row per
%                   Joints/Settings/Elements column. Use it as tooltip
%                   (Input Message) text for Data Validation.
%
%   Example:
%       f  = data.makeTemplate("my_template.xlsx");
%       jl = data.loadJointLibrary(f, data.Library.load());   % Joints sheet
%
%   Joints is written FIRST so plain data.loadJointLibrary(f, lib) — which
%   reads the first sheet — parses it directly.

arguments
    outFile (1,1) string
end

if ~endsWith(lower(outFile), [".xlsx", ".xlsm", ".xls"])
    error("data:makeTemplate:badExtension", ...
        "outFile must be a spreadsheet path ending in .xlsx (got: %s).", outFile);
end
if isfile(outFile)
    delete(outFile);   % start clean so the workbook is exactly these sheets
end

lib = data.Library.load();

J = jointColumns();      % Nx5 {matlab, friendly, description, units, valid/default}
E = elementColumns();
S = settingsRows();      % Nx5 {key, value, description, units, valid/default}

% ---- Joints: friendly row / MATLAB row / two example rows ---------------
jNames = string(J(:, 1))';
C = [J(:, 2)'; J(:, 1)'; ...
     rowFromStruct(dabjExampleRow(),   jNames); ...
     rowFromStruct(insertExampleRow(), jNames)];
writecell(C, outFile, "Sheet", "Joints");

% ---- Elements: friendly row / MATLAB row / three example rows -----------
eNames = string(E(:, 1))';
rows = elementExampleRows();
C = [E(:, 2)'; E(:, 1)'];
for i = 1:numel(rows)
    C = [C; rowFromStruct(rows{i}, eNames)]; %#ok<AGROW>
end
writecell(C, outFile, "Sheet", "Elements");

% ---- Settings: Setting | Value | Description ----------------------------
% Value MUST be column 2 — data.loadSettings reads (col 1, col 2) as
% (key, value); the Description column rides along ignored.
C = [{"Setting", "Value", "Description"}; S(:, 1:3)];
writecell(C, outFile, "Sheet", "Settings");

% ---- Lists: one dropdown-source column each -----------------------------
cols = {["ThreadedMember"; "Nut"; "Insert"; "TappedHole"], ...
        ["SlipMode"; "Ignored"; "SingleFastener"; "Joint"], ...
        ["Boolean"; "TRUE"; "FALSE"], ...
        ["Bolts"; lib.boltKeys()'], ...
        ["Materials"; lib.materialKeys()']};
n = max(cellfun(@numel, cols));
C = repmat({""}, n, numel(cols));
for c = 1:numel(cols)
    v = cols{c};
    for r = 1:numel(v)
        C{r, c} = v(r);
    end
end
writecell(C, outFile, "Sheet", "Lists");

% ---- Fields: the data dictionary ----------------------------------------
hdr = {"MATLAB Name", "Friendly Name", "Description", "Units", "Valid / default"};
C = [hdr; banner("Joints sheet"); J];
C = [C; banner("Settings sheet")];
for i = 1:size(S, 1)
    C = [C; {S{i, 1}, S{i, 1}, S{i, 3}, S{i, 4}, S{i, 5}}]; %#ok<AGROW>
end
C = [C; banner("Elements sheet"); E];
writecell(C, outFile, "Sheet", "Fields");

d = dir(outFile);
f = string(fullfile(d.folder, d.name));
end

% =========================================================================
% Sheet-building helpers
% =========================================================================

function row = rowFromStruct(s, names)
%ROWFROMSTRUCT  1xN cell row: s.(name) per column, "" where absent (blank).
row = cell(1, numel(names));
for i = 1:numel(names)
    if isfield(s, names(i))
        row{i} = s.(names(i));
    else
        row{i} = "";
    end
end
end

function b = banner(txt)
%BANNER  Fields-sheet section separator row.
b = {"— " + string(txt) + " —", "", "", "", ""};
end

% =========================================================================
% Joints sheet: column dictionary (order = sheet column order)
% =========================================================================

function C = jointColumns()
%JOINTCOLUMNS  Nx5 {MATLAB name, friendly name, description, units, valid/default}.
C = {
"Name"                "Joint Name"                  "Unique joint identifier; Elements rows reference it via joint_name. Rows with a blank Name are skipped."                                    "—"          "required"
"Bolt"                "Bolt Size"                   "Bolt thread designation — a library key resolved via lib.bolt()."                                                                          "—"          "required; pick from Lists!Bolts"
"BoltMaterial"        "Bolt Material"               "Bolt material — a library key resolved via lib.material()."                                                                                "—"          "required; pick from Lists!Materials"
"BoltSpec"            "Bolt Spec (optional)"        "Explicit bolt-spec key for the rated ultimate/yield loads; blank = auto-lookup of the library spec matching Bolt + Bolt Material (none found: engine derives At*Ftu)." "—"          "optional"
"FrustumAngle"        "Frustum Angle (deg)"         "Conical pressure-frustum half-angle used in the clamped-stack stiffness model."                                                            "deg"        "blank → 30"
"ThreadsInShear"      "Threads in Shear?"           "TRUE = threads lie in the shear plane (threads-in-shear allowables); FALSE = unthreaded body in the shear plane."                          "TRUE/FALSE" "blank → TRUE (threads in shear)"
"SlipMode"            "Slip Check"                  "How the slip margin is evaluated: Ignored, SingleFastener (per-bolt), or Joint (whole bolt-pattern; needs pattern_id rows = Bolt Count)."   "—"          "blank → SingleFastener; Lists!SlipMode"
"ThreadedMember"      "Threaded Member"             "What the bolt threads into: Nut, Insert (Helicoil), or TappedHole. Selects which member-detail columns apply."                             "—"          "blank → Nut; Lists!ThreadedMember"
"AxialX"              "Axial Dir X"                 "Mark this cell (X or TRUE) when the bolt axis is the FEM X direction. Mark EXACTLY ONE of the three Axial columns."                        "mark"       "none marked → Z"
"AxialY"              "Axial Dir Y"                 "Mark this cell (X or TRUE) when the bolt axis is the FEM Y direction."                                                                     "mark"       "—"
"AxialZ"              "Axial Dir Z"                 "Mark this cell (X or TRUE) when the bolt axis is the FEM Z direction."                                                                     "mark"       "—"
"BoltCount"           "Bolt Count (nf)"             "Number of fasteners in the bolt pattern, nf — used by joint-mode slip."                                                                    "—"          "blank → 1"
"FrictionCoefficient" "Friction Coeff (μ)"          "Coefficient of friction between the faying surfaces, for the slip check."                                                                  "—"          "blank → 0 (slip not evaluated)"
"LoadingPlaneFactor"  "Loading Plane Factor (n)"    "Loading-plane factor n = Llp/L — where the applied load is introduced into the stack (1.0 is conservative)."                               "—"          "blank → 1.0"
"HeadWasherOn"        "Head Washer?"                "TRUE builds a washer under the bolt head from the Head Washer columns; FALSE/blank = no washer."                                           "TRUE/FALSE" "blank → FALSE; Lists!Boolean"
"HeadWasherMaterial"  "Head Washer Material"        "Head-washer material — library key (carried for completeness; washers are rigid in the frustum model)."                                    "—"          "used when Head Washer? is TRUE"
"HeadWasherOD"        "Head Washer OD (in)"         "Head-washer outer diameter (caps the frustum cone diameter)."                                                                              "in"         "blank → frustum governs"
"HeadWasherID"        "Head Washer ID (in)"         "Head-washer inner diameter."                                                                                                               "in"         "optional"
"HeadWasherThickness" "Head Washer Thk (in)"        "Head-washer thickness (adds to the grip)."                                                                                                 "in"         "blank → 0"
};
for k = 1:4
    C = [C; flangeColumns(k)]; %#ok<AGROW>
end
C = [C; {
"NutWasherOn"         "Nut Washer?"                 "TRUE builds a washer under the nut from the Nut Washer columns; FALSE/blank = no washer."                                                  "TRUE/FALSE" "blank → FALSE; Lists!Boolean"
"NutWasherMaterial"   "Nut Washer Material"         "Nut-washer material — library key."                                                                                                        "—"          "used when Nut Washer? is TRUE"
"NutWasherOD"         "Nut Washer OD (in)"          "Nut-washer outer diameter."                                                                                                                "in"         "blank → frustum governs"
"NutWasherID"         "Nut Washer ID (in)"          "Nut-washer inner diameter."                                                                                                                "in"         "optional"
"NutWasherThickness"  "Nut Washer Thk (in)"         "Nut-washer thickness (adds to the grip)."                                                                                                  "in"         "blank → 0"
"NutHeight"           "Nut Height (in)"             "Nut config only: thread engagement length Le (nut height)."                                                                                "in"         "blank → model default"
"NutMaterial"         "Nut Material"                "Nut config only: nut material — library key (nut-thread shear allowable)."                                                                 "—"          "Lists!Materials"
"NutDiameter"         "Nut Bearing Dia (in)"        "Nut config only: nut bearing outer diameter for the under-nut bearing check."                                                              "in"         "blank → not checked"
"HelicoilParentName"  "Helicoil Parent Name"        "Insert config only: name/label of the part the insert is installed in (cosmetic)."                                                         "—"          "optional"
"HelicoilParentMaterial" "Helicoil Parent Material" "Insert config only: parent (host) material — library key (parent-thread shear allowable)."                                                 "—"          "Lists!Materials"
"HelicoilLengthRatio" "Helicoil Length (×D)"        "Insert config only: insert engagement length as a multiple of the bolt nominal diameter (1.5 = 1.5D)."                                     "×D"         "e.g. 1, 1.5, 2"
"NutFactor"           "Nut Factor (K)"              "Torque-to-preload nut factor K (T = K·D·P), NASA-STD-5020B Eq. 24."                                                                        "—"          "blank → 0.2"
"Uncertainty"         "Preload Uncertainty (Γ)"     "Preload uncertainty Γ (± fraction) in the min/max preload equations (NASA-STD-5020B Eq. 3/4/5)."                                           "frac"       "blank → 0.25"
"PreloadLoss"         "Preload Loss (frac)"         "Relaxation/embedment preload loss as a fraction of nominal preload."                                                                       "frac"       "blank → 0.05"
"NominalTorque"       "Nominal Torque (in-lbf)"     "Nominal effective installation torque (above running torque)."                                                                             "in-lbf"     "required (torque control)"
"TorqueTolerance"     "Torque Tolerance (frac)"     "Fractional torque tolerance: a spec of 470 ± 20 in-lbf is 20/470 ≈ 0.0426 (the 5020B c-factors)."                                          "frac"       "blank → 0"
"ThermalRate"         "Thermal Rate (lbf/°C, optional)" "Preload change per °C override; blank/0 = compute from CTE mismatch + joint stiffness."                                                "lbf/°C"     "blank → 0 (computed)"
"FlangeCount"         "Flange Count"                "Number of clamped layers to read (1–4)."                                                                                                   "—"          "blank → inferred from populated Flange Materials"
"BodyLengthInGrip"    "Body Length in Grip (in, optional)" "Unthreaded body (shank) length within the grip, L1 — refines bolt stiffness."                                                       "in"         "blank → derived"
}];
end

function C = flangeColumns(k)
%FLANGECOLUMNS  The six-column dictionary block for clamped layer k.
K = string(k);
C = { ...
"Flange" + K + "Name",      "Flange " + K + " Name",            "Label for clamped layer " + K + " (layer 1 is under the bolt head).",     "—",          "optional"; ...
"Flange" + K + "Material",  "Flange " + K + " Material",        "Layer " + K + " material — library key.",                                  "—",          "required per counted layer; Lists!Materials"; ...
"Flange" + K + "HoleDia",   "Flange " + K + " Hole Dia (in)",   "Clearance-hole diameter in layer " + K + " (bearing / tear-out checks).",  "in",         "blank → not checked"; ...
"Flange" + K + "Thickness", "Flange " + K + " Thickness (in)",  "Layer " + K + " thickness (sums into the grip length).",                   "in",         "blank → 0.1"; ...
"Flange" + K + "Tearout",   "Flange " + K + " Check Tear-out?", "TRUE runs the shear tear-out check on layer " + K + " (needs Edge Dist).", "TRUE/FALSE", "blank → TRUE; Lists!Boolean"; ...
"Flange" + K + "EdgeDist",  "Flange " + K + " Edge Dist (in)",  "Hole center to free edge distance e in layer " + K + ", for tear-out.",    "in",         "blank → not checked"};
end

% =========================================================================
% Joints sheet: the two shipped example rows (mirror the template CSV)
% =========================================================================

function s = dabjExampleRow()
%DABJEXAMPLEROW  The DABJ Section 9 class-problem joint (template row 1).
s = struct();
s.Name = "DABJ Sec. 9 class problem";
s.Bolt = "3/8-24 UNF";               s.BoltMaterial = "A-286";
s.ThreadedMember = "Nut";            s.ThreadsInShear = false;
s.SlipMode = "Joint";                s.AxialZ = "X";
s.BoltCount = 4;                     s.FrictionCoefficient = 0.1;
s.LoadingPlaneFactor = 0.5;
s.NutFactor = 0.15;                  s.Uncertainty = 0.25;
s.PreloadLoss = 0.05;                s.NominalTorque = 470;
s.TorqueTolerance = 0.042553;        s.ThermalRate = 12.978;
s.NutMaterial = "A-286";
s.HeadWasherOn = false;              s.NutWasherOn = false;
s.FlangeCount = 2;
s.Flange1Name = "Upper flange";      s.Flange1Material = "Al 7075-T7351";
s.Flange1Thickness = 0.375;
s.Flange2Name = "Lower flange";      s.Flange2Material = "Al 7075-T7351";
s.Flange2Thickness = 0.375;
end

function s = insertExampleRow()
%INSERTEXAMPLEROW  The Helicoil-insert example joint (template row 2).
s = struct();
s.Name = "Example insert joint";
s.Bolt = "3/8-24 UNF";               s.BoltMaterial = "A-286";
s.BoltSpec = "3/8 A-286 160ksi";
s.ThreadedMember = "Helical Insert"; s.FrustumAngle = 30;
s.ThreadsInShear = true;             s.SlipMode = "Ignored";
s.AxialX = true;
s.BoltCount = 1;                     s.FrictionCoefficient = 0;
s.LoadingPlaneFactor = 1.0;
s.NutFactor = 0.2;                   s.Uncertainty = 0.25;
s.PreloadLoss = 0.05;                s.NominalTorque = 100;
s.TorqueTolerance = 0.1;
s.HelicoilParentName = "Housing";
s.HelicoilParentMaterial = "Al 7075-T7351";
s.HelicoilLengthRatio = 1.5;
s.HeadWasherOn = true;               s.HeadWasherMaterial = "A-286";
s.HeadWasherOD = 0.687;              s.HeadWasherID = 0.391;
s.HeadWasherThickness = 0.063;
s.NutWasherOn = false;
s.FlangeCount = 1;
s.Flange1Name = "Bracket flange";    s.Flange1Material = "Al 7075-T7351";
s.Flange1HoleDia = 0.397;            s.Flange1Thickness = 0.25;
s.Flange1Tearout = true;             s.Flange1EdgeDist = 0.75;
end

% =========================================================================
% Elements sheet: column dictionary + example rows
% =========================================================================

function C = elementColumns()
%ELEMENTCOLUMNS  Nx5 {MATLAB name, friendly name, description, units, valid/default}.
C = {
"element_id" "Element ID"          "FEM element identifier (each element = one bolt)."                                                          "—"          "required"
"joint_name" "Joint Name"          "Which joint definition applies — must match a Name on the Joints sheet."                                    "—"          "required"
"pattern_id" "Pattern ID"          "Physical bolt-pattern tag: rows sharing a pattern_id are one joint instance (joint-mode slip aggregation)." "—"          "blank → joint_name"
"load_case"  "Load Case"           "Load-case label carried into the results."                                                                  "—"          "optional"
"FX"         "Force X (lbf)"       "Element force, FEM X — resolved onto the joint's bolt axis into tension + shear."                           "lbf"        "blank → 0"
"FY"         "Force Y (lbf)"       "Element force, FEM Y."                                                                                      "lbf"        "blank → 0"
"FZ"         "Force Z (lbf)"       "Element force, FEM Z."                                                                                      "lbf"        "blank → 0"
"MX"         "Moment X (in-lbf)"   "Element moment about FEM X (informational for now)."                                                        "in-lbf"     "blank → 0"
"MY"         "Moment Y (in-lbf)"   "Element moment about FEM Y (informational for now)."                                                        "in-lbf"     "blank → 0"
"MZ"         "Moment Z (in-lbf)"   "Element moment about FEM Z (informational for now)."                                                        "in-lbf"     "blank → 0"
"scale"      "Scale Factor"        "Multiplier applied to the forces before resolution (e.g. 3-sigma factor)."                                  "—"          "blank → 1"
"reversible" "Reversible?"         "TRUE = the load can act in both directions (tension taken as abs of the axial component)."                  "TRUE/FALSE" "blank → FALSE; Lists!Boolean"
};
end

function rows = elementExampleRows()
%ELEMENTEXAMPLEROWS  The three shipped example rows (templates/elements_template.csv).
%   Row 1001 carries the DABJ §9 per-bolt limit loads (bolt axis Z: FZ 5590
%   -> PtL, FX 1560 -> PsL) so the template workbook is self-validating —
%   engine.runWorkbook on a fresh template reproduces the §9 per-bolt
%   margins (tests/tWorkbook.m).
r1 = struct("element_id", 1001, "joint_name", "DABJ Sec. 9 class problem", ...
    "pattern_id", "PLATE-1", "load_case", "Liftoff", ...
    "FX", 1560, "FY", 0, "FZ", 5590, "MX", 0, "MY", 0, "MZ", 0, ...
    "scale", 1, "reversible", false);
r2 = struct("element_id", 1002, "joint_name", "DABJ Sec. 9 class problem", ...
    "pattern_id", "PLATE-1", "load_case", "Liftoff", ...
    "FX", -150, "FY", 200, "FZ", -800, "MX", 10, "MY", 5, "MZ", 0, ...
    "scale", 1, "reversible", true);
r3 = struct("element_id", 1003, "joint_name", "Example insert joint", ...
    "load_case", "Landing", "FX", 50, "FY", 120, "FZ", 400, "scale", 1.5, ...
    "reversible", false);
rows = {r1, r2, r3};
end

% =========================================================================
% Settings sheet: rows + dictionary
% =========================================================================

function S = settingsRows()
%SETTINGSROWS  Nx5 {key, value, description, units, valid/default}.
%   Values are the DABJ Section 9 case (matching templates/settings_template.csv).
S = {
"NominalTempC" 20      "Assembly/reference temperature — applied to every joint (ReferenceTemperature)."       "degC" "blank → 20"
"HotTempC"     33.8889 "Maximum expected service temperature — applied to every joint (MaxTemperature)."       "degC" "blank → 20"
"ColdTempC"    6.1111  "Minimum expected service temperature — applied to every joint (MinTemperature)."       "degC" "blank → 20"
"FSU"          1.4     "Ultimate safety factor (tension/shear/bearing rupture checks)."                        "—"    "DABJ §9: 1.4"
"FSY"          1.25    "Yield safety factor."                                                                  "—"    "DABJ §9: 1.25"
"FSSep"        1       "Separation safety factor."                                                             "—"    "DABJ §9: 1.0"
"FSSlip"       1       "Slip safety factor."                                                                   "—"    "DABJ §9: 1.0"
"FFU"          1.15    "Ultimate fitting factor."                                                              "—"    "DABJ §9: 1.15"
"FFY"          1       "Yield fitting factor."                                                                 "—"    "DABJ §9: 1.0"
"FFSep"        1       "Separation fitting factor."                                                            "—"    "DABJ §9: 1.0"
"FFSlip"       1       "Slip fitting factor."                                                                  "—"    "DABJ §9: 1.0"
};
end
