function T = summary(joint, loadCase, factors)
%SUMMARY  Analysis inputs + computed preload band as one display table.
%   T = engine.summary(joint, loadCase, factors) returns a MATLAB table that
%   records, in human-readable form, every input to the analysis (bolt,
%   materials, clamped stack, threaded member, preload spec, joint config,
%   applied loads, factors) plus the computed min/max preload band from
%   engine.preload. One row per item; columns:
%       Group   (string)  section the row belongs to (e.g. "Bolt", "Factors")
%       Item    (string)  the input's name
%       Value   (string)  display string ("—" for NaN / not set)
%       Unit    (string)  engineering unit ("" if dimensionless)
%
%   This is a display/reporting helper — no analysis math lives here (the
%   preload numbers come from engine.preload). Suitable for disp(T),
%   writetable(T, ...), or embedding in a report.
%
%   Example:
%       c = validation.dabjSection9();
%       T = engine.summary(c.Joint, c.LoadCase, c.Factors)

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
end

rows = strings(0, 4);   % accumulates [Group, Item, Value, Unit] per row

% ---- Bolt ---------------------------------------------------------------
b = joint.Bolt;
rows(end+1,:) = ["Bolt", "Designation",       fmt(b.Designation),       ""];
rows(end+1,:) = ["Bolt", "NominalDiameter",   fmt(b.NominalDiameter),   "in"];
rows(end+1,:) = ["Bolt", "Series",            fmt(b.Series),            ""];
rows(end+1,:) = ["Bolt", "ThreadsPerInch",    fmt(b.ThreadsPerInch),    "1/in"];
rows(end+1,:) = ["Bolt", "TensileStressArea", fmt(b.TensileStressArea), "in^2"];
rows(end+1,:) = ["Bolt", "MinorDiameter",     fmt(b.MinorDiameter),     "in"];
rows(end+1,:) = ["Bolt", "BodyDiameter",      fmt(b.BodyDiameter),      "in"];

% ---- Bolt material ------------------------------------------------------
bm = joint.BoltMaterial;
rows(end+1,:) = ["Bolt material", "Name", fmt(bm.Name), ""];
rows(end+1,:) = ["Bolt material", "Ftu",  fmt(bm.Ftu),  "psi"];
rows(end+1,:) = ["Bolt material", "Fty",  fmt(bm.Fty),  "psi"];
rows(end+1,:) = ["Bolt material", "Fsu",  fmt(bm.Fsu),  "psi"];
rows(end+1,:) = ["Bolt material", "E",    fmt(bm.E),    "psi"];
rows(end+1,:) = ["Bolt material", "CTE",  fmt(bm.CTE),  "1/degC"];

% ---- Clamped stack (one row per flange layer) ---------------------------
if isempty(joint.FlangeStack)
    rows(end+1,:) = ["Clamped stack", "Layers", "(none)", ""];
else
    for k = 1:numel(joint.FlangeStack)
        fl = joint.FlangeStack(k);
        rows(end+1,:) = ["Clamped stack", sprintf("Layer %d", k), ...
            sprintf("%s, t = %s", fmt(fl.Material.Name), fmt(fl.Thickness)), "in"];
    end
end
rows(end+1,:) = ["Clamped stack", "GripLength", fmt(joint.GripLength), "in"];

% ---- Threaded member ----------------------------------------------------
tm = joint.ThreadedMember;
rows(end+1,:) = ["Threaded member", "Type",              fmt(tm.Type),              ""];
rows(end+1,:) = ["Threaded member", "Material",          fmt(tm.Material.Name),     ""];
rows(end+1,:) = ["Threaded member", "RatedUltimateLoad", fmt(tm.RatedUltimateLoad), "lbf"];

% ---- Preload spec -------------------------------------------------------
ps = joint.PreloadSpec;
rows(end+1,:) = ["Preload spec", "Method",             fmt(ps.Method),             ""];
rows(end+1,:) = ["Preload spec", "NominalTorque",      fmt(ps.NominalTorque),      "in-lbf"];
rows(end+1,:) = ["Preload spec", "TorqueTolerance",    fmt(ps.TorqueTolerance),    ""];
rows(end+1,:) = ["Preload spec", "TorqueMin (derived)", fmt(ps.TorqueMin),         "in-lbf"];
rows(end+1,:) = ["Preload spec", "TorqueMax (derived)", fmt(ps.TorqueMax),         "in-lbf"];
rows(end+1,:) = ["Preload spec", "NutFactor K",        fmt(ps.NutFactor),          ""];
rows(end+1,:) = ["Preload spec", "Uncertainty Γ",      fmt(ps.Uncertainty),        ""];
rows(end+1,:) = ["Preload spec", "RelaxationFraction", fmt(ps.RelaxationFraction), ""];
rows(end+1,:) = ["Preload spec", "CreepLoss",          fmt(ps.CreepLoss),          "lbf"];
rows(end+1,:) = ["Preload spec", "ThermalRate",        fmt(ps.ThermalRate),        "lbf/degC"];
rows(end+1,:) = ["Preload spec", "SeparationCritical", fmt(ps.SeparationCritical), ""];
if ps.Method == model.PreloadMethod.DirectPreload
    rows(end+1,:) = ["Preload spec", "NominalPreload", fmt(ps.NominalPreload), "lbf"];
