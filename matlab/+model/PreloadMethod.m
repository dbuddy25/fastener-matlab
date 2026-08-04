classdef PreloadMethod
    %PRELOADMETHOD  How the installed preload is established/specified.
    %   TorqueControl — preload derived from an effective torque range and
    %                   nut factor K (P = T / (K·D)).
    %   DirectPreload — nominal preload specified directly (e.g. from an
    %                   instrumented installation or a known answer key).
    enumeration
        TorqueControl
        DirectPreload
    end
end
