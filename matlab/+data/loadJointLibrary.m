function jl = loadJointLibrary(file, lib)
%LOADJOINTLIBRARY  Read a joint-table (.csv/.xlsx) into model.Joint objects.
%   jl = data.loadJointLibrary(file, lib) reads a joint-definition table
%   (one row per joint) and returns a struct array with fields:
%       Name   (1,1) string      — the row's Name column
%       Joint  (1,1) model.Joint — the fully-built joint
%
%   `lib` is a data.Library; the Bolt / BoltMaterial / BoltSpec /
%   NutMaterial / HelicoilParentMaterial / {Head,Nut}WasherMaterial /
%   Flange{k}Material columns hold LIBRARY KEYS resolved via lib.bolt(key)
%   / lib.material(key) / lib.boltSpec(key).
%
%   HEADER-ROW AUTO-DETECT: the reader scans the top of the sheet for the
%   row whose cells best match the known column-name set (case-insensitive)
%   and treats it as the header; data starts on the next row. Rows ABOVE
%   the header (e.g. a friendly-name banner row) are ignored, so the same
%   reader accepts both a plain single-header CSV (row 1 is the header) and
%   a decorated workbook with a display row above the MATLAB names.
%
%   Column schema (case-insensitive names; a template with the exact
%   headers lives at templates/joint_library_template.csv — the first row
%   is the DABJ Section 9 class-problem joint). Optional columns may be
%   omitted entirely or left blank per-row; blanks keep the +model
%   defaults. Rows with an empty Name are skipped.
%
%   Identity + bolt:
%       Name                 -> Joint.Name (required; blank row skipped)
%       Bolt                 -> lib.bolt(key) -> Joint.Bolt (required)
%       BoltMaterial         -> lib.material(key) -> Joint.BoltMaterial (required)
%       BoltSpec             -> lib.boltSpec(key) -> Joint.BoltRatedUltimateLoad
%                               / BoltRatedYieldLoad (optional EXPLICIT
%                               override). When blank, the rated loads are
%                               AUTO-LOOKED-UP: if the library has a
%                               boltSpec whose bolt+material keys match this
%                               row's Bolt+BoltMaterial
%                               (lib.boltSpecFor), its rated loads are used;
%                               otherwise they stay NaN (engine derives).
%
%   Configuration:
%       ThreadedMember       -> type text: "Nut" (default), "Insert" /
%                               "Helicoil" / "Helical Insert", "Tapped" /
%                               "TappedHole" / "Tapped Hole"
%       FrustumAngle         -> Joint.FrustumAngle, deg (blank -> 30)
%       ThreadsInShear       -> logical -> Joint.ShearPlane
%                               (TRUE -> ThreadsInShear, FALSE -> BodyInShear)
%       SlipMode             -> "Ignored" / "SingleFastener" / "Joint"
%                               ("Disabled" accepted as a legacy alias)
%       AxialX/AxialY/AxialZ -> Joint.BoltAxis. Mark EXACTLY ONE cell (any
%                               nonblank mark — "X", TRUE, 1). None marked
%                               -> default Z; more than one -> error.
%       BoltCount            -> Joint.BoltCount (nf)
%       FrictionCoefficient  -> Joint.FrictionCoefficient (mu)
%       LoadingPlaneFactor   -> Joint.LoadingPlaneFactor (n)
%       BodyLengthInGrip     -> Joint.BodyLengthInGrip, in (optional)
%
%   Preload (Method is always TorqueControl):
%       NutFactor            -> PreloadSpec.NutFactor (K)
%       Uncertainty          -> PreloadSpec.Uncertainty (Gamma)
%       PreloadLoss          -> PreloadSpec.RelaxationFraction
%       NominalTorque        -> PreloadSpec.NominalTorque, in-lbf
%       TorqueTolerance      -> PreloadSpec.TorqueTolerance (fraction;
%                               blank -> 0)
%       ThermalRate          -> PreloadSpec.ThermalRate, lbf/degC (optional;
%                               blank -> 0 = compute from CTE/stiffness)
%
%   Threaded member details (used per the ThreadedMember type):
%       NutHeight            -> (Nut) ThreadedMember.EngagementLength, in
%       NutMaterial          -> (Nut) lib.material(key) -> ThreadedMember.Material
%       NutDiameter          -> (Nut) ThreadedMember.BearingDiameter, in
%       HelicoilParentName   -> (Insert) ThreadedMember.HostName
%       HelicoilParentMaterial -> (Insert) lib.material(key) -> ThreadedMember.Material
%       HelicoilLengthRatio  -> (Insert) ThreadedMember.EngagementLength
%                               = ratio x Joint.Bolt.NominalDiameter
%
%   Washers ({W} = HeadWasher or NutWasher; built ONLY when {W}On is TRUE,
%   else the model default = no washer):
%       {W}On                -> gate (logical)
%       {W}Material          -> lib.material(key) -> Washer.Material
%       {W}OD / {W}ID / {W}Thickness -> Washer.OuterDiameter /
%                               InnerDiameter / Thickness, in
%
%   Flange stack (k = 1..4):
%       FlangeCount          -> layers to read (optional; blank -> inferred
%                               from the populated Flange{k}Material columns)
%       Flange{k}Name        -> FlangeLayer.Name
%       Flange{k}Material    -> lib.material(key) -> FlangeLayer.Material
%       Flange{k}HoleDia     -> FlangeLayer.HoleDiameter, in
%       Flange{k}Thickness   -> FlangeLayer.Thickness, in
%       Flange{k}Tearout     -> FlangeLayer.CheckShearTearout (logical)
%       Flange{k}EdgeDist    -> FlangeLayer.EdgeDistance, in
%
%   TEMPERATURES ARE GLOBAL: the joint table carries no temperature columns.
%   NominalTempC/HotTempC/ColdTempC live in the Settings file
%   (data.loadSettings) and engine.runBulk applies them to every Joint
%   before analysis; joints parsed here keep the model default (20 degC).
%
%   Extra (unrecognized) columns are ignored.
%
%   Example:
%       lib = data.Library.load();
%       jl  = data.loadJointLibrary("my_joints.csv", lib);
%       jl(1).Joint    % -> model.Joint, ready for engine.analyze

