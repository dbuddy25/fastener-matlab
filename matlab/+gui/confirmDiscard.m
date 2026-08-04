function tf = confirmDiscard(fig, actionText)
%CONFIRMDISCARD  "Discard unsaved changes?" — true when the user says yes.
%   tf = gui.confirmDiscard(fig, actionText) asks before an action that
%   would destroy unsaved edits (File > New / Open, closing the window).
%   `actionText` names the action in the question, e.g. "starting a new
%   case". Cancel is the default and the Esc action — destroying work must
%   never be the path of least resistance.
%
%   Callers are responsible for checking the dirty flag first; this
%   function always asks. The rule it serves (GUI_PORT_SPEC.md Section 2):
%   confirm whenever dirty, INCLUDING when no file is open. Skipping the
%   no-file case is the classic way File > New silently destroys work:
%   unsaved edits are just as real before the case has a filename.
%
%   Example:
%       if app.IsDirty && ~gui.confirmDiscard(app.Fig, 'opening another case')
%           return
%       end

arguments
    fig        (1,1) matlab.ui.Figure
    actionText (1,1) string = "continuing"
end

choice = gui.askChoice(fig, ...
    sprintf('You have unsaved changes. Discard them before %s?', actionText), ...
    'Unsaved Changes', ["Discard Changes", "Cancel"]);
tf = (choice == "Discard Changes");
end
