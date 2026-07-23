function jl = loadJointLibrary(file, lib)
%LOADJOINTLIBRARY  Read a joint-library table into model.Joint objects (Phase 3.5b).
%   jl = data.loadJointLibrary(file, lib) reads a joint-definition table
%   (.csv or .xlsx, one row per joint) and returns a struct array with
%   fields:
%       Name   (1,1) string      — the row's Name column
%       Joint  (1,1) model.Joint — the fully-built joint
%
%   `lib` is a data.Library; the Bolt / BoltMaterial / BoltSpec /
%   HostMaterial / Flange{k}Material columns hold LIBRARY KEYS resolved via
%   lib.bolt(key) / lib.material(key) / lib.boltSpec(key).
%
%   Column schema (case-insensitive names; a template with the exact
%   headers lives at templates/joint_library_template.csv — the
%   first row is the DABJ Section 9 class-problem joint). Optional columns
%   may be omitted entirely or left blank per-row; blanks keep the +model
%   defaults. Rows with an empty Name are skipped.
%
%       Name                 -> Joint.Name (required; blank row skipped)
%       Bolt                 -> lib.bolt(key) -> Joint.Bolt (required)
%       BoltMaterial         -> lib.material(key) -> Joint.BoltMaterial (required)
%       BoltSpec             -> lib.boltSpec(key) -> Joint.BoltRatedUltimateLoad
%                               / BoltRatedYieldLoad (optional; NaN -> derive)
%       ThreadedMember       -> type text: "Nut" (default), "Insert" /
%                               "Helical Insert", "Tapped" / "Tapped Hole"
%       HostMaterial         -> lib.material(key) -> ThreadedMember.Material
%       ThreadEngagement     -> Le, in — a plain number, OR a diameter
%                               multiple ("1.5D", "1.5 D", "1.5xD") scaled
%                               by Bolt.NominalDiameter
%       InsertRating         -> ThreadedMember.RatedUltimateLoad, lbf
%                               (Heli-Coil rated pull-out for inserts;
%                               spec-rated Pult for nuts)
%       Torque               -> PreloadSpec.NominalTorque, in-lbf
%                               (Method is always TorqueControl)
%       TorqueTolerance      -> PreloadSpec.TorqueTolerance (fraction)
%       NutFactor            -> PreloadSpec.NutFactor (K)
%       Uncertainty          -> PreloadSpec.Uncertainty (Gamma)
%       Relaxation           -> PreloadSpec.RelaxationFraction
%       ThermalRate          -> PreloadSpec.ThermalRate, lbf/degC — thermal
%                               preload change per degree (blank/0 -> compute
%                               from CTE/stiffness in engine.preload)
%       SeparationCritical   -> PreloadSpec.SeparationCritical (logical)
%       AssemblyTempC        -> Joint.ReferenceTemperature, degC
%       HotTempC / ColdTempC -> Joint.MaxTemperature / MinTemperature, degC
%       BoltCount            -> Joint.BoltCount (nf)
%       FrictionCoefficient  -> Joint.FrictionCoefficient (mu)
%       LoadingPlaneFactor   -> Joint.LoadingPlaneFactor (n)
%       ThreadsInShear       -> logical -> Joint.ShearPlane
%                               (true -> ThreadsInShear, false -> BodyInShear)
%       SlipMode             -> "Ignored" / "SingleFastener" / "Joint"
%                               ("Disabled" accepted as a legacy alias)
%       BoltAxis             -> "X" / "Y" / "Z"
%       FrustumAngle         -> Joint.FrustumAngle, deg
%       BodyLengthInGrip     -> Joint.BodyLengthInGrip, in
%       HeadBearingDiameter  -> Joint.Bolt.HeadBearingDiameter, in
%       HeadWasherThickness / HeadWasherOD -> Joint.HeadWasher (model.Washer)
%       NutWasherThickness  / NutWasherOD  -> Joint.NutWasher
%       FlangeCount          -> layers to read, 1-4 (blank -> inferred from
%                               the populated Flange{k}Material columns)
%       Flange{k}Material    -> lib.material(key) -> FlangeLayer.Material
%       Flange{k}Thickness   -> FlangeLayer.Thickness, in
%       Flange{k}HoleDia     -> FlangeLayer.HoleDiameter, in
%       Flange{k}EdgeDist    -> FlangeLayer.EdgeDistance, in
%       Flange{k}Tearout     -> FlangeLayer.CheckShearTearout (logical)
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

