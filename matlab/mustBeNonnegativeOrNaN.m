function mustBeNonnegativeOrNaN(x)
%MUSTBENONNEGATIVEORNAN  Validate that a value is NaN (unconfigured) or >= 0.
%   Passes when x is NaN — the "not yet configured" sentinel — or x >= 0.
%   Errors otherwise, so negative garbage fails loud instead of silently
%   flowing into the analysis.
if ~(isnan(x) || x >= 0)
    error("model:validators:mustBeNonnegativeOrNaN", ...
          "Value must be NaN (unconfigured) or nonnegative.");
end
end
