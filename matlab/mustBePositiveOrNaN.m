function mustBePositiveOrNaN(x)
%MUSTBEPOSITIVEORNAN  Validate that a value is NaN (unconfigured) or positive.
%   Passes when x is NaN — the "not yet configured" sentinel — or x > 0.
%   Errors otherwise, so zero/negative garbage fails loud instead of
%   silently flowing into the analysis.
if ~(isnan(x) || x > 0)
    error("model:validators:mustBePositiveOrNaN", ...
          "Value must be NaN (unconfigured) or positive.");
end
end