T = readtable(file, "TextType", "string");
names = string(T.Properties.VariableNames);

jl = struct("Name", {}, "Joint", {});
for r = 1:height(T)
    name = getText(T, names, r, "Name", "");
    if strlength(name) == 0
        continue   % blank Name -> not a joint row
    end
    jl(end+1) = struct("Name", name, ...
                       "Joint", buildJoint(T, names, r, lib, name)); %#ok<AGROW>
end
end

% =========================================================================
% Row -> model.Joint
% =========================================================================

function j = buildJoint(T, names, r, lib, name)
% ---- bolt + bolt material (required library keys) -----------------------
boltKey = getText(T, names, r, "Bolt", "");
matKey  = getText(T, names, r, "BoltMaterial", "");
if strlength(boltKey) == 0 || strlength(matKey) == 0
    error("data:loadJointLibrary:missingKey", ...
        "Row ""%s"": the Bolt and BoltMaterial columns are required (library keys).", name);
end
b  = lib.bolt(boltKey);
bm = lib.material(matKey);

hbd = getNum(T, names, r, "HeadBearingDiameter", NaN);
if ~isnan(hbd)
    b.HeadBearingDiameter = hbd;
end

% ---- spec-rated allowables (optional) -----------------------------------
ratedUlt = NaN;
ratedYld = NaN;
specKey = getText(T, names, r, "BoltSpec", "");
if strlength(specKey) > 0
    s = lib.boltSpec(specKey);
    ratedUlt = s.RatedUltimateLoad;
    ratedYld = s.RatedYieldLoad;
end

% ---- threaded member ----------------------------------------------------
tm = model.ThreadedMember( ...
    Type = parseMemberType(getText(T, names, r, "ThreadedMember", "Nut")));
hostKey = getText(T, names, r, "HostMaterial", "");
if strlength(hostKey) > 0
    tm.Material = lib.material(hostKey);
end
le = parseEngagement(getval(T, names, r, "ThreadEngagement", NaN), ...
                     b.NominalDiameter, name);
if ~isnan(le)
    tm.EngagementLength = le;
end
rating = getNum(T, names, r, "InsertRating", NaN);
if ~isnan(rating)
    tm.RatedUltimateLoad = rating;
end

% ---- preload spec (torque-controlled) -----------------------------------
ps = model.PreloadSpec(Method = model.PreloadMethod.TorqueControl);
v = getNum(T, names, r, "Torque", NaN);
if ~isnan(v), ps.NominalTorque = v; end
v = getNum(T, names, r, "TorqueTolerance", NaN);
if ~isnan(v), ps.TorqueTolerance = v; end
v = getNum(T, names, r, "NutFactor", NaN);
if ~isnan(v), ps.NutFactor = v; end
v = getNum(T, names, r, "Uncertainty", NaN);
if ~isnan(v), ps.Uncertainty = v; end
v = getNum(T, names, r, "Relaxation", NaN);
if ~isnan(v), ps.RelaxationFraction = v; end
v = getNum(T, names, r, "ThermalRate", NaN);
if ~isnan(v), ps.ThermalRate = v; end
if hasVal(T, names, r, "SeparationCritical")
    ps.SeparationCritical = getLogical(T, names, r, "SeparationCritical", false);
end

