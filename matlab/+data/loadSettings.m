function s = loadSettings(file)
%LOADSETTINGS  Global analysis settings (temperatures + factors) from a file.
%   s = data.loadSettings(file) reads a small key/value settings table
%   (.csv or .xlsx) and returns a struct with fields:
%       NominalTempC  (1,1) double  — assembly/reference temperature, degC
%       HotTempC      (1,1) double  — maximum expected temperature, degC
%       ColdTempC     (1,1) double  — minimum expected temperature, degC
%       Factors       (1,1) model.Factors — safety/fitting factors built
%                     from the FSU/FSY/FSSep/FSSlip/FFU/FFY/FFSep/FFSlip
%                     keys; any missing key keeps the model.Factors default
%
%   FILE FORMAT — a TWO-COLUMN (key, value) table, one setting per row
%   (template with the exact keys: templates/settings_template.csv):
%
%       Setting,Value
%       NominalTempC,20
%       HotTempC,33.8889
%       ColdTempC,6.1111
%       FSU,1.4
%       ...
%
%   Keys are matched case-insensitively in column 1; column 2 is the
%   numeric value. Unrecognized rows (including any header/banner rows)
%   are simply ignored, so the file needs no fixed header and tolerates
%   decoration. Missing temperature keys default to 20 degC.
%
%   These settings are GLOBAL: engine.runBulk applies the three
%   temperatures to every Joint (ReferenceTemperature = NominalTempC,
%   MaxTemperature = HotTempC, MinTemperature = ColdTempC) and passes the
%   Factors to the analysis — the joint table itself carries neither.
%
%   Example:
%       s = data.loadSettings("templates/settings_template.csv");
%       s.NominalTempC   % -> 20
%       s.Factors.FSU    % -> 1.4

arguments
    file (1,1) string
end

if ~isfile(file)
    error("data:loadSettings:fileNotFound", ...
        "Settings file not found: %s", file);
end

raw = readcell(file, "DatetimeType", "text");

tempKeys = ["NominalTempC", "HotTempC", "ColdTempC"];
facKeys  = ["FSU", "FSY", "FSSep", "FSSlip", "FFU", "FFY", "FFSep", "FFSlip"];

s = struct("NominalTempC", 20, "HotTempC", 20, "ColdTempC", 20);
facArgs = {};
for r = 1:size(raw, 1)
    if size(raw, 2) < 2
        continue
    end
    k = raw{r, 1};
    if ~(ischar(k) || isstring(k))
        continue                          % blank/numeric key cell -> not a setting
    end
    k = strtrim(string(k));
    x = toNumber(raw{r, 2});
    if strlength(k) == 0 || isnan(x)
        continue                          % header/banner/blank rows are ignored
    end
    ti = find(strcmpi(tempKeys, k), 1);
    if ~isempty(ti)
        s.(tempKeys(ti)) = x;
        continue
    end
    fi = find(strcmpi(facKeys, k), 1);
    if ~isempty(fi)
        facArgs = [facArgs, {char(facKeys(fi)), x}]; %#ok<AGROW>
    end
end

s.Factors = model.Factors(facArgs{:});
end

function x = toNumber(v)
%TONUMBER  Numeric value of a readcell cell; NaN when not numeric-like.
if isa(v, "missing")
    x = NaN;
elseif isnumeric(v) && isscalar(v)
    x = double(v);
elseif islogical(v)
    x = double(v);
elseif ischar(v) || isstring(v)
    x = str2double(string(v));
else
    x = NaN;
end
end
