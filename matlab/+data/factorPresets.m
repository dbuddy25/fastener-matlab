function m = factorPresets()
%FACTORPRESETS  Built-in (protected) factor presets, name -> model.Factors
%   (Phase 3.7). These names can never be overwritten by
%   data.saveFactorPreset — see that function's protected-name check.
%
%   Presets:
%     "NASA-STD-5020B"            — the standard set used throughout this
%                                    tool's validation case (matches
%                                    validation.dabjSection9 / model.Factors
%                                    defaults): FSU 1.4, FSY 1.25, FSSep 1.0,
%                                    FSSlip 1.0, FFU 1.15, FFY 1.0, FFSep 1.0,
%                                    FFSlip 1.0.
%     "Ultimate-1.4-Yield-1.25"    — alias of the same standard set, named
%                                    by its two headline factors for users
%                                    who think in FSU/FSY shorthand.
%     "Conservative-FF-1.25"       — same safety factors, but a higher
%                                    (1.25) fitting factor across the
%                                    board — a common conservative
%                                    program-level policy variant.
%
%   m = data.factorPresets() -> containers.Map<string, model.Factors>.
%   Use data.factorPreset(name) for lookup (built-in + user, by name).

m = containers.Map();

standard = model.Factors(FSU=1.4, FSY=1.25, FSSep=1.0, FSSlip=1.0, ...
                         FFU=1.15, FFY=1.0, FFSep=1.0, FFSlip=1.0);

m("NASA-STD-5020B")         = standard;
m("Ultimate-1.4-Yield-1.25") = standard;
m("Conservative-FF-1.25")   = model.Factors(FSU=1.4, FSY=1.25, FSSep=1.0, ...
                                            FSSlip=1.0, FFU=1.25, FFY=1.25, ...
                                            FFSep=1.25, FFSlip=1.25);
end
