classdef tDefinedJointsOrder < matlab.unittest.TestCase
    %TDEFINEDJOINTSORDER  Defined Joints reordering (Move Up/Down, Sort by
    %   Name): the pure struct-array helpers behind those buttons.
    %
    %   gui.FastenerApp's Defined Joints list used to auto-sort by name on
    %   every refresh; app.JointLibrary's own stored order is now the
    %   display order, and the analyst reorders it with Move Up/Down or a
    %   one-shot Sort by Name action (onDjMoveUp/onDjMoveDown/
    %   onDjSortByName in +gui/FastenerApp.m). Those callbacks are GUI
    %   glue with no reachable test seam (no test in this suite
    %   instantiates gui.FastenerApp — it builds a real uifigure), but the
    %   reorder logic itself is factored into two PURE, public Static
    %   helpers that need no app/GUI instance at all:
    %       gui.FastenerApp.swapJointLibraryEntries(lib, i, j)
    %       gui.FastenerApp.orderJointLibraryByName(lib)
    %   This file is the test surface for those two helpers.
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
        function swapExchangesTwoEntriesOnly(testCase)
            lib = tDefinedJointsOrder.makeLib(["Alpha", "Bravo", "Charlie", "Delta"]);
            swapped = gui.FastenerApp.swapJointLibraryEntries(lib, 2, 4);
            testCase.verifyEqual([swapped.Name], ...
                ["Alpha", "Delta", "Charlie", "Bravo"]);
            % The Joint payload rides along with its Name (identity, not
            % position, is what moved) and every untouched entry is
            % byte-for-byte unchanged.
            testCase.verifyEqual(swapped(1), lib(1));
            testCase.verifyEqual(swapped(3), lib(3));
            testCase.verifyEqual(swapped(2).Joint, lib(4).Joint);
            testCase.verifyEqual(swapped(4).Joint, lib(2).Joint);
        end

        function swapAdjacentEntriesIsMoveUpMoveDown(testCase)
            % onDjMoveUp/onDjMoveDown always swap ADJACENT indices
            % (idx, idx-1) or (idx, idx+1) -- the case that actually fires
            % from the buttons.
            lib = tDefinedJointsOrder.makeLib(["Alpha", "Bravo", "Charlie"]);
            up = gui.FastenerApp.swapJointLibraryEntries(lib, 2, 1);
            testCase.verifyEqual([up.Name], ["Bravo", "Alpha", "Charlie"]);

            down = gui.FastenerApp.swapJointLibraryEntries(lib, 2, 3);
            testCase.verifyEqual([down.Name], ["Alpha", "Charlie", "Bravo"]);
        end

        function orderByNameIsCaseInsensitiveAndStable(testCase)
            lib = tDefinedJointsOrder.makeLib(["charlie", "Alpha", "bravo", "alpha"]);
            order = gui.FastenerApp.orderJointLibraryByName(lib);
            names = [lib(order).Name];
            testCase.verifyEqual(names, ["Alpha", "alpha", "bravo", "charlie"]);
            % Stable sort: the two case-variant "alpha"/"Alpha" entries
            % (indices 2 and 4) must keep their original relative order.
            testCase.verifyLessThan(find(order == 2), find(order == 4));
        end

        function orderByNameHandlesEmptyAndSingleton(testCase)
            emptyLib = struct('Name', {}, 'Joint', {});
            testCase.verifyEqual(gui.FastenerApp.orderJointLibraryByName(emptyLib), ...
                zeros(1, 0));

            oneLib = tDefinedJointsOrder.makeLib("Solo");
            testCase.verifyEqual(gui.FastenerApp.orderJointLibraryByName(oneLib), 1);
        end

        function sortByNameReordersTheWholeLibrary(testCase)
            % Mirrors what onDjSortByName does: compute the order, then
            % index the library by it. This is the "Sort by Name" button's
            % entire effect on app.JointLibrary.
            lib = tDefinedJointsOrder.makeLib(["Zulu", "Alpha", "Mike"]);
            order = gui.FastenerApp.orderJointLibraryByName(lib);
            sorted = lib(order);
            testCase.verifyEqual([sorted.Name], ["Alpha", "Mike", "Zulu"]);
        end
    end

    methods (Static)
        function lib = makeLib(names)
            %MAKELIB  A minimal JointLibrary struct array for these pure
            %   helpers -- Name is all they read; Joint just has to ride
            %   along with an identifiable payload (its own name), which
            %   is what the "moved by identity" assertions above check.
            names = string(names);
            n = numel(names);
            lib = struct('Name', {}, 'Joint', {});
            for i = 1:n
                lib(i) = struct('Name', names(i), 'Joint', names(i)); %#ok<AGROW>
            end
        end
    end
end
