function choice = askChoice(fig, message, titleText, options, defaultOption, cancelOption)
%ASKCHOICE  Blocking multi-choice dialog — the one uiconfirm wrapper.
%   choice = gui.askChoice(fig, message, titleText, options) shows a modal
%   uiconfirm over `fig` with the given option buttons and returns the
%   selected option as a string. Closing the dialog any other way (Esc, X)
%   returns `cancelOption`, so callers can always compare against a known
%   option name — no empty/char special cases.
%
%   options       — 1xN string array of button labels, in display order.
%   defaultOption — Enter-key option (default: the LAST option, so the
%                   safe/cancel choice is the default unless stated).
%   cancelOption  — Esc/close option (default: the last option).
%
%   Every recurring dialog shape in the app routes through here so future
%   shapes (Overwrite/Skip/Rename, Replace/Merge/Cancel — GUI_PORT_SPEC.md
%   Section 14) are one call, not new plumbing:
%
%       c = gui.askChoice(fig, msg, 'Import', ...
%           ["Replace", "Merge", "Cancel"]);
%       if c == "Replace", ...
%
%   See gui.confirmDiscard for the dirty-state Discard/Cancel shape.

arguments
    fig           (1,1) matlab.ui.Figure
    message       (1,1) string
    titleText     (1,1) string
    options       (1,:) string
    defaultOption (1,1) string = options(end)
    cancelOption  (1,1) string = options(end)
end

choice = string(uiconfirm(fig, message, titleText, ...
    'Options',       cellstr(options), ...
    'DefaultOption', char(defaultOption), ...
    'CancelOption',  char(cancelOption), ...
    'Icon',          'question'));
end
