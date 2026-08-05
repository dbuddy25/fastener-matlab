function c = palette(name)
%PALETTE  Semantic color names -> RGB triples — the ONLY place GUI colors live.
%   c = gui2.palette(name) returns a 1x3 RGB triple for a semantic color
%   name. Every color in +gui2 goes through this function; no literal RGB
%   triple may appear anywhere else in the GUI layer. That discipline makes
%   a future dark mode (deferred — see GUI2_SPEC.md Section 15) a one-file
%   change instead of a grep across every page.
%
%   Color semantics, applied consistently across the app:
%     muted gray  = informational / OK
%     amber       = warning, AND "could not be evaluated"
%     red (bold)  = failure
%     red border  = missing required input
%
%   GUI2_HARVEST.md A1 — "unknown must never look like fine". A check that
%   could not run is amber, NOT muted gray: the check is not running, and
%   that must never read as nothing to report. tableNaBg exists for that
%   state and is deliberately distinct from both tablePassBg and
%   tableFailBg.
%
%   Names:
%     statusPass / statusFail / statusWarn — bold status text colors
%     defaultText / mutedText              — plain and de-emphasized text
%     tablePassBg / tableFailBg / tableNaBg — margin-table cell backgrounds
%     fieldBg / requiredBlankBg            — editable-field background:
%                                            normal, and the pale red for a
%                                            REQUIRED field left blank
%                                            (GUI2_SPEC.md Section 11)
%     bannerInfoBg|Fg|Border               — info banner (onboarding, hints)
%     bannerWarnBg|Fg|Border               — warning banner (amber)
%     bannerErrorBg|Fg|Border              — error banner (red)
%     navActiveFg / navIdleFg              — rail item label color, active
%                                            and idle. The ACTIVE state is
%                                            carried by the state button's
%                                            native pressed rendering plus
%                                            FontWeight (GUI2_SPEC.md
%                                            Section 3) — these two exist so
%                                            an idle item can be slightly
%                                            de-emphasized, NOT to signal
%                                            status. Rail STATUS rides on
%                                            the separate glyph channel; if
%                                            both used color they would
%                                            fight.
%     navSectionFg                         — rail section-header label
%     navStaleFg / navLoadedFg             — the rail status GLYPH color
%                                            (amber dot / loaded check)
%
%   Unknown names error immediately — a typo must fail loudly at development
%   time, not silently render the wrong color.
%
%   Values carried forward verbatim from gui.palette so the two builds
%   cannot drift while both are launchable (GUI2_SPEC.md Section 1 rule 2).
%   They assume a light background; R2026a apps are theme-aware, so if dark
%   mode is taken up this function becomes theme-aware and stays the single
%   file that changes.
%
%   Example:
%       lbl.FontColor = gui2.palette('statusFail');

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
    % GUI2_SPEC.md Section 11 — legible behind black text, and clearly
    % distinct from the bold tableFailBg. fieldBg is the restore target
    % when the field is filled.
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

    % ---- Left navigation rail --------------------------------------------
    % Active vs idle is a TEXT-WEIGHT and pressed-state distinction, not a
    % color one (GUI2_SPEC.md Section 3). These two are a light emphasis
    % difference only; they never carry status.
    case 'navActiveFg',  c = [0.00 0.00 0.00];
    case 'navIdleFg',    c = [0.20 0.20 0.20];
    case 'navSectionFg', c = [0.40 0.40 0.40];   % matches mutedText
    % Rail status glyph — the SEPARATE channel from active/idle.
    case 'navStaleFg',   c = [0.80 0.40 0.00];   % amber, matches statusWarn
    case 'navLoadedFg',  c = [0.00 0.40 0.00];   % green, matches statusPass

    otherwise
        error('gui2:palette:unknownName', ...
            'Unknown palette color "%s" — add it to gui2.palette, never inline an RGB triple.', name);
end
end