% ---- flange stack -------------------------------------------------------
nFl = getNum(T, names, r, "FlangeCount", NaN);
if isnan(nFl)
    nFl = 0;   % infer: highest populated Flange{k}Material column
    for k = 1:4
        if strlength(getText(T, names, r, "Flange" + k + "Material", "")) > 0
            nFl = k;
        end
    end
end
layers = model.FlangeLayer.empty(1, 0);
for k = 1:nFl
    fmKey = getText(T, names, r, "Flange" + k + "Material", "");
    if strlength(fmKey) == 0
        error("data:loadJointLibrary:missingFlange", ...
            "Row ""%s"": FlangeCount is %d but Flange%dMaterial is empty.", ...
            name, nFl, k);
    end
    fl = model.FlangeLayer(Material = lib.material(fmKey));
    v = getNum(T, names, r, "Flange" + k + "Thickness", NaN);
    if ~isnan(v), fl.Thickness = v; end
    v = getNum(T, names, r, "Flange" + k + "HoleDia", NaN);
    if ~isnan(v), fl.HoleDiameter = v; end
    v = getNum(T, names, r, "Flange" + k + "EdgeDist", NaN);
    if ~isnan(v), fl.EdgeDistance = v; end
    if hasVal(T, names, r, "Flange" + k + "Tearout")
        fl.CheckShearTearout = getLogical(T, names, r, "Flange" + k + "Tearout", true);
    end
    layers(end+1) = fl; %#ok<AGROW>
end

% ---- assemble the Joint (name-value pairs so the constructor validates) --
nv = {"Name", name, "Bolt", b, "BoltMaterial", bm, "FlangeStack", layers, ...
      "ThreadedMember", tm, "PreloadSpec", ps};
if ~isnan(ratedUlt)
    nv = [nv, {"BoltRatedUltimateLoad", ratedUlt, "BoltRatedYieldLoad", ratedYld}];
end
v = getNum(T, names, r, "BoltCount", NaN);
if ~isnan(v), nv = [nv, {"BoltCount", v}]; end
v = getNum(T, names, r, "FrictionCoefficient", NaN);
if ~isnan(v), nv = [nv, {"FrictionCoefficient", v}]; end
v = getNum(T, names, r, "LoadingPlaneFactor", NaN);
if ~isnan(v), nv = [nv, {"LoadingPlaneFactor", v}]; end
v = getNum(T, names, r, "AssemblyTempC", NaN);
if ~isnan(v), nv = [nv, {"ReferenceTemperature", v}]; end
v = getNum(T, names, r, "HotTempC", NaN);
if ~isnan(v), nv = [nv, {"MaxTemperature", v}]; end
v = getNum(T, names, r, "ColdTempC", NaN);
if ~isnan(v), nv = [nv, {"MinTemperature", v}]; end
if hasVal(T, names, r, "ThreadsInShear")
    if getLogical(T, names, r, "ThreadsInShear", true)
        nv = [nv, {"ShearPlane", model.ShearPlaneCondition.ThreadsInShear}];
    else
        nv = [nv, {"ShearPlane", model.ShearPlaneCondition.BodyInShear}];
    end
end
sm = getText(T, names, r, "SlipMode", "");
if strlength(sm) > 0
    nv = [nv, {"SlipMode", parseSlipMode(sm, name)}];
end
ax = getText(T, names, r, "BoltAxis", "");
if strlength(ax) > 0
    nv = [nv, {"BoltAxis", parseBoltAxis(ax, name)}];
end
v = getNum(T, names, r, "FrustumAngle", NaN);
if ~isnan(v), nv = [nv, {"FrustumAngle", v}]; end
v = getNum(T, names, r, "BodyLengthInGrip", NaN);
if ~isnan(v), nv = [nv, {"BodyLengthInGrip", v}]; end
w = washerFrom(T, names, r, "HeadWasher");
if ~isempty(w), nv = [nv, {"HeadWasher", w}]; end
w = washerFrom(T, names, r, "NutWasher");
if ~isempty(w), nv = [nv, {"NutWasher", w}]; end

