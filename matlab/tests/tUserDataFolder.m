classdef tUserDataFolder < matlab.unittest.TestCase
    %TUSERDATAFOLDER  data.userDataFolder and data.copyUserData.
    %
    %   Run from the matlab/ folder with:
    %       runTests("UserDataFolder")
    %
    %   Every test passes its own preference file and temp folders, so the
    %   real user's library and folder choice are never read or written.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function anUnsetChoiceFallsBackToUserpath(testCase)
            store = testCase.tempStore();
            up = string(userpath());
            testCase.assumeGreaterThan(strlength(up), 0, 'userpath is empty here.');
            testCase.verifyEqual(data.userDataFolder("", store), up);
        end

        function aStoredChoiceIsReturned(testCase)
            store = testCase.tempStore();
            want = string(testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder);
            testCase.verifyEqual(data.userDataFolder(want, store), want);
            testCase.verifyEqual(data.userDataFolder("", store), want);
        end

        function aMissingChosenFolderIsStillReturned(testCase)
            % Falling back to the default would split the library across
            % two places the moment a sync is late.
            store = testCase.tempStore();
            gone = string(tempname);
            data.userDataFolder(gone, store);
            testCase.verifyEqual(data.userDataFolder("", store), gone);
        end

        function theCopyBringsTheLibraryPresetsAndDropIns(testCase)
            [from, to] = testCase.twoFolders();
            tUserDataFolder.write(fullfile(from, "fastener_library.json"), "lib");
            tUserDataFolder.write(fullfile(from, "fastener_factor_presets.json"), "presets");
            tUserDataFolder.write(fullfile(from, "fastener_library", "materials", "Ti.json"), "ti");

            [copied, kept] = data.copyUserData(from, to);

            testCase.verifyEqual(numel(copied), 3);
            testCase.verifyEmpty(kept);
            testCase.verifyEqual(string(fileread(fullfile(to, "fastener_library", "materials", "Ti.json"))), "ti");
        end

        function theCopyNeverOverwritesAndNeverDeletes(testCase)
            % The target may be a synced folder another machine filled.
            [from, to] = testCase.twoFolders();
            tUserDataFolder.write(fullfile(from, "fastener_library.json"), "old machine");
            tUserDataFolder.write(fullfile(to, "fastener_library.json"), "synced");

            [copied, kept] = data.copyUserData(from, to);

            testCase.verifyEmpty(copied);
            testCase.verifyEqual(kept, "fastener_library.json");
            testCase.verifyEqual(string(fileread(fullfile(to, "fastener_library.json"))), "synced", ...
                'An existing library in the target must never be replaced.');
            testCase.verifyEqual(string(fileread(fullfile(from, "fastener_library.json"))), "old machine", ...
                'The old folder must be left as it was.');
        end

        function theLibraryAndPresetsResolveThroughTheFolder(testCase)
            % The real preference is read here, never written.
            f = data.userDataFolder();
            testCase.verifyEqual(data.Library.userPath(), ...
                string(fullfile(f, "fastener_library.json")));
            testCase.verifyEqual(data.Library.dropInPath(), ...
                string(fullfile(f, "fastener_library")));
        end
    end

    methods
        function store = tempStore(testCase)
            store = string(tempname) + ".json";
            testCase.addTeardown(@() tUserDataFolder.deleteIfPresent(store));
        end

        function [from, to] = twoFolders(testCase)
            root = string(testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder);
            from = fullfile(root, "from");
            to = fullfile(root, "to");
            mkdir(from);
            mkdir(to);
        end
    end

    methods (Static, Access = private)
        function write(file, text)
            folder = fileparts(file);
            if ~isfolder(folder)
                mkdir(folder);
            end
            fid = fopen(file, 'w');
            fprintf(fid, '%s', text);
            fclose(fid);
        end

        function deleteIfPresent(f)
            if isfile(f)
                delete(f);
            end
        end
    end
end