arguments
    file (1,1) string
    lib  (1,1) data.Library
end

if ~isfile(file)
    error("data:loadJointLibrary:fileNotFound", ...
        "Joint library file not found: %s", file);
end

raw = readcell(file, "DatetimeType", "text");
[hdrRow, names] = detectHeader(raw, file);

jl = struct("Name", {}, "Joint", {});
for r = hdrRow+1:size(raw, 1)
    name = getText(raw, names, r, "Name", "");
    if strlength(name) == 0
        continue   % blank Name -> not a joint row
    end
    jl(end+1) = struct("Name", name, ...
                       "Joint", buildJoint(raw, names, r, lib, name)); %#ok<AGROW>
end
end

% =========================================================================
% Header-row auto-detect
% =========================================================================

function [hdrRow, names] = detectHeader(raw, file)
%DETECTHEADER  Find the row whose cells best match the known column names.
%   Scans the top of the sheet, scores each row by how many of its cells
%   are (case-insensitive) known column names, and picks the best. This
%   makes the reader tolerant of decoration rows (titles, friendly names)
%   above the real header; a plain single-header CSV scores row 1 best.
known = knownColumns();
nScan = min(size(raw, 1), 25);   % the header must live near the top
best = 0;
hdrRow = 0;
for r = 1:nScan
    score = 0;
    for c = 1:size(raw, 2)
        t = cellText(raw{r, c});
        if strlength(t) > 0 && any(strcmpi(known, t))
            score = score + 1;
        end
    end
    if score > best
        best = score;
        hdrRow = r;
    end
