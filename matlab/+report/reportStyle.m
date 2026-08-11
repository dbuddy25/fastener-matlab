function s = reportStyle()
%REPORTSTYLE  The report's visual language, in ONE place.
%   s = report.reportStyle() returns a struct of colours (hex strings, the
%   form mlreportgen.dom.Color takes) and type sizes used by every table
%   and heading report.singleJointReport builds.
%
%   WHY NOT gui2.palette. The values below are deliberately the SAME as
%   that palette's result colours — a margin that reads green on screen
%   must read green on paper, or a reviewer holding the PDF and an analyst
%   holding the screen are looking at what appears to be two different
%   answers. But +report must not depend on +gui2: the report layer is
%   callable headless, from the command window and from the bulk runners,
%   and reaching into a GUI package for a colour would drag the whole
%   shell into a path that has no window in it. So the values are restated
%   here and tests/tPdfReport.m asserts the two agree, which is the same
%   arrangement toolVersion uses — one definition would be better, two
%   with a guard is the best a layering rule allows.
%
%   RESULT COLOURS ARE SEMANTIC, not decorative: Pass / Fail /
%   NotEvaluated come straight off the engine's Status, and nothing in the
%   report re-thresholds a margin to pick one (GUI2_SPEC.md Section 2's
%   rule, which applies to paper for the same reason it applies to
%   screen).

s = struct();

% ---- Result colours — identical to gui2.palette's table colours --------
s.PassBg        = "C7F0C7";   % [0.78 0.94 0.78]
s.FailBg        = "FFC7C7";   % [1.00 0.78 0.78]
s.NotEvalBg     = "FFF3CD";   % amber — "did not run" is NOT "nothing to report"
s.NaBg          = "F0F0F0";   % [0.94 0.94 0.94]

s.PassText      = "006600";   % [0.00 0.40 0.00]
s.FailText      = "CC0000";   % [0.80 0.00 0.00]

% ---- Structure ---------------------------------------------------------
s.HeaderBg      = "334D80";   % dark blue band behind every table header
s.HeaderText    = "FFFFFF";
s.BandBg        = "F2F2F7";   % alternating row fill, very light
s.GridColor     = "B3B3B3";
s.MutedText     = "666666";

% ---- Type --------------------------------------------------------------
% A deliberate scale rather than per-call sizes: a report whose tables
% each picked their own size is exactly what the default styling looked
% like.
s.FontFamily    = "Helvetica";
s.TitleSize     = "16pt";
s.HeadingSize   = "12pt";
s.BodySize      = "9pt";
s.TableSize     = "8pt";
s.CaptionSize   = "7pt";
end
