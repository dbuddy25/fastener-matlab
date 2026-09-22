function r = marginSeparation(preload, designLoads)
%MARGINSEPARATION  Joint-separation margin of safety (NASA-STD-5020B Eq. 19).
%   r = engine.marginSeparation(preload, designLoads) computes the
%   separation margin for one joint. preload is the struct from
%   engine.preload; designLoads is the struct from engine.designLoads.
%   All loads in lbf (see UNITS.md).
%
%   Separation is driven by the MINIMUM in-service preload against the
%   design separation load:
%       MS = PpMin / Psep - 1                                (Eq. 19)
%   where PpMin = preload.PpMin (worst-case min preload after uncertainty,
%   relaxation, creep, and thermal) and Psep = designLoads.Psep
%   (FSSep * FFSep * PtL).
%
%   TWO SCOPE LIMITS §4.4.3 PUTS ON Eq. 19, neither of which the tool can
%   detect for you (see COMPLIANCE.md):
%
%     AXIAL ONLY. "The equation is applicable to systems under axial
%     loading only. Other equations or methods may be used to evaluate the
%     margin of safety when combined loading is considered." (p32) So a
%     joint carrying simultaneous shear or bending is outside Eq. 19's
%     stated scope — part of the TFSR 11 gap COMPLIANCE.md records as
%     PARTIAL, and the reason this row is not the whole separation story.
%
%     SEALED JOINTS. "When a joint maintains a seal ... Eq. 19 does not
%     accurately predict the margin of safety for separation." (p32) The
%     tool models no seal, so it cannot warn; an analyst working a sealed
%     interface must not read this margin as the answer.
%
%   Returned struct fields:
%       MS      margin of safety (double)
%       Method  string: governing equation
%       Inputs  1x2 struct array (engine.eqInput): the two numbers actually
%               substituted into Eq. 19, so the margin can be re-derived by
%               hand — or diffed against another tool — without re-reading
%               the preload and design-load panels. Symbols match the Method
%               equation exactly.

arguments
    preload     (1,1) struct
    designLoads (1,1) struct
end

% NASA-STD-5020B Eq. 19 — MS = PpMin / Psep - 1
MS = preload.PpMin / designLoads.Psep - 1;

r = struct( ...
    "MS",     MS, ...
    "Method", "NASA-STD-5020B Eq. 19 (separation) - MS = PpMin/Psep - 1", ...
    "Inputs", [ ...
        engine.eqInput("PpMin", preload.PpMin, "lbf", ...
            "engine.preload, 5020B Eq. 2"), ...
        engine.eqInput("Psep", designLoads.Psep, "lbf", ...
            "engine.designLoads = FSSep*FFSep*PtL")]);
end
