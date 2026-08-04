function c = palette(name)
%PALETTE  Semantic color names -> RGB triples — the ONLY place GUI colors live.
%   c = gui.palette(name) returns a 1x3 RGB triple for a semantic color
%   name. Every color in +gui goes through this function; no literal RGB
%   triple may appear anywhere else in the GUI layer. That discipline makes
%   a future dark mode (deferred — see GUI_PORT_SPEC.md Section 9) a
%   one-file change instead of a grep across every tab.
%
%   Color semantics, applied consistently across the app:
%     muted gray  = informational / OK
%     amber       = warning
%     red (bold)  = failure
%     red border  = missing required input
%
%   Names:
%     statusPass / statusFail / statusWarn — bold status text colors
%     defaultText / mutedText              — plain and de-emphasized text
%     tablePassBg / tableFailBg / tableNaBg — margin-table cell backgrounds
%     fieldBg / requiredBlankBg            — editable-field background:
%                                            normal, and the pale red for a
%                                            REQUIRED field left blank
%                                            (spec Section 4 Layer 1)
%     bannerInfoBg|Fg|Border               — info banner (onboarding, hints)
%     bannerWarnBg|Fg|Border               — warning banner (amber)
%     bannerErrorBg|Fg|Border              — error banner (red)
%
%   Unknown names error immediately — a typo must fail loudly at development
%   time, not silently render the wrong color.
%
%   Example:
%       lbl.FontColor = gui.palette('statusFail');

arguments
    name (1,1) string
end

switch char(name)
    % ---- Status text -----------------------------------------------------
    case 'statusPass',  c = [0.00 0.40 0.00];   % #006600
    case 'statusFail',  c = [0.80 0.00 0.00];   % #CC0000
    case 'statusWarn',  c = [0.80 0.40 0.00];   % #CC6600
    case 'defaultText', c = [0.00 0.00 0.00];
    case 'mutedText',   c = [0.40 0.40 0.40];   % #666666

    % ---- Table cell backgrounds (pass/fail/not-evaluated) ----------------
    case 'tablePassBg', c = [0.78 0.94 0.78];
    case 'tableFailBg', c = [1.00 0.78 0.78];
    case 'tableNaBg',   c = [0.94 0.94 0.94];

    % ---- Editable-field backgrounds (required-field validation) ----------
    % requiredBlankBg is the "missing required input" pale red from
    % GUI_PORT_SPEC.md Section 4 Layer 1 — legible behind black text, and
    % clearly distinct from the bold tableFailBg. fieldBg is the restore
    % target when the field is filled.
    case 'fieldBg',         c = [1.00 1.00 1.00];
    case 'requiredBlankBg', c = [1.00 0.90 0.90];   % #FFE5E5

    % ---- Banners: info (blue), warning (amber), error (red) --------------
    case 'bannerInfoBg',     c = [0.863 0.914 0.988];   % #DCE9FC
    case 'bannerInfoFg',     c = [0.102 0.227 0.431];   % #1A3A6E
    case 'bannerInfoBorder', c = [0.630 0.760 0.950];
    case 'bannerWarnBg',     c = [1.000 0.953 0.804];   % #FFF3CD
    case 'bannerWarnFg',     c = [0.522 0.392 0.016];   % #856404
    case 'bannerWarnBorder', c = [1.000 0.933 0.729];
    case 'bannerErrorBg',    c = [0.973 0.843 0.855];   % #F8D7DA
    case 'bannerErrorFg',    c = [0.447 0.110 0.141];   % #721C24
    case 'bannerErrorBorder',c = [0.961 0.776 0.796];

    otherwise
        error('gui:palette:unknownName', ...
            'Unknown palette color "%s" — add it to gui.palette, never inline an RGB triple.', name);
end
end
