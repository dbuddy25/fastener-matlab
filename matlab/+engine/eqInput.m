function s = eqInput(symbol, value, units, source)
%EQINPUT  One term of an equation, as DATA rather than prose.
%   s = engine.eqInput(symbol, value, units, source) builds a single row of
%   a margin row's Inputs array — the numbers that were substituted into
%   the equation named by that row's Method string.
%
%   s = engine.eqInput() (no arguments) returns the EMPTY 1x0 array with
%   the same four fields. That is the "no inputs recorded" value, and it is
%   what a NotEvaluated check carries: a check that did not run has no
%   substituted values, and a caller renders that by testing isempty(),
%   never by looking for a sentinel number. Same idiom as Result.Warnings.
%
%   Fields:
%       Symbol  string — the symbol AS IT APPEARS in the Method equation,
%               so a reader can match the row to the formula by eye
%               ("PpMin", not "minimum in-service preload")
%       Value   double — the value actually used, in the engine's units
%               (lbf / in / psi / degC, see UNITS.md); NaN when the term
%               was genuinely absent rather than zero
%       Units   string — "lbf", "in", "in^2", "psi", or "" for a
%               dimensionless factor
%       Source  string — where the number came from: the engine function
%               and equation that produced it, or the model property it
%               was read off. This is what makes a disagreement traceable
%               to ONE upstream number instead of to "the margin".
%
%   ONE LEVEL ONLY. A term that is itself a product (Psep = FSSep*FFSep*PtL)
%   is recorded as the single number the equation consumed, with the
%   breakdown named in Source. Recursing would restate the design-loads and
%   preload panels inside all fifteen margin rows.
%
%   Call graph:
%       Precedents (calls)      (leaf).
%       Dependents (called by)  engine.marginSeparation,
%                               engine.marginNutStrength, engine.analyze
%                               (the entry() default), engine.Result (the
%                               empty Margins prototype).
%       Tests                   tests/tEqInput.m
%
%   Example:
%       engine.eqInput("PpMin", 6469.75, "lbf", "engine.preload (5020B Eq. 2)")

arguments
    symbol (1,1) string = ""
    value  (1,1) double = NaN
    units  (1,1) string = ""
    source (1,1) string = ""
end

s = struct("Symbol", symbol, "Value", value, "Units", units, "Source", source);

if nargin == 0
    s = repmat(s, 1, 0);
end
end