end
if best < 3
    error("data:loadJointLibrary:noHeader", ...
        "No header row found in %s — no row matches the joint-table column names (Name, Bolt, BoltMaterial, ...). See templates/joint_library_template.csv.", ...
        file);
end
names = strings(1, size(raw, 2));
for c = 1:size(raw, 2)
    names(c) = cellText(raw{hdrRow, c});
end
end

function cols = knownColumns()
%KNOWNCOLUMNS  Every recognized column name (the header-detection set).
cols = ["Name", "Bolt", "BoltMaterial", "BoltSpec", ...
        "ThreadedMember", "FrustumAngle", "ThreadsInShear", "SlipMode", ...
        "AxialX", "AxialY", "AxialZ", ...
        "BoltCount", "FrictionCoefficient", "LoadingPlaneFactor", ...
        "NutFactor", "Uncertainty", "PreloadLoss", "NominalTorque", ...
        "TorqueTolerance", "ThermalRate", "BodyLengthInGrip", ...
        "NutHeight", "NutMaterial", "NutDiameter", ...
        "HelicoilParentName", "HelicoilParentMaterial", "HelicoilLengthRatio", ...
        "HeadWasherOn", "HeadWasherMaterial", "HeadWasherOD", ...
        "HeadWasherID", "HeadWasherThickness", ...
        "NutWasherOn", "NutWasherMaterial", "NutWasherOD", ...
        "NutWasherID", "NutWasherThickness", ...
        "FlangeCount"];
for k = 1:4
    cols = [cols, "Flange" + k + ["Name", "Material", "HoleDia", ...
            "Thickness", "Tearout", "EdgeDist"]]; %#ok<AGROW>
end
end

function t = cellText(v)
%CELLTEXT  Trimmed string of a readcell cell; "" for non-text/missing.
if ischar(v) || isstring(v)
    t = strtrim(string(v));
    if ismissing(t)
        t = "";
    end
else
    t = "";
end
end

% =========================================================================
% Row -> model.Joint
% =========================================================================

function j = buildJoint(raw, names, r, lib, name)
% ---- bolt + bolt material (required library keys) -----------------------
boltKey = getText(raw, names, r, "Bolt", "");
matKey  = getText(raw, names, r, "BoltMaterial", "");
if strlength(boltKey) == 0 || strlength(matKey) == 0
    error("data:loadJointLibrary:missingKey", ...
        "Row ""%s"": the Bolt and BoltMaterial columns are required (library keys).", name);
end
b  = lib.bolt(boltKey);
bm = lib.material(matKey);

% ---- spec-rated allowables: explicit BoltSpec, else auto-lookup ---------
ratedUlt = NaN;
ratedYld = NaN;
specKey = getText(raw, names, r, "BoltSpec", "");
if strlength(specKey) > 0
    s = lib.boltSpec(specKey);              % explicit override
else
    s = lib.boltSpecFor(boltKey, matKey);   % auto: match bolt+material; [] if none
end
if ~isempty(s)
    ratedUlt = s.RatedUltimateLoad;
    ratedYld = s.RatedYieldLoad;
end

% ---- threaded member ----------------------------------------------------
tmType = parseMemberType(getText(raw, names, r, "ThreadedMember", "Nut"), name);
tm = model.ThreadedMember(Type = tmType);
switch tmType
    case model.ThreadedMemberType.Nut
        v = getNum(raw, names, r, "NutHeight", NaN);
        if ~isnan(v), tm.EngagementLength = v; end
        k = getText(raw, names, r, "NutMaterial", "");
        if strlength(k) > 0, tm.Material = lib.material(k); end
        v = getNum(raw, names, r, "NutDiameter", NaN);
        if ~isnan(v), tm.BearingDiameter = v; end
    case model.ThreadedMemberType.Insert
        tm.HostName = getText(raw, names, r, "HelicoilParentName", "");
        k = getText(raw, names, r, "HelicoilParentMaterial", "");
        if strlength(k) > 0, tm.Material = lib.material(k); end
        v = getNum(raw, names, r, "HelicoilLengthRatio", NaN);
        if ~isnan(v), tm.EngagementLength = v * b.NominalDiameter; end
    otherwise
        % TappedHole: type only (parent-material columns come later)