end

% ---- Config -------------------------------------------------------------
rows(end+1,:) = ["Config", "BoltCount",             fmt(joint.BoltCount),             ""];
rows(end+1,:) = ["Config", "FrictionCoefficient μ", fmt(joint.FrictionCoefficient),   ""];
rows(end+1,:) = ["Config", "LoadingPlaneFactor n",  fmt(joint.LoadingPlaneFactor),    ""];
rows(end+1,:) = ["Config", "ShearPlane",            fmt(joint.ShearPlane),            ""];
rows(end+1,:) = ["Config", "SlipMode",              fmt(joint.SlipMode),              ""];
rows(end+1,:) = ["Config", "BoltRatedUltimateLoad", fmt(joint.BoltRatedUltimateLoad), "lbf"];
rows(end+1,:) = ["Config", "BoltRatedYieldLoad",    fmt(joint.BoltRatedYieldLoad),    "lbf"];
rows(end+1,:) = ["Config", "ReferenceTemperature",  fmt(joint.ReferenceTemperature),  "degC"];
rows(end+1,:) = ["Config", "MinTemperature",        fmt(joint.MinTemperature),        "degC"];
rows(end+1,:) = ["Config", "MaxTemperature",        fmt(joint.MaxTemperature),        "degC"];

% ---- Applied loads (LoadCase) -------------------------------------------
rows(end+1,:) = ["Applied loads", "Name",                  fmt(loadCase.Name),                  ""];
rows(end+1,:) = ["Applied loads", "BoltTensileLimitLoad",  fmt(loadCase.BoltTensileLimitLoad),  "lbf"];
rows(end+1,:) = ["Applied loads", "BoltShearLimitLoad",    fmt(loadCase.BoltShearLimitLoad),    "lbf"];
rows(end+1,:) = ["Applied loads", "JointTensileLimitLoad", fmt(loadCase.JointTensileLimitLoad), "lbf"];
rows(end+1,:) = ["Applied loads", "JointShearLimitLoad",   fmt(loadCase.JointShearLimitLoad),   "lbf"];

% ---- Factors ------------------------------------------------------------
rows(end+1,:) = ["Factors", "FSU",    fmt(factors.FSU),    ""];
rows(end+1,:) = ["Factors", "FSY",    fmt(factors.FSY),    ""];
rows(end+1,:) = ["Factors", "FSSep",  fmt(factors.FSSep),  ""];
rows(end+1,:) = ["Factors", "FSSlip", fmt(factors.FSSlip), ""];
rows(end+1,:) = ["Factors", "FFU",    fmt(factors.FFU),    ""];
rows(end+1,:) = ["Factors", "FFY",    fmt(factors.FFY),    ""];
rows(end+1,:) = ["Factors", "FFSep",  fmt(factors.FFSep),  ""];
rows(end+1,:) = ["Factors", "FFSlip", fmt(factors.FFSlip), ""];

% ---- Preload (computed) — the min/max preload band ----------------------
p = engine.preload(joint);
rows(end+1,:) = ["Preload (computed)", "PpiMax",       fmt(p.PpiMax),       "lbf"];
rows(end+1,:) = ["Preload (computed)", "PpiMin",       fmt(p.PpiMin),       "lbf"];
rows(end+1,:) = ["Preload (computed)", "ThermalDelta", fmt(p.ThermalDelta), "lbf"];
rows(end+1,:) = ["Preload (computed)", "PpMax",        fmt(p.PpMax),        "lbf"];
rows(end+1,:) = ["Preload (computed)", "PpMin",        fmt(p.PpMin),        "lbf"];

T = table(rows(:,1), rows(:,2), rows(:,3), rows(:,4), ...
    VariableNames=["Group", "Item", "Value", "Unit"]);
end

% ---- Local helpers --------------------------------------------------------
function s = fmt(v)
%FMT  One value -> display string. NaN -> "—"; numbers via %.6g; else string().
if isnumeric(v)
    if isnan(v)
        s = "—";
    else
        s = string(sprintf("%.6g", v));
    end
else
    s = string(v);   % strings pass through; enums/logicals -> their names
end
end
