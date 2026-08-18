classdef tReferenceDocuments < matlab.unittest.TestCase
    %TREFERENCEDOCUMENTS  The citation list behind Help > References.
    %
    %   Run from the matlab/ folder with:
    %       runTests("ReferenceDocuments")
    %
    %   WHY THIS IS TESTED AT ALL, given it is a list of constants: the
    %   list is a COMPLIANCE artifact, not decoration. It is the tool's own
    %   statement of which documents its numbers rest on and in what role,
    %   and CLAUDE.md's document hierarchy is a rule with real
    %   consequences -- the DABJ course book being marked Validation rather
    %   than Governing is the difference between an answer key and a source
    %   of equations. A silent edit that promoted it would be a serious
    %   error and would otherwise be caught by nobody.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function everyDocumentIsFullyDescribed(testCase)
            % A row with a blank citation is worse than no row: it implies
            % the tool cannot say where a number came from.
            docs = data.referenceDocuments();
            testCase.assertGreaterThan(numel(docs), 0);
            for d = docs
                testCase.verifyGreaterThan(strlength(d.Key), 0);
                testCase.verifyGreaterThan(strlength(d.Title), 0, ...
                    sprintf('%s has no title.', d.Key));
                testCase.verifyGreaterThan(strlength(d.Publisher), 0, ...
                    sprintf('%s has no publisher.', d.Key));
                testCase.verifyGreaterThan(strlength(d.UsedFor), 0, ...
                    sprintf('%s does not say what the tool takes from it.', d.Key));
            end
        end

        function keysAreUnique(testCase)
            keys = [data.referenceDocuments().Key];
            testCase.verifyEqual(numel(unique(keys)), numel(keys));
        end

        function rolesComeFromTheDocumentHierarchy(testCase)
            % Free-text roles would drift into synonyms and the ordering
            % that matters -- governing above supplemental above validation
            % -- would stop being legible.
            allowed = ["Governing", "Supplemental", "Hardware data", ...
                       "Validation", "Background"];
            for d = data.referenceDocuments()
                testCase.verifyTrue(any(d.Role == allowed), ...
                    sprintf('%s has role "%s", which is not in the hierarchy.', ...
                            d.Key, d.Role));
            end
        end

        function exactlyOneDocumentGoverns(testCase)
            % CLAUDE.md: "NASA-STD-5020B is the governing standard."
            % Singular. A second Governing row would be a claim that two
            % documents can settle the same question.
            docs = data.referenceDocuments();
            governing = docs([docs.Role] == "Governing");
            testCase.verifyEqual(numel(governing), 1);
            testCase.verifyEqual(governing.Key, "NASA-STD-5020B");
        end

        function theCourseBookIsValidationOnly(testCase)
            % The rule this list most needs to keep. CLAUDE.md: "The DABJ
            % course book is VALIDATION ONLY -- the worked-example answer
            % key. Never cite DABJ as a governing equation."
            docs = data.referenceDocuments();
            dabj = docs(contains([docs.Key], "DABJ"));
            testCase.assertNotEmpty(dabj, 'The answer key must be listed.');
            testCase.verifyEqual(dabj.Role, "Validation");
        end

        function theCopyrightedDocumentsAreMarkedUnshippable(testCase)
            % THIS IS THE FLAG THAT KEEPS THE TOOL LEGAL. Every NAS/NASM
            % sheet carries "COPYRIGHT ... Aerospace Industries Association
            % ... ALL RIGHTS RESERVED" on its face, the course book carries
            % a copyright notice and restrictions, and the Heli-Coil
            % bulletin is vendor material. If a future packaging step reads
            % this flag to decide what to include, a wrong value here ships
            % someone else's document inside our installer.
            docs = data.referenceDocuments();
            mustNotShip = ["NASM33537", "NAS1351", "NAS1352", "NASM21042", ...
                           "NAS1291", "NAS620", "NAS1149", ...
                           "Heli-Coil TB 68-2", "DABJ course book"];
            for k = mustNotShip
                d = docs([docs.Key] == k);
                testCase.assertNotEmpty(d, sprintf('%s is missing from the list.', k));
                testCase.verifyFalse(d.Redistributable, ...
                    sprintf('%s is copyrighted and must never be marked shippable.', k));
            end

            % And the other half, so the flag is not just false everywhere:
            % the governing standard IS public release, distribution
            % unlimited, and marking it unshippable would be its own error.
            std = docs([docs.Key] == "NASA-STD-5020B");
            testCase.verifyTrue(std.Redistributable);
        end

        function fileNamesMatchWhatIsActuallyOnDisk(testCase)
            % The File field is how a local copy is found, so a typo makes
            % a document permanently "not on this machine" even when it is.
            % Only checkable where the folder exists -- it is gitignored,
            % so a clean checkout has nothing to compare against.
            folder = gui2.referencesFolder();
            testCase.assumeTrue(strlength(folder) > 0 && isfolder(folder), ...
                'No references folder on this machine; nothing to check against.');

            docs = data.referenceDocuments();
            missing = strings(1, 0);
            for d = docs
                if strlength(d.File) > 0 && ~isfile(fullfile(folder, d.File))
                    missing(end+1) = d.File; %#ok<AGROW>
                end
            end
            testCase.verifyEmpty(missing, sprintf( ...
                'Named files not found in %s: %s', folder, strjoin(missing, ", ")));
        end

        function theStoredFolderRoundTrips(testCase)
            % A TEMP STORE, not the real one. This writes a per-user
            % preference, and a test that pointed a developer's machine at
            % a folder it then deleted would be a nasty thing to leave
            % behind. Same reason data.saveFactorPreset takes a file.
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            store  = string(fullfile(fx.Folder, "prefs.json"));
            folder = string(fullfile(fx.Folder, "docs"));
            mkdir(char(folder));

            testCase.verifyEqual(gui2.referencesFolder("", store), "", ...
                'An unwritten store reads as unset, not as an error.');

            gui2.referencesFolder(folder, store);
            testCase.verifyEqual(gui2.referencesFolder("", store), folder);
        end
    end
end