end

% ---- preload spec (torque-controlled) -----------------------------------
ps = model.PreloadSpec(Method = model.PreloadMethod.TorqueControl);
v = getNum(raw, names, r, "NutFactor", NaN);
if ~isnan(v), ps.NutFactor = v; end
v = getNum(raw, names, r, "Uncertainty", NaN);
if ~isnan(v), ps.Uncertainty = v; end
v = getNum(raw, names, r, "PreloadLoss", NaN);
if ~isnan(v), ps.RelaxationFraction = v; end
v = getNum(raw, names, r, "NominalTorque", NaN);
if ~isnan(v), ps.NominalTorque = v; end
v = getNum(raw, names, r, "TorqueTolerance", NaN);
if ~isnan(v), ps.TorqueTolerance = v; end   % blank -> model default 0
v = getNum(raw, names, r, "ThermalRate", NaN);
if ~isnan(v), ps.ThermalRate = v; end       % blank -> model default 0

% ---- flange stack -------------------------------------------------------
nFl = getNum(raw, names, r, "FlangeCount", NaN);
if isnan(nFl)
    nFl = 0;   % infer: highest populated Flange{k}Material column
    for k = 1:4
        if strlength(getText(raw, names, r, "Flange" + k + "Material", "")) > 0
            nFl = k;
        end
    end
end
layers = model.FlangeLayer.empty(1, 0);
for k = 1:nFl
    fmKey = getText(raw, names, r, "Flange" + k + "Material", "");
    if strlength(fmKey) == 0
        error("data:loadJointLibrary:missingFlange", ...
            "Row ""%s"": FlangeCount is %d but Flange%dMaterial is empty.", ...
            name, nFl, k);
    end
    fl = model.FlangeLayer(Material = lib.material(fmKey));
    t = getText(raw, names, r, "Flange" + k + "Name", "");
    if strlength(t) > 0, fl.Name = t; end
    v = getNum(raw, names, r, "Flange" + k + "Thickness", NaN);
    if ~isnan(v), fl.Thickness = v; end
    v = getNum(raw, names, r, "Flange" + k + "HoleDia", NaN);
    if ~isnan(v), fl.HoleDiameter = v; end
    v = getNum(raw, names, r, "Flange" + k + "EdgeDist", NaN);
    if ~isnan(v), fl.EdgeDistance = v; end
    if hasVal(raw, names, r, "Flange" + k + "Tearout")
        fl.CheckShearTearout = getLogical(raw, names, r, "Flange" + k + "Tearout", true);
    end
    layers(end+1) = fl; %#ok<AGROW>
end

% ---- assemble the Joint (name-value pairs so the constructor validates) --
nv = {"Name", name, "Bolt", b, "BoltMaterial", bm, "FlangeStack", layers, ...
      "ThreadedMember", tm, "PreloadSpec", ps, ...
      "BoltAxis", parseAxialColumns(raw, names, r, name)};
if ~isnan(ratedUlt)
    nv = [nv, {"BoltRatedUltimateLoad", ratedUlt, "BoltRatedYieldLoad", ratedYld}];
end
v = getNum(raw, names, r, "BoltCount", NaN);
if ~isnan(v), nv = [nv, {"BoltCount", v}]; end
v = getNum(raw, names, r, "FrictionCoefficient", NaN);
if ~isnan(v), nv = [nv, {"FrictionCoefficient", v}]; end
v = getNum(raw, names, r, "LoadingPlaneFactor", NaN);
if ~isnan(v), nv = [nv, {"LoadingPlaneFactor", v}]; end
if hasVal(raw, names, r, "ThreadsInShear")
    if getLogical(raw, names, r, "ThreadsInShear", true)
        nv = [nv, {"ShearPlane", model.ShearPlaneCondition.ThreadsInShear}];
    else
        nv = [nv, {"ShearPlane", model.ShearPlaneCondition.BodyInShear}];
    end
