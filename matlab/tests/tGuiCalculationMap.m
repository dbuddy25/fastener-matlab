classdef tGuiCalculationMap < matlab.uitest.TestCase
    %TGUICALCULATIONMAP  The Calculation Map window.
    %
    %   Run from the matlab/ folder with:
    %       runTests("GuiCalculationMap")
    %
    %   Nothing here clicks an equation: that opens the MATLAB editor. The
    %   click resolves through linkFor, which is checked against the file.

    properties
        App
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (TestMethodSetup)
        function launchApp(testCase)
            testCase.App = gui.FastenerApp();
            testCase.addTeardown(@() delete(testCase.App));
        end
    end

    methods (Test)
        function itOpensAtTheRequestedCheck(testCase)
            v = testCase.App.showCalculationMap("Slip");
            testCase.verifyTrue(v.isOpen());
            testCase.verifyEqual(v.currentCheck(), "Slip");
            testCase.verifyGreaterThan(v.linkCount(), 0);
        end

        function mermaidDrawsEveryCheck(testCase)
            % The real proof the generated text is valid Mermaid: the page
            % reports back "rendered" or "renderError" for each check.
            for name = engine.calculationMap()
                v = testCase.App.showCalculationMap(name);
                ev = tGuiCalculationMap.waitForRender(v);
                testCase.verifyTrue(startsWith(ev, "rendered"), ...
                    sprintf('%s: %s', name, ev));
            end
        end

        function theTopToBottomLayoutDrawsToo(testCase)
            v = testCase.App.showCalculationMap("Tension-Yield");
            tGuiCalculationMap.waitForRender(v);
            testCase.choose(v.layoutDropDown(), 'Top to bottom');
            ev = tGuiCalculationMap.waitForRender(v);
            testCase.verifyTrue(startsWith(ev, "rendered"), ev);
        end

        function aSecondOpenReusesTheWindow(testCase)
            v1 = testCase.App.showCalculationMap("Slip");
            fig = v1.figureHandle();
            v2 = testCase.App.showCalculationMap("Bearing");
            testCase.verifySameHandle(v2, v1);
            testCase.verifySameHandle(v2.figureHandle(), fig);
            testCase.verifyEqual(v2.currentCheck(), "Bearing");
        end

        function theWindowDiesWithTheApp(testCase)
            app = gui.FastenerApp();
            fig = app.showCalculationMap("Slip").figureHandle();
            delete(app);
            testCase.verifyFalse(isvalid(fig), ...
                'The Calculation Map outlived the app that opened it.');
        end

        function showCalculationOpensTheSelectedCheck(testCase)
            c = validation.dabjSection9();
            s = testCase.App.State;
            s.Joint = c.Joint;  s.LoadCase = c.LoadCase;  s.Factors = c.Factors;
            s.setResult(engine.analyze(c.Joint, c.LoadCase, c.Factors));
            testCase.App.navigateTo("Results");
            page = testCase.App.page("Results");
            % Results pre-selects the first failing row: Slip, here.
            testCase.press(page.calcButton());
            v = testCase.App.calculationMapView();
            testCase.assertNotEmpty(v, 'Show calculation opened nothing.');
            testCase.verifyEqual(v.currentCheck(), "Slip");

            % Row 3 of the table is Shear-Ultimate.
            page.selectRow(3);
            testCase.press(page.calcButton());
            testCase.verifyEqual(v.currentCheck(), "Shear-Ultimate");
        end

        function everyClickTargetIsARealLine(testCase)
            for name = engine.calculationMap()
                [txt, links] = gui.CalculationMapView.mermaidText(engine.calculationMap(name));
                testCase.verifyTrue(startsWith(txt, "flowchart LR"));
                for k = links
                    n = numel(splitlines(string(fileread(k.File))));
                    testCase.verifyLessThanOrEqual(k.Line, n, ...
                        sprintf('%s: %s points past the end of %s.', name, k.Id, k.File));
                    testCase.verifySubstring(txt, "click " + k.Id + " call openNode");
                end
            end
        end
    end

    methods (Static, Access = private)
        function ev = waitForRender(v)
            t0 = tic;
            ev = "";
            while toc(t0) < 20
                drawnow
                ev = v.lastEvent();
                if startsWith(ev, ["rendered", "renderError"])
                    return
                end
                pause(0.2)
            end
            ev = "timed out waiting for the page";
        end
    end
end
