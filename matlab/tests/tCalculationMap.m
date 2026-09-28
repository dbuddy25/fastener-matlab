classdef tCalculationMap < matlab.unittest.TestCase
    %TCALCULATIONMAP  engine.calculationMap reads each check's chain from the code.
    %
    %   Run from the matlab/ folder with:
    %       runTests("CalculationMap")

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function everyCheckTheEngineReportsHasAMap(testCase)
            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            testCase.verifyEqual(sort(engine.calculationMap()), sort([r.Margins.Name]), ...
                'engine.calculationMap and engine.analyze disagree on the checks.');
            for name = [r.Margins.Name]
                m = engine.calculationMap(name);
                testCase.verifyEqual(nnz([m.Nodes.IsCheck]), 1, name + ": no check node.");
                eqs = [m.Nodes.Equations];
                testCase.verifyNotEmpty(eqs, name + " has no equations on its map.");
            end
        end

        function everyEquationLinkPointsAtItsEquation(testCase)
            n = 0;
            for name = engine.calculationMap()
                m = engine.calculationMap(name);
                for node = m.Nodes
                    lines = splitlines(string(fileread(node.File)));
                    for e = node.Equations
                        n = n + 1;
                        testCase.verifySubstring(lines(e.Line), extractBefore(e.Reference + " ", " "), ...
                            sprintf('%s:%d does not hold "%s".', node.File, e.Line, e.Reference));
                        testCase.verifySubstring(lines(e.Line), "=");
                    end
                end
            end
            testCase.verifyGreaterThan(n, 30, 'The equation scan found almost nothing.');
        end

        function knownLinksAreFound(testCase)
            testCase.verifyTrue(tCalculationMap.has("Slip", "preload"));
            testCase.verifyTrue(tCalculationMap.has("Separation", "designLoads"));
            testCase.verifyTrue(tCalculationMap.has("Tension-Ultimate", "systemTensileAllowable"));
            testCase.verifyTrue(tCalculationMap.has("Tension-Ultimate", "stiffness"));
            testCase.verifyTrue(tCalculationMap.has("Tension-Yield", "shearYieldStrength"));
            testCase.verifyTrue(tCalculationMap.has("Interaction", "boltBendingStress"));
        end

        function everyEdgeJoinsTwoNodesOnTheMap(testCase)
            for name = engine.calculationMap()
                m = engine.calculationMap(name);
                names = [m.Nodes.Name];
                for e = m.Edges
                    testCase.verifyTrue(any(names == e.From) && any(names == e.To), ...
                        sprintf('%s: edge %s -> %s leaves the map.', name, e.From, e.To));
                end
            end
        end

        function anUnknownCheckIsRefused(testCase)
            testCase.verifyError(@() engine.calculationMap("Nope"), ...
                "engine:calculationMap:unknownCheck");
        end
    end

    methods (Static, Access = private)
        function tf = has(check, fn)
            m = engine.calculationMap(check);
            tf = any([m.Nodes.Name] == fn);
        end
    end
end