end
sm = getText(raw, names, r, "SlipMode", "");
if strlength(sm) > 0
    nv = [nv, {"SlipMode", parseSlipMode(sm, name)}];
end
v = getNum(raw, names, r, "FrustumAngle", NaN);
if ~isnan(v), nv = [nv, {"FrustumAngle", v}]; end
v = getNum(raw, names, r, "BodyLengthInGrip", NaN);
if ~isnan(v), nv = [nv, {"BodyLengthInGrip", v}]; end
w = washerFrom(raw, names, r, "HeadWasher", lib);
if ~isempty(w), nv = [nv, {"HeadWasher", w}]; end
w = washerFrom(raw, names, r, "NutWasher", lib);
if ~isempty(w), nv = [nv, {"NutWasher", w}]; end

j = model.Joint(nv{:});
end

% =========================================================================
% Field parsers
% =========================================================================

function t = parseMemberType(txt, name)
%PARSEMEMBERTYPE  "Nut" (default) / "Insert" ("Helicoil" / "Helical Insert")
%   / "TappedHole" ("Tapped" / "Tapped Hole"). Case/spacing-insensitive.
s = lower(erase(strtrim(txt), [" ", "-", "_"]));
if s == "" || s == "nut"
    t = model.ThreadedMemberType.Nut;
elseif contains(s, "insert") || contains(s, "helicoil") || contains(s, "helical")
    t = model.ThreadedMemberType.Insert;
elseif startsWith(s, "tapped")
    t = model.ThreadedMemberType.TappedHole;
else
    error("data:loadJointLibrary:badMemberType", ...
        "Row ""%s"": unknown ThreadedMember ""%s"" (expected Nut, Insert/Helicoil, or TappedHole).", ...
        name, txt);
end
end

function m = parseSlipMode(txt, name)
%PARSESLIPMODE  "Ignored" / "SingleFastener" / "Joint" (spacing/case-insensitive;
%   "Disabled" accepted as a legacy alias for Ignored).
s = lower(erase(strtrim(txt), [" ", "-", "_"]));
switch s
    case {"ignored", "disabled"}   % "disabled" = legacy alias
        m = model.SlipMode.Ignored;
    case {"joint", "jointslip"}
        m = model.SlipMode.Joint;
    case {"single", "singlefastener", "singlefastenerslip"}
        m = model.SlipMode.SingleFastener;
    otherwise
        error("data:loadJointLibrary:badSlipMode", ...
            "Row ""%s"": unknown SlipMode ""%s"" (expected Ignored, SingleFastener, or Joint).", ...
            name, txt);
end
end

function a = parseAxialColumns(raw, names, r, name)
%PARSEAXIALCOLUMNS  Joint.BoltAxis from the AxialX/AxialY/AxialZ mark cells.
%   A cell is "marked" when it holds any nonblank mark that is not an
%   explicit no (FALSE/0/no). Exactly one mark expected; none -> default Z;
%   more than one -> error.
axList = [model.BoltAxis.X, model.BoltAxis.Y, model.BoltAxis.Z];
cols   = ["AxialX", "AxialY", "AxialZ"];
marked = false(1, 3);
for i = 1:3
    marked(i) = isMarked(raw, names, r, cols(i));
end
n = nnz(marked);
if n == 0
    a = model.BoltAxis.Z;   % model default bolt axis
elseif n == 1
    a = axList(marked);
else
    error("data:loadJointLibrary:multipleAxes", ...
        "Row ""%s"": %d of the AxialX/AxialY/AxialZ cells are marked (%s) — mark exactly one (any nonblank mark, e.g. ""X"" or TRUE).", ...
        name, n, strjoin(cols(marked), ", "));
