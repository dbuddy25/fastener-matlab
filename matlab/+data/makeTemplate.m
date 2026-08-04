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
%                   example rows (templates/joint_library_template.csv): a
%                   sample four-bolt SHCS/nut joint ("Sample four-bolt
%                   SHCS/nut joint") and an insert (Helicoil) joint, both
%                   built from REAL catalog hardware (NAS1351 3/8-24, A286,
%                   Al 7075-T7351) — NOT the DABJ Section 9 validation
%                   fixture, which library.json no longer ships (see
%                   validation.dabjSection9). The demo configuration
%                   (torque, factors, bolt count, ...) still mirrors that
%                   class problem, but the computed margins are
%                   illustrative, not the published answer key. Both rows
%                   carry a BodyLengthInGrip (and the nut row a NutHeight)
%                   so bolt stiffness — and everything downstream of it
%                   (phi, thermal CTE-mismatch preload, the Fig. 8
%                   rupture branch) — actually resolves on the nut row; see
%                   sampleNutJointRow's own comment for the geometry and
%                   engine.stiffness's Nut-only guard for why the insert
%                   row's BodyLengthInGrip does not (yet) do the same.
%       Elements  — the element + forces table (same two-row header idea;
%                   data.loadElements header-auto-detects the MATLAB-name
%                   row, so the friendly row needs no cleanup) with the
%                   three shipped example rows. Example row 1001 carries
%                   representative per-bolt loads (FZ 5590 / FX 1560 on the
%                   bolt-axis-Z sample joint) so a fresh template run
%                   through engine.runWorkbook analyzes cleanly end to end
%                   (tests/tWorkbook.m) — a structural smoke test, not an
%                   answer-key reproduction.
%       Settings  — Setting | Value | Description. data.loadSettings reads
%                   columns 1–2 (key, value) and ignores everything else,
%                   so the Description column is safe decoration. Seeded
%                   with the DABJ §9 factors/temperatures as representative
%                   defaults (independent of the Joints/Elements hardware).
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
%       f  = data.makeTemplate("analysis_template.xlsx");
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
     rowFromStruct(sampleNutJointRow(), jNames); ...
     rowFromStruct(insertExampleRow(),  jNames)];
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
"NutHeight"           "Nut Height (in)"             "Nut config only: thread engagement length Le (nut height). Feeds the nut-thread-shear allowable (engine.marginNutStrength) and, only when BOTH Bolt.Length and BodyLengthInGrip are blank, the simplified bolt-length fallback for stiffness (NASA-STD-5020B §4.7.4). There is no other default: blank leaves EngagementLength unset and Nut Strength reports NotEvaluated." "in"         "blank → Nut Strength NotEvaluated"
"NutMaterial"         "Nut Material"                "Nut config only: nut material — library key (nut-thread shear allowable)."                                                                 "—"          "Lists!Materials"
"NutDiameter"         "Nut Bearing Dia (in)"        "Nut config only: nut bearing outer diameter for the under-nut bearing check."                                                              "in"         "blank → not checked"
"HelicoilParentName"  "Helicoil Parent Name"        "Insert config only: name/label of the part the insert is installed in (cosmetic)."                                                         "—"          "optional"
"HelicoilParentMaterial" "Helicoil Parent Material" "Insert config only: parent (host) material — library key (parent-thread shear allowable)."                                                 "—"          "Lists!Materials"
"HelicoilLengthRatio" "Helicoil Length (×D)"        "Insert config only: insert engagement length as a multiple of the bolt nominal diameter (1.5 = 1.5D)."                                     "×D"         "e.g. 1, 1.5, 2"
"HelicoilRatedLoad"   "Helicoil Rated Load (lbf)"   "Insert config only: manufacturer-rated pull-out load. Acts as a ceiling on the ultimate criterion above the NASA-STD-5020B §4.4.1 parent-material area form (engine.marginInsert), which is always computed from the insert catalogue (StiPitchDiameter) rather than analyst-typed." "lbf" "blank → 0"
"NutFactor"           "Nut Factor (K)"              "Torque-to-preload nut factor K (T = K·D·P), NASA-STD-5020B Eq. 24."                                                                        "—"          "blank → 0.2"
"Uncertainty"         "Preload Uncertainty (Γ)"     "Preload uncertainty Γ (± fraction) in the min/max preload equations (NASA-STD-5020B Eq. 3/4/5)."                                           "frac"       "blank → 0.25"
"PreloadLoss"         "Preload Loss (frac)"         "Relaxation/embedment preload loss as a fraction of nominal preload."                                                                       "frac"       "blank → 0.05"
"NominalTorque"       "Nominal Torque (in-lbf)"     "Nominal effective installation torque (above running torque)."                                                                             "in-lbf"     "required (torque control)"
"TorqueTolerance"     "Torque Tolerance (frac)"     "Fractional torque tolerance: a spec of 470 ± 20 in-lbf is 20/470 ≈ 0.0426 (the 5020B c-factors)."                                          "frac"       "blank → 0"
"FlangeCount"         "Flange Count"                "Number of clamped layers to read (1–4)."                                                                                                   "—"          "blank → inferred from populated Flange Materials"
"BodyLengthInGrip"    "Body Length in Grip (in)"   "Unthreaded body (shank) length within the grip, L1 — the shank/thread split engine.stiffness needs to compute bolt stiffness Kb (and, from it, phi, Eq. 9, and the thermal CTE-mismatch preload change). None of the shipped catalog bolts carry a Length or ThreadLength, so the two alternate routes (overall Bolt.Length minus ThreadLength; or ThreadedMember.EngagementLength + Bolt.Pitch + Bolt.ThreadLength) are never available from library data alone — this column is the ONLY practical way to supply L1. Leaving it blank does not fall back to a computed value: stiffness (and everything that needs it — phi, the Fig. 8 rupture branch of Tension-Ultimate, and the CTE-mismatch thermal preload change, TM-106943 Eq. 10) reports NotEvaluated. Nut configuration only for now — engine.stiffness defers the insert/tapped-hole frustum form regardless of this column (Phase 3.1 later)." "in" "required for stiffness (Nut config); blank → NotEvaluated"
}];
% No STI pitch diameter column above: the parent tapped-hole thread-shear
% pitch diameter (ThreadedMember.StiPitchDiameter) is auto-resolved from
% the insert catalogue by this row's own Bolt thread size
% (data.Library.insertFor) -- a catalogue lookup, not analyst input. NaN
% when the catalogue has no entry for that size (e.g. #0-80/#5-44). See
% data.loadJointLibrary.
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

function s = sampleNutJointRow()
%SAMPLENUTJOINTROW  Sample four-bolt SHCS/nut joint (template row 1).
%   Configuration (torque, factors, bolt count, flange layout) mirrors the
%   DABJ Section 9 class problem, but the hardware keys are REAL catalog
%   parts (NAS1351 3/8-24, A286, Al 7075-T7351) -- library.json no longer
%   ships the DABJ validation fixture (see validation.dabjSection9, which
%   now builds that fixture's geometry inline). Renamed off the DABJ name
%   entirely (it used to be called "DABJ Sec. 9 class problem") because a
%   name promising the book's answer key, attached to different hardware
%   (NAS1351/A286 vs. the book's own bolt spec) and different derived
%   allowables, is actively misleading -- anyone comparing this row's
%   margins to the book will get different numbers and reasonably
%   conclude the tool is wrong. No catalog boltSpec covers this
%   bolt+material pairing, so BoltSpec is left blank: the auto-lookup
%   documented in jointColumns' "Bolt Spec (optional)" row misses, and
%   BoltRatedUltimateLoad/Yield stay NaN (engine derives them from At*Ftu/
%   Fty at analysis time) -- itself a realistic demonstration of that
%   fallback path.
%
%   BodyLengthInGrip / NutHeight (added so this row's stiffness actually
%   resolves -- see jointColumns' BodyLengthInGrip row for why blank
%   cannot be derived for any catalog bolt):
%     Grip = Flange1Thickness + Flange2Thickness = 0.75 in, no washers, so
%     the washer-inclusive clamped length Lbolt = 0.75 in too.
%     BodyLengthInGrip (L1) = 0.50 in: ThreadsInShear is FALSE on this row
%     (the UNTHREADED shank, not the threads, is assumed to cross the
%     shear plane at the Flange1/Flange2 interface, 0.375 in into the
%     grip) -- L1 must clear that interface with margin, and 0.50 in
%     leaves L2 = Lbolt - L1 = 0.25 in of thread run into the grip toward
%     the nut, a plausible amount for a 3/8-24 SHCS at this grip. (L1 is a
%     geometry CHOICE for this demo joint, not a spec value -- no catalog
%     bolt carries Length/ThreadLength, so nothing here claims otherwise.)
%     NutHeight = 0.328 in: a representative 3/8-24 finished-hex-nut
%     height (~21/64 in, e.g. NASM/AN315-pattern nuts), so
%     engine.marginNutStrength's nut-thread-shear mode also resolves
%     instead of reporting NotEvaluated. It does not change the system
%     Tension-Ultimate allowable here: the nut mode's computed ultimate
%     (Fsu*As = 93,400 psi * 0.75*pi*0.3479*0.328 in^2 ~= 25,100 lbf) is
%     well above the bolt-derived 14,052.8 lbf, so the bolt mode still
%     governs the system minimum -- see tests/tBulk.m for the numeric
%     consequences of L1 on the Tension-Ultimate rupture branch.
s = struct();
s.Name = "Sample four-bolt SHCS/nut joint";
s.Bolt = "NAS1351 3/8-24";           s.BoltMaterial = "A286";
s.ThreadedMember = "Nut";            s.ThreadsInShear = false;
s.SlipMode = "Joint";                s.AxialZ = "X";
s.BoltCount = 4;                     s.FrictionCoefficient = 0.1;
s.LoadingPlaneFactor = 0.5;
s.NutFactor = 0.15;                  s.Uncertainty = 0.25;
s.PreloadLoss = 0.05;                s.NominalTorque = 470;
s.TorqueTolerance = 0.042553;
s.BodyLengthInGrip = 0.50;           s.NutHeight = 0.328;
s.NutMaterial = "A286";
s.HeadWasherOn = false;              s.NutWasherOn = false;
s.FlangeCount = 2;
s.Flange1Name = "Upper flange";      s.Flange1Material = "Al 7075-T7351";
s.Flange1Thickness = 0.375;
s.Flange2Name = "Lower flange";      s.Flange2Material = "Al 7075-T7351";
s.Flange2Thickness = 0.375;
end

function s = insertExampleRow()
%INSERTEXAMPLEROW  The Helicoil-insert example joint (template row 2).
%   Same catalog-hardware repointing as sampleNutJointRow (real NAS1351/
%   A286/Al 7075-T7351 keys, not the DABJ fixture). BoltSpec is left blank
%   for the same reason: no catalog boltSpec exists for this bolt+material
%   pairing, so the row demonstrates the auto-lookup-miss fallback rather
%   than the explicit-override path.
%
%   BodyLengthInGrip: grip = Flange1Thickness = 0.25 in; washers add
%   HeadWasherThickness 0.063 in (no nut washer), so the washer-inclusive
%   clamped length Lbolt = 0.313 in. L1 = 0.15 in is chosen consistent
%   with ThreadsInShear = TRUE on this row (the THREAD, not the shank, is
%   assumed to cross the Flange1 far face 0.25 in into the grip -- so L1
%   must stay short of that interface, leaving the last 0.10 in before the
%   interface already threaded). Populated for the same reason as the nut
%   row's BodyLengthInGrip (a blank cell would still misleadingly read as
%   "derived"). It now DOES feed stiffness: engine.stiffness computes the
%   threaded-in (Insert/TappedHole) frustum via the shortened grip
%   L = t1 + D/2, so L1 reaches kb exactly as it does on the nut row.
%   NutHeight does not apply to an insert
%   configuration (see HelicoilLengthRatio below for its analog).
%
%   HelicoilRatedLoad: an illustrative demo number, not a catalog lookup --
%   the NASM33537 insert catalogue (data.Library's insertFor) publishes
%   tapped-hole GEOMETRY only (no rated-load column; see that catalogue's
%   own header), so it is still entered directly as a "joint design choice
%   supplied once" (engine.boltSizingSweep's phrasing). This row's
%   StiPitchDiameter, by contrast, IS catalog-derived (lib.insertFor by
%   this row's own Bolt thread size — see data.loadJointLibrary); no
%   column exists for it, and ThreadedMember.ShearEngagementArea likewise
%   has no column: engine.marginInsert derives the NASA-STD-5020B Section
%   4.4.1 parent-material area itself from StiPitchDiameter, with the
%   rated load acting as a ceiling on the ultimate criterion only -- so
%   this row exercises the full insert pull-out check end to end, unlike
%   sampleNutJointRow's insert-adjacent fields.
s = struct();
s.Name = "Example insert joint";
s.Bolt = "NAS1351 3/8-24";           s.BoltMaterial = "A286";
s.ThreadedMember = "Helical Insert"; s.FrustumAngle = 30;
s.ThreadsInShear = true;             s.SlipMode = "Ignored";
s.AxialX = true;
s.BoltCount = 1;                     s.FrictionCoefficient = 0;
s.LoadingPlaneFactor = 1.0;
s.NutFactor = 0.2;                   s.Uncertainty = 0.25;
s.PreloadLoss = 0.05;                s.NominalTorque = 100;
s.TorqueTolerance = 0.1;
s.BodyLengthInGrip = 0.15;
s.HelicoilParentName = "Housing";
s.HelicoilParentMaterial = "Al 7075-T7351";
s.HelicoilLengthRatio = 1.5;
s.HelicoilRatedLoad = 2600;
s.HeadWasherOn = true;               s.HeadWasherMaterial = "A286";
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
"joint_name" "Joint Name"          "Which joint definition applies — must match a Name on the Joints sheet. Optional: blank rows are kept and mapped in the GUI's Element Mapping tab; headless runs (runBulk/runWorkbook) need it filled." "—" "optional (headless needs it)"
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
%   Row 1001 carries representative per-bolt loads (bolt axis Z: FZ 5590 ->
%   axial, FX 1560 -> shear -- values borrowed from DABJ Sec. 9, same as
%   the joint row's torque/factors/bolt count) so a fresh template run
%   through engine.runWorkbook analyzes cleanly end to end (tests/tWorkbook.m)
%   -- a structural smoke test; the exact DABJ Section 9 answer key is
%   pinned in code by validation.dabjSection9, independent of this demo
%   hardware.
r1 = struct("element_id", 1001, "joint_name", "Sample four-bolt SHCS/nut joint", ...
    "pattern_id", "PLATE-1", "load_case", "Liftoff", ...
    "FX", 1560, "FY", 0, "FZ", 5590, "MX", 0, "MY", 0, "MZ", 0, ...
    "scale", 1, "reversible", false);
r2 = struct("element_id", 1002, "joint_name", "Sample four-bolt SHCS/nut joint", ...
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