j = model.Joint(nv{:});
end

% =========================================================================
% Field parsers
% =========================================================================

function t = parseMemberType(txt)
%PARSEMEMBERTYPE  "Nut" (default) / "Insert" / "Helical Insert" / "Tapped [Hole]".
s = lower(erase(strtrim(txt), [" ", "-", "_"]));
if contains(s, "insert")
    t = model.ThreadedMemberType.Insert;
elseif startsWith(s, "tapped")
    t = model.ThreadedMemberType.TappedHole;
else
    t = model.ThreadedMemberType.Nut;
end
end

function le = parseEngagement(v, nominalDiameter, name)
%PARSEENGAGEMENT  Le as inches (plain number) or a diameter multiple
%   ("1.5D" / "1.5 D" / "1.5xD" -> 1.5 * NominalDiameter).
if isnumeric(v)
    le = double(v);
    return
end
s = upper(erase(strtrim(string(v)), [" ", "X", "*"]));
if endsWith(s, "D")
    n = str2double(erase(s, "D"));
    le = n * nominalDiameter;
else
    n = str2double(s);
    le = n;
end
if isnan(le)
    error("data:loadJointLibrary:badEngagement", ...
        "Row ""%s"": cannot parse ThreadEngagement ""%s"" (use inches, e.g. 0.5, or a diameter multiple, e.g. 1.5D).", ...
        name, string(v));
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

function a = parseBoltAxis(txt, name)
%PARSEBOLTAXIS  "X" / "Y" / "Z" (case-insensitive).
switch upper(strtrim(txt))
    case "X"
        a = model.BoltAxis.X;
    case "Y"
        a = model.BoltAxis.Y;
    case "Z"
        a = model.BoltAxis.Z;
    otherwise
        error("data:loadJointLibrary:badBoltAxis", ...
            "Row ""%s"": unknown BoltAxis ""%s"" (expected X, Y, or Z).", name, txt);
end
end

function w = washerFrom(T, names, r, prefix)
%WASHERFROM  model.Washer from {prefix}Thickness / {prefix}OD, or [] if neither set.
t  = getNum(T, names, r, prefix + "Thickness", NaN);
od = getNum(T, names, r, prefix + "OD", NaN);
if isnan(t) && isnan(od)
    w = [];
    return
end
w = model.Washer();
if ~isnan(t),  w.Thickness = t;      end
if ~isnan(od), w.OuterDiameter = od; end
end

% =========================================================================
% Table access primitives (case-insensitive columns, blanks -> default)
% =========================================================================

function v = getval(T, names, r, name, default)
%GETVAL  Raw cell value; `default` when the column is absent or the cell blank.
idx = find(strcmpi(names, name), 1);
if isempty(idx)
    v = default;
    return
end
v = T{r, idx};
if iscell(v), v = v{1}; end
if ischar(v), v = string(v); end
if isstring(v) && (ismissing(v) || strlength(strtrim(v)) == 0)
    v = default;
elseif isnumeric(v) && isscalar(v) && isnan(v)
    v = default;
end
end

function tf = hasVal(T, names, r, name)
%HASVAL  True when the column exists and the cell holds a non-blank value.
tf = ~isempty(getval(T, names, r, name, []));
end

function s = getText(T, names, r, name, default)
%GETTEXT  Trimmed string value ("" family -> default).
v = getval(T, names, r, name, string(default));
s = strtrim(string(v));
if ismissing(s)
    s = string(default);
end
end

function x = getNum(T, names, r, name, default)
%GETNUM  Numeric value; text cells are str2double'd (bad text errors).
v = getval(T, names, r, name, default);
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

function tf = getLogical(T, names, r, name, default)
%GETLOGICAL  Logical from logical/numeric/text (TRUE/FALSE, yes/no, 1/0).
v = getval(T, names, r, name, default);
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