end
end

function tf = isMarked(raw, names, r, col)
%ISMARKED  True when the cell holds a nonblank mark ("X", TRUE, 1, ...)
%   that is not an explicit no (FALSE, 0, no, n, f).
v = getval(raw, names, r, col, []);
if isempty(v)
    tf = false;
elseif islogical(v)
    tf = v;
elseif isnumeric(v)
    tf = v ~= 0;
elseif isstring(v)
    s = lower(strtrim(v));
    tf = ~any(s == ["false", "f", "no", "n", "0", ""]);
else
    tf = false;
end
end

function w = washerFrom(raw, names, r, prefix, lib)
%WASHERFROM  model.Washer from the {prefix}On/Material/OD/ID/Thickness
%   columns when {prefix}On is TRUE; [] (no washer) otherwise.
if ~getLogical(raw, names, r, prefix + "On", false)
    w = [];
    return
end
w = model.Washer();
k = getText(raw, names, r, prefix + "Material", "");
if strlength(k) > 0, w.Material = lib.material(k); end
v = getNum(raw, names, r, prefix + "OD", NaN);
if ~isnan(v), w.OuterDiameter = v; end
v = getNum(raw, names, r, prefix + "ID", NaN);
if ~isnan(v), w.InnerDiameter = v; end
v = getNum(raw, names, r, prefix + "Thickness", NaN);
if ~isnan(v), w.Thickness = v; end
end

% =========================================================================
% Cell-grid access primitives (case-insensitive columns, blanks -> default)
% =========================================================================

function v = getval(raw, names, r, name, default)
%GETVAL  Raw cell value; `default` when the column is absent or the cell blank.
idx = find(strcmpi(names, name), 1);
if isempty(idx)
    v = default;
    return
end
v = raw{r, idx};
if isa(v, "missing")
    v = default;
    return
end
if ischar(v), v = string(v); end
if isstring(v) && (ismissing(v) || strlength(strtrim(v)) == 0)
    v = default;
elseif isnumeric(v) && isscalar(v) && isnan(v)
    v = default;
end
end

function tf = hasVal(raw, names, r, name)
%HASVAL  True when the column exists and the cell holds a non-blank value.
tf = ~isempty(getval(raw, names, r, name, []));
end

function s = getText(raw, names, r, name, default)
%GETTEXT  Trimmed string value ("" family -> default).
v = getval(raw, names, r, name, string(default));
s = strtrim(string(v));
if ismissing(s)
    s = string(default);
end
end

function x = getNum(raw, names, r, name, default)
%GETNUM  Numeric value; text cells are str2double'd (bad text errors).
v = getval(raw, names, r, name, default);
if isstring(v)
    x = str2double(v);
    if isnan(x)
        error("data:loadJointLibrary:badNumber", ...
            "Column ""%s"": cannot parse ""%s"" as a number.", name, v);
    end
elseif islogical(v)
    x = double(v);
else
    x = double(v);
end
end

function tf = getLogical(raw, names, r, name, default)
%GETLOGICAL  Logical from logical/numeric/text (TRUE/FALSE, yes/no, 1/0).
v = getval(raw, names, r, name, default);
if islogical(v)
    tf = v;
elseif isnumeric(v)
    if isnan(v)
        tf = logical(default);
    else
        tf = v ~= 0;
    end
elseif isstring(v)
    s = lower(strtrim(v));
    if any(s == ["true", "t", "yes", "y", "1"])
        tf = true;
    elseif any(s == ["false", "f", "no", "n", "0"])
        tf = false;
    else
        error("data:loadJointLibrary:badLogical", ...
            "Column ""%s"": cannot parse ""%s"" as a logical (use TRUE/FALSE).", name, v);
    end
else
    tf = logical(default);
end
end
