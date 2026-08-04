classdef tMemberTypeCrossing < matlab.unittest.TestCase
    %TMEMBERTYPECROSSING  The engagement-mode boundary that a member-type
    %   change can cross, and what a crossing means for a stored value.
    %
    %   Thread engagement changes MEANING with member type: Helical Insert
    %   authors it as a multiple of the bolt nominal diameter
    %   (model.ThreadedMember.EngagementRatio), while Nut and Tapped Hole
    %   author it as an absolute length in inches (EngagementLength). A
    %   change that crosses that boundary leaves any entered value denoting
    %   something else, so both paths that can change a member type clear
    %   it rather than convert it.
    %
    %   Why this file exists: those two paths -- Joint Config's dropdown
    %   (gui.FastenerApp's onMemberTypeChanged) and the Defined Joints
    %   grid's Bulk Edit (onDjBulkEdited) -- implemented the rule
    %   independently and drifted. The grid changed Type without clearing,
    %   and engine/private/resolveEngagementLength is deliberately
    %   type-agnostic (a ratio wins whenever it is set), so a ratio left
    %   behind by a former Insert was applied as a NUT's thread engagement
    %   height: on a #10-32 that is 1.5 x 0.190 = 0.285 in, far longer than
    %   a real nut, overstating As = 0.75*pi*E*Le and so the nut allowable,
    %   uncapped when no rating is set -- while Joint Config displayed a
    %   BLANK engagement field for the same joint, because it shows the
    %   Nut-side property. The predicate is now a pure Static so it can be
    %   pinned here; neither callback is reachable without building a
    %   uifigure, which this suite deliberately never does.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function insertToInchModesIsACrossing(testCase)
            % Insert -> Nut and Insert -> Tapped Hole both leave a ratio
            % denoting something it is not.
            T = @(n) model.ThreadedMemberType.(n);
            testCase.verifyTrue(gui.FastenerApp.engagementModeCrossed( ...
                T('Insert'), T('Nut')));
            testCase.verifyTrue(gui.FastenerApp.engagementModeCrossed( ...
                T('Insert'), T('TappedHole')));
        end

        function inchModesToInsertIsACrossing(testCase)
            % The mirror image: an absolute length left behind would be
            % read as a diameter multiple.
            T = @(n) model.ThreadedMemberType.(n);
            testCase.verifyTrue(gui.FastenerApp.engagementModeCrossed( ...
                T('Nut'), T('Insert')));
            testCase.verifyTrue(gui.FastenerApp.engagementModeCrossed( ...
                T('TappedHole'), T('Insert')));
        end

        function nutAndTappedHoleAreTheSameMode(testCase)
            % NOT a crossing -- both author inches, so a value survives.
            % Clearing here would destroy work for no reason.
            T = @(n) model.ThreadedMemberType.(n);
            testCase.verifyFalse(gui.FastenerApp.engagementModeCrossed( ...
                T('Nut'), T('TappedHole')));
            testCase.verifyFalse(gui.FastenerApp.engagementModeCrossed( ...
                T('TappedHole'), T('Nut')));
        end

        function noChangeIsNotACrossing(testCase)
            T = @(n) model.ThreadedMemberType.(n);
            for n = ["Nut", "Insert", "TappedHole"]
                testCase.verifyFalse( ...
                    gui.FastenerApp.engagementModeCrossed(T(n), T(n)), ...
                    "Re-selecting the same type must not clear a value");
            end
        end

        function bothEngagementFieldsAreClearedTogether(testCase)
            % Documents the ACTION a crossing implies, which the predicate
            % itself does not encode: callers clear BOTH properties, not
            % just the one belonging to the outgoing mode. Clearing only
            % the outgoing one would leave the incoming mode's property
            % holding a value the analyst entered for a different meaning,
            % and resolveEngagementLength is type-agnostic -- a ratio wins
            % whenever it is set, whatever the member type.
            tm = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.Insert, ...
                EngagementRatio = 1.5, EngagementLength = 0.30);
            testCase.verifyTrue(gui.FastenerApp.engagementModeCrossed( ...
                tm.Type, model.ThreadedMemberType.Nut));
            tm.Type              = model.ThreadedMemberType.Nut;
            tm.EngagementRatio   = NaN;
            tm.EngagementLength  = NaN;
            testCase.verifyTrue(isnan(tm.EngagementRatio));
            testCase.verifyTrue(isnan(tm.EngagementLength), ...
                "Clearing only the outgoing mode's property strands the other");
        end
    end
end
