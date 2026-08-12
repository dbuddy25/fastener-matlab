classdef MarginView
    %MARGINVIEW  How a margin is RENDERED and REDUCED, in one place.
    %   Pure statics, no state, no widgets. Results and Bulk both come
    %   through here so the two can never disagree about what a number
    %   looks like or which direction "worse" runs (GUI2_HARVEST.md A8:
    %   "Formatting helpers are shared across Results and Bulk so the two
    %   can never drift").
    %
    %   That drift was real and already latent: the first build's bulk tab
    %   rendered margins as %+.2g and the ratio as "R = %.3g (<=1)", while
    %   the rebuilt Results page renders %+.2f and "R = %.2f (<= 1)".
    %   Porting the old formatters verbatim would have put two spellings of
    %   the same number in one application. The gui2 spellings win, and
    %   they live here.
    %
    %   THE INTERACTION RATIO IS THE WHOLE REASON THIS IS A MODULE.
    %   NASA-STD-5020B Eq. 20-23 reports R, passing iff R <= 1 — the
    %   OPPOSITE direction from MS >= 0. Every consumer that formats,
    %   colours or aggregates a margin MATRIX keys off isRatio rather than
    %   testing the name again, so a second ratio-type check some day is a
    %   one-line change here and nowhere else (GUI2_HARVEST.md A2).
    %
    %   Nothing here re-thresholds anything the engine decided. passFail
    %   exists because a bulk TABLE carries raw numbers rather than the
    %   Status strings a Result carries; where a Status exists, use it.

    properties (Constant)
        % Display cap. A margin above this renders ">+5" so the eye lands
        % on the near-failure numbers. DISPLAY ONLY — never applied to a
        % stored value, an aggregation or an export.
        CapThreshold = 5

        % The em dash that stands for "not evaluated". A1: never a blank,
        % never a zero, never "NaN" — an unrun check must not be able to
        % read as a computed one.
        NotEvaluated = char(8212)
    end

    methods (Static)
        function s = msText(value, capOn)
            %MSTEXT  Margin-of-safety display text.
            %   NaN -> em dash, +Inf -> "+inf", above the cap -> ">+5",
            %   otherwise a signed two-decimal number. The explicit plus is
            %   deliberate: "+0.32" and "0.32" read differently at a glance
            %   in a column where the sign is the whole answer.
            arguments
                value (1,1) double
                capOn (1,1) logical = true
            end
            if isnan(value)
                s = gui2.MarginView.NotEvaluated;
            elseif isinf(value) && value > 0
                s = '+inf';
            elseif capOn && value > gui2.MarginView.CapThreshold
                s = '>+5';
            else
                s = sprintf('%+.2f', value);
            end
        end

        function s = rText(value)
            %RTEXT  Interaction ratio display text.
            %   Carries its own criterion — "R = 0.86 (<= 1)" — because a
            %   bare 0.86 in a column of margins reads as a comfortable
            %   margin when it is in fact 86% of the allowable envelope.
            arguments
                value (1,1) double
            end
            if isnan(value)
                s = gui2.MarginView.NotEvaluated;
            elseif isinf(value)
                s = 'R = +inf (<= 1)';
            else
                s = sprintf('R = %.2f (<= 1)', value);
            end
        end

        function s = cellText(value, isRatioCol, capOn)
            %CELLTEXT  One margin cell, ratio-aware. The bulk grids' entry
            %   point: they hold a matrix and a mask, not named fields.
            arguments
                value      (1,1) double
                isRatioCol (1,1) logical
                capOn      (1,1) logical = true
            end
            if isRatioCol
                s = gui2.MarginView.rText(value);
            else
                s = gui2.MarginView.msText(value, capOn);
            end
        end

        function tf = isRatio(names)
            %ISRATIO  True where a column is a RATIO, not a margin.
            %   "InteractionR" today. THE one place that list lives: every
            %   path that aggregates, colours or formats a margin matrix
            %   asks here instead of re-testing the name.
            names = string(names);
            tf = (names == "InteractionR");
        end

        function env = envelope(M, ratioMask)
            %ENVELOPE  Column-wise worst case over a set of rows.
            %   An ordinary margin's worst case is its MINIMUM. A ratio's
            %   worst case is its MAXIMUM — R <= 1 passes, so a larger R
            %   has used more of the envelope.
            %
            %   THIS IS THE FUNCTION THE MODULE EXISTS FOR. A plain min()
            %   across a mixed matrix silently takes the BEST-case R across
            %   load cases, which hides a real interaction failure from the
            %   Joint Summary tier and from any export built on it. The bug
            %   would show as a joint that passes in summary and fails when
            %   you open it.
            arguments
                M         double
                ratioMask (1,:) logical
            end
            env = min(M, [], 1, 'omitnan');
            if any(ratioMask)
                env(ratioMask) = max(M(:, ratioMask), [], 1, 'omitnan');
            end
        end

        function [passM, failM] = passFail(M, ratioMask)
            %PASSFAIL  Pass / fail masks for a margin matrix.
            %   MS >= 0 passes; R <= 1 passes. NaN is neither — an
            %   unevaluated check must not be counted as passing, and must
            %   not be counted as failing either (A1).
            arguments
                M         double
                ratioMask (1,:) logical
            end
            passM = false(size(M));
            failM = false(size(M));
            ok = ~isnan(M);

            ms = ok & ~repmat(ratioMask, size(M, 1), 1);
            passM(ms) = M(ms) >= 0;
            failM(ms) = M(ms) <  0;

            rt = ok & repmat(ratioMask, size(M, 1), 1);
            passM(rt) = M(rt) <= 1;
            failM(rt) = M(rt) >  1;
        end

        function names = headerText(cols)
            %HEADERTEXT  Column name -> table header.
            %   Splits camel case ("TensionUlt" -> "Tension Ult") so a new
            %   engine check gets a readable header with no GUI change.
            %   InteractionR is the exception: it is named for its
            %   criterion, not its magnitude.
            cols  = string(cols);
            names = cell(1, numel(cols));
            for i = 1:numel(cols)
                if cols(i) == "InteractionR"
                    names{i} = 'Interaction R (<= 1)';
                else
                    % Capture both sides and put the space between them.
                    % A zero-width lookaround pattern finds the boundary
                    % but regexprep does not substitute into an empty
                    % match, so "TensionUlt" came back unchanged.
                    names{i} = char(regexprep(char(cols(i)), ...
                        '([a-z])([A-Z])', '$1 $2'));
                end
            end
        end
    end
end
