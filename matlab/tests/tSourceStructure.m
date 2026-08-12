classdef tSourceStructure < matlab.unittest.TestCase
    %TSOURCESTRUCTURE  Every .m file's block structure, checked as TEXT.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   WHY THIS EXISTS, AND WHY IT READS TEXT RATHER THAN CALLING CODE.
    %   A classdef whose blocks are mis-nested does not fail — it fails to
    %   LOAD, and a test class that fails to load contributes NO TESTS AT
    %   ALL. The suite then reports a smaller number, every one of them
    %   green. That is the worst possible failure mode: it looks like
    %   success, and the only symptom is a total nobody was tracking
    %   closely enough to notice. It has happened twice in this repo, both
    %   times from appending a methods block one line too early, and both
    %   times a function/end COUNT looked correct because the totals still
    %   balanced — the blocks were simply nested wrongly.
    %
    %   So this reads every file as text and checks two things a balanced
    %   count cannot see:
    %       1. methods/properties/events/enumeration blocks sit DIRECTLY
    %          inside a classdef — never inside another block.
    %       2. every block opened is closed.
    %
    %   It is deliberately independent of MATLAB's own parser: a file this
    %   test can read is a file whose structure is checkable even when the
    %   parser would refuse it.

    properties (Constant)
        % Opens a block. `else`/`elseif`/`case`/`otherwise` deliberately
        % absent — they continue a block rather than opening one.
        Openers = ["classdef", "methods", "properties", "events", ...
                   "enumeration", "function", "if", "for", "while", ...
                   "switch", "try", "parfor", "spmd", "arguments"]

        % Legal only directly inside a classdef.
        ClassOnly = ["methods", "properties", "events", "enumeration"]
    end

    methods (Test)
        function everyFileIsStructurallySound(testCase)
            files = tSourceStructure.sourceFiles();
            testCase.assertNotEmpty(files, 'Found no .m files to check.');

            problems = string.empty(1, 0);
            for i = 1:numel(files)
                problems = [problems, ...
                    tSourceStructure.scan(files(i))]; %#ok<AGROW>
            end

            testCase.verifyEmpty(problems, ...
                sprintf(['Block-structure problems (a mis-nested methods ' ...
                         'block makes a test class vanish silently):\n%s'], ...
                        strjoin(problems, newline)));
        end

        function everyGuiTestClassCanDriveAGesture(testCase)
            %   A tGui2* file that extends matlab.unittest.TestCase instead
            %   of matlab.uitest.TestCase looks completely normal until it
            %   runs, and then every test in it ERRORS with "Unrecognized
            %   method, property, or field 'press'". The file is about
            %   driving a real app; press/choose/type are the whole point,
            %   and they live on the uitest base class only.
            files = tSourceStructure.sourceFiles();
            wrong = string.empty(1, 0);
            for i = 1:numel(files)
                [~, name] = fileparts(files(i));
                if ~startsWith(name, "tGui2")
                    continue
                end
                txt = string(fileread(files(i)));
                if ~contains(txt, "matlab.uitest.TestCase")
                    wrong(end + 1) = name; %#ok<AGROW>
                end
            end
            testCase.verifyEmpty(wrong, sprintf( ...
                ['These tGui2* classes cannot drive a gesture (they need ' ...
                 'matlab.uitest.TestCase, not matlab.unittest.TestCase): ' ...
                 '%s'], strjoin(wrong, ", ")));
        end

        function theScannerActuallyCatchesAMisNestedBlock(testCase)
            % A guard on the guard. A checker that silently matches nothing
            % would pass this suite forever while protecting nothing, which
            % is precisely the failure it exists to prevent.
            bad = fullfile(tempname + ".m");
            fid = fopen(bad, 'w');
            fprintf(fid, 'classdef broken\n    methods\n        function a(~)\n        end\n');
            fprintf(fid, '    methods\n        function b(~)\n        end\n    end\n    end\nend\n');
            fclose(fid);
            testCase.addTeardown(@() delete(bad));

            found = tSourceStructure.scan(string(bad));

            testCase.verifyNotEmpty(found, ...
                'The scanner must flag a methods block nested inside another.');
            testCase.verifyTrue(any(contains(found, "NESTING")));
        end
    end

    methods (Static, Access = private)
        function files = sourceFiles()
            %SOURCEFILES  Every .m under matlab/, packages and tests included.
            here = fileparts(fileparts(mfilename("fullpath")));   % .../matlab
            d = dir(fullfile(here, "**", "*.m"));
            files = string.empty(1, 0);
            for i = 1:numel(d)
                if ~d(i).isdir
                    files(end + 1) = string(fullfile(d(i).folder, d(i).name)); %#ok<AGROW>
                end
            end
        end

        function problems = scan(file)
            %SCAN  One file's block stack. Returns a string per problem.
            problems = string.empty(1, 0);
            txt = string(splitlines(fileread(file)));
            [~, name, ext] = fileparts(file);
            short = name + ext;

            kinds = string.empty(1, 0);   % the open-block stack
            lines = [];

            for n = 1:numel(txt)
                t = strtrim(txt(n));
                if t == "" || startsWith(t, "%")
                    continue
                end
                t = regexprep(t, '\s*\.\.\..*$', '');   % drop continuations

                kw = tSourceStructure.opener(t);
                if strlength(kw) > 0
                    % "if x, y; end" opens and closes on one line.
                    if ~isempty(regexp(t, '[,;]\s*end\s*;?\s*(%.*)?$', 'once'))
                        continue
                    end
                    if any(kw == tSourceStructure.ClassOnly)
                        if isempty(kinds) || kinds(end) ~= "classdef"
                            if isempty(kinds)
                                where = "nothing";
                            else
                                where = sprintf("%s (line %d)", kinds(end), lines(end));
                            end
                            problems(end + 1) = sprintf( ...
                                "%s:%d: NESTING: '%s' opened inside %s - must sit directly in classdef", ...
                                short, n, kw, where); %#ok<AGROW>
                        end
                    end
                    kinds(end + 1) = kw;   %#ok<AGROW>
                    lines(end + 1) = n;    %#ok<AGROW>
                elseif ~isempty(regexp(t, '^end\s*(%.*)?;?\s*$', 'once'))
                    if isempty(kinds)
                        problems(end + 1) = sprintf( ...
                            "%s:%d: 'end' with nothing open", short, n); %#ok<AGROW>
                    else
                        kinds(end) = [];
                        lines(end) = [];
                    end
                end
            end

            for k = 1:numel(kinds)
                problems(end + 1) = sprintf("%s:%d: '%s' never closed", ...
                    short, lines(k), kinds(k)); %#ok<AGROW>
            end
        end

        function kw = opener(t)
            %OPENER  The block keyword this line opens, or "".
            kw = "";
            for candidate = tSourceStructure.Openers
                if ~isempty(regexp(t, "^" + candidate + "\>", 'once'))
                    kw = candidate;
                    return
                end
            end
        end
    end
end
