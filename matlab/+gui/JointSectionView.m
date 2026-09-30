classdef JointSectionView < handle
    %JOINTSECTIONVIEW  To-scale axial cross-section of the joint.
    %
    %   A NON-MODAL window, opened from Joint Config and kept alive beside
    %   the app. It listens to JointChanged and repaints as the form is
    %   edited, which is the whole point: the mistakes it catches are ones
    %   nobody thinks to go looking for, so a picture you have to remember
    %   to open is a picture that never gets opened.
    %
    %   WHY A WINDOW AND NOT THE RIGHT-HAND COLUMN OF JOINT CONFIG (GUI_SPEC.md
    %   Section 16). That column already ends
    %   in the Analyze button on a scrollable page, so a fifth group renders
    %   below the fold exactly when it is wanted; and it is the 1x of a 2x/1x
    %   split, which cannot show a to-scale section with per-flange labels.
    %   DataAspectRatio forbids cheating the width. Repainting on
    %   JointChanged recovers what inline hosting was for.
    %
    %   Coordinates are in data units (inches), never pixels; a
    %   pixel-scaling layer would be ~170 lines. x is radial (0 on the
    %   centerline, symmetric); y is axial, measured down from the
    %   under-head bearing plane, with the axis YDir reversed so the head
    %   sits at the top and the stack reads head-to-tail like Joint
    %   Config's left column.
    %
    %   LABELS LIVE IN LADDERS, NOT ON THE DRAWING. Text is sized in points
    %   and the geometry in inches, so a label anchored at a 0.03 in washer
    %   overlaps its neighbours at any zoom. Every callout therefore sits
    %   in a column to the RIGHT of the section, one per row, spread apart
    %   by spreadRows() and tied to its feature by a leader; dimension
    %   lines (grip, L, Lmin, Le) sit in columns to the LEFT, packed by
    %   packColumns() so non-overlapping spans share a column, with their
    %   values in spread rows beyond them. The only pixel arithmetic in
    %   the file is frame(), which reserves room for that text from the
    %   axes' real pixel size - so the window repaints on resize.
    %
    %   THREE DIMENSIONS IN THIS DRAWING ARE NOT DATA. The model carries no
    %   bolt head height, no head across-flats and no nut hex geometry, and
    %   neither does the library - see HeadHeightFactor below. They are
    %   drawing conventions, they are listed in the window's own note line,
    %   and nothing computed from them is ever shown as a number. A flange
    %   drawn to an assumed half-width gets a dashed outer edge so an
    %   invented dimension can never be read as a measured one.
    %
    %   IT COMPUTES NO ENGINEERING VALUES. Grip, required length and thread
    %   engagement come from engine.boltLengthCheck, not from arithmetic
    %   here, for the same reason ResultsPage refuses to call
    %   engine.preload: a second implementation is a second answer. The
    %   shear-plane condition it shows is a CONSISTENCY flag - the declared
    %   Joint.ShearPlane against where the drawn thread starts - and never
    %   alters the declaration. layout() is a pure function of a
    %   model.Joint and is where every coordinate is decided, so the
    %   geometry is testable without a figure on screen.
    %
    %   IT MUST NEVER THROW. It repaints on every commit, against joints
    %   that are half-filled by definition. Everything unknown degrades to
    %   "not drawn" plus a line in the note; nothing raises.

    properties (Constant, Access = private)
        % DRAWING CONVENTIONS, NOT DATA. model.Bolt has no head height and
        % no across-flats, and library.json has neither for any of the 25
        % shipped bolts. These produce a head that reads as a head at a
        % plausible size. They are surfaced in the note line so the drawing
        % never implies a precision it does not have.
        HeadHeightFactor   = 0.65   % x nominal diameter
        HeadDiameterFactor = 1.5    % x nominal diameter, if no bearing dia
        NutHeightFactor    = 0.875  % x nominal diameter, when Le is unknown
        MemberWidthFactor  = 1.6    % x nominal diameter, half-width of the host

        % Used only when FlangeLayer.EdgeDistance is unset. A flange drawn
        % to this gets a dashed outer edge.
        AssumedFlangeHalfWidth = 2.0   % x nominal diameter

        % Type sizes. Set explicitly rather than left to the uiaxes default,
        % which renders small enough to be unreadable at the window's
        % opening size.
        AxisFontSize  = 11
        LabelFontSize = 12
        AnnotFontSize = 12

        % Screen text metrics, used ONLY to reserve room for the ladders.
        % Points to pixels at the 96 dpi MATLAB assumes for uifigures; the
        % average glyph is about 0.55 em wide in the default sans face.
        PxPerPoint      = 96 / 72
        CharWidthFactor = 0.55
        RowHeightFactor = 1.6    % callout row pitch, x font height

        % Thread teeth are skipped outside this range: below it there is
        % nothing to see, above it the teeth merge into a grey band and the
        % dotted root outline reads better.
        MinThreadTeeth = 2
        MaxThreadTeeth = 120

        % Fill colours. Deliberately muted and few: this is a diagram, not
        % a rendering, and GUI_SPEC.md Section 16 says skip the gradients.
        % Adjacent flanges alternate two greys so a two-layer stack reads
        % as two layers; washers are darker than either.
        BoltFill      = [0.62 0.66 0.72]
        WasherFill    = [0.70 0.72 0.76]
        FlangeFill    = [0.88 0.90 0.93]
        FlangeFillAlt = [0.79 0.82 0.86]
        MemberFill    = [0.72 0.76 0.70]
        EdgeColour    = [0.25 0.27 0.30]

        % Line and text colours for the annotations.
        LeaderColour       = [0.55 0.55 0.58]
        DimColour          = [0.30 0.30 0.33]
        FrustumColour      = [0.55 0.40 0.65]
        EngagementColour   = [0.30 0.45 0.30]
        LoadingPlaneColour = [0.15 0.35 0.65]
        ShearPlaneColour   = [0.20 0.20 0.22]
    end

    properties (Access = private)
        State
        Fig      = matlab.ui.Figure.empty
        Ax
        NoteLabel
        Listener = event.listener.empty(1, 0)
    end

    methods
        function obj = JointSectionView(state)
            arguments
                state (1,1) gui.AppState
            end
            obj.State = state;
        end

        function show(obj)
            %SHOW  Open the window, or raise it if it is already open.
            %   Create-or-focus, so repeated presses of the button on Joint
            %   Config cannot litter the desktop with identical windows.
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                figure(obj.Fig);
                obj.redraw();
                return
            end
            obj.build();
            % Lay the window out before the first paint: frame() reads the
            % axes' pixel size, which is zeros until then.
            drawnow;
            obj.redraw();
        end

        function delete(obj)
            %DELETE  Drop the listener before the figure goes.
            delete(obj.Listener);
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                delete(obj.Fig);
            end
        end
    end

    % ---- Window -----------------------------------------------------------
    methods (Access = private)
        function build(obj, visible)
            arguments
                obj
                visible (1,1) logical = true
            end
            % Wide: the section is height-limited (DataAspectRatio), so
            % width is what buys room for the two ladders at a readable
            % scale. Clamped to the screen so it never opens off-screen.
            scr = get(groot, 'ScreenSize');
            w   = min(1400, scr(3) - 80);
            h   = min(750,  scr(4) - 120);
            obj.Fig = uifigure('Name', 'Joint Cross-Section', ...
                'Position', [40 80 w h], ...
                'Visible', matlab.lang.OnOffSwitchState(visible));

            g = uigridlayout(obj.Fig, [2 1]);
            g.RowHeight   = {'1x', 'fit'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];

            obj.Ax = uiaxes(g);
            obj.Ax.Layout.Row    = 1;
            obj.Ax.Layout.Column = 1;

            % The whole reason this is not a pixel-scaling exercise: equal
            % data units on both axes means a to-scale section falls out of
            % drawing in inches.
            obj.Ax.DataAspectRatio = [1 1 1];
            % Head at the top. y counts down the stack from the under-head
            % bearing plane, which is how the joint is described everywhere
            % else in this app.
            obj.Ax.YDir     = 'reverse';
            obj.Ax.Box      = 'off';
            obj.Ax.FontSize = gui.JointSectionView.AxisFontSize;
            % A signed "radius" is a contradiction; the x axis carries no
            % information the section does not, so it is hidden. The y
            % axis is the one worth reading.
            obj.Ax.XAxis.Visible = 'off';
            ylabel(obj.Ax, 'axial position from under-head (in)');

            obj.NoteLabel = uilabel(g, 'WordWrap', 'on', 'Text', '', ...
                'FontSize', gui.JointSectionView.LabelFontSize);
            obj.NoteLabel.Layout.Row    = 2;
            obj.NoteLabel.Layout.Column = 1;
            obj.NoteLabel.FontColor     = gui.palette('mutedText');

            % Repaints as the form is edited - the passive catching that
            % inline hosting was for.
            obj.Listener = event.listener(obj.State, 'JointChanged', ...
                @(~, ~) obj.redraw());

            obj.Fig.CloseRequestFcn = @(~, ~) obj.onClose();
            % Row spacing is in data units derived from the pixel size, so
            % a resize changes the answer. AutoResizeChildren must be off
            % for a uifigure to take a SizeChangedFcn; the grid still lays
            % its children out.
            obj.Fig.AutoResizeChildren = 'off';
            obj.Fig.SizeChangedFcn     = @(~, ~) obj.redraw();
        end

        function onClose(obj)
            %ONCLOSE  Closing the window tears the view down with it.
            %   The listener must go too, or an edit after the window is
            %   gone fires into a deleted axes.
            delete(obj.Listener);
            obj.Listener = event.listener.empty(1, 0);
            delete(obj.Fig);
        end

        function redraw(obj)
            %REDRAW  Rebuild the whole picture from AppState.Joint.
            %   WRAPPED, and it has to be. This runs on every commit against
            %   joints that are half-filled by definition; a throw here would
            %   surface as the Joint Config edit itself failing.
            if isempty(obj.Fig) || ~isvalid(obj.Fig)
                return
            end
            try
                g = gui.JointSectionView.layout(obj.State.Joint);
                obj.paint(g);
            catch err
                cla(obj.Ax);
                obj.NoteLabel.Text = sprintf('Section not drawn: %s', err.message);
            end
        end
    end

    % ---- Painting ---------------------------------------------------------
    methods (Access = private)
        function paint(obj, g)
            cla(obj.Ax);
            hold(obj.Ax, 'on');

            if ~g.Ok
                obj.NoteLabel.Text = gui.JointSectionView.joinNotes(g.Notes);
                hold(obj.Ax, 'off');
                return
            end

            obj.paintClampedStack(g);
            obj.paintBolt(g);
            obj.paintFrustum(g);
            obj.paintEngagement(g);
            obj.paintShearPlanes(g);
            obj.paintLoadingPlane(g);

            % Centreline last so it sits over the fills.
            plot(obj.Ax, [0 0], [g.YTop g.YBottom], '-.', ...
                'Color', [0.45 0.45 0.50], 'LineWidth', 0.5);

            fr = obj.frame(g);
            obj.paintCallouts(g, fr);
            obj.paintDims(g, fr);

            obj.Ax.XLim = fr.XLim;
            obj.Ax.YLim = g.YLim;
            obj.NoteLabel.Text = gui.JointSectionView.joinNotes(g.Notes);
            hold(obj.Ax, 'off');
        end

        function paintClampedStack(obj, g)
            %PAINTCLAMPEDSTACK  Washers, flanges and the threaded host.
            %   Everything here is an annulus in section: two rectangles,
            %   left and right of a real clearance hole. Drawing one solid
            %   block and putting the bolt on top of it would hide exactly
            %   the thing this view exists to show - whether the hole and
            %   the bolt in it are plausible. Names go to the callout
            %   ladder, never onto the drawing.
            for k = 1:numel(g.Bands)
                b = g.Bands(k);
                if b.OuterR <= b.InnerR || b.Height <= 0
                    continue
                end
                style = '-';
                if b.WidthAssumed
                    % An invented width must never read as a measured one.
                    style = '--';
                end
                obj.band(b.InnerR, b.OuterR, b.Y0, b.Height, b.Fill, style);
            end
        end

        function band(obj, innerR, outerR, y0, h, fill, style)
            %BAND  One annular layer in section: mirrored left and right.
            w = outerR - innerR;
            rectangle(obj.Ax, 'Position', [innerR, y0, w, h], ...
                'FaceColor', fill, 'EdgeColor', obj.EdgeColour, ...
                'LineStyle', style, 'LineWidth', 0.5);
            rectangle(obj.Ax, 'Position', [-outerR, y0, w, h], ...
                'FaceColor', fill, 'EdgeColor', obj.EdgeColour, ...
                'LineStyle', style, 'LineWidth', 0.5);
        end

        function paintBolt(obj, g)
            %PAINTBOLT  Head, then shank, then the threaded length.
            b = g.Bolt;

            rectangle(obj.Ax, 'Position', ...
                [-b.HeadR, b.HeadTop, 2 * b.HeadR, b.HeadHeight], ...
                'FaceColor', obj.BoltFill, 'EdgeColor', obj.EdgeColour, ...
                'LineWidth', 0.5);

            % The unthreaded run only. Drawing the shank full length and
            % the thread over it left the crests buried under the shank fill.
            if b.ShankLength > 0
                rectangle(obj.Ax, 'Position', ...
                    [-b.ShankR, 0, 2 * b.ShankR, b.ShankLength], ...
                    'FaceColor', obj.BoltFill, 'EdgeColor', obj.EdgeColour, ...
                    'LineWidth', 0.5);
            end

            if b.ThreadLength <= 0
                return
            end

            % The root cylinder, always. Teeth ride on top of it when the
            % thread data supports them.
            rectangle(obj.Ax, 'Position', ...
                [-b.ThreadR, b.ThreadTop, 2 * b.ThreadR, b.ThreadLength], ...
                'FaceColor', obj.BoltFill, 'EdgeColor', obj.EdgeColour, ...
                'LineStyle', ':', 'LineWidth', 0.5);

            if b.Thread.Ok
                plot(obj.Ax, b.Thread.R, b.Thread.Y, '-', ...
                    'Color', obj.EdgeColour, 'LineWidth', 0.5);
                plot(obj.Ax, -b.Thread.R, b.Thread.Y, '-', ...
                    'Color', obj.EdgeColour, 'LineWidth', 0.5);
            end
        end

        function paintFrustum(obj, g)
            %PAINTFRUSTUM  The compression cone, at the user's half-angle.
            %   Two polylines rather than four lines: the profile is one
            %   path per side. Named in the callout ladder.
            if ~g.Frustum.Ok
                return
            end
            f = g.Frustum;
            plot(obj.Ax, f.R, f.Y, '--', 'Color', obj.FrustumColour, 'LineWidth', 1);
            plot(obj.Ax, -f.R, f.Y, '--', 'Color', obj.FrustumColour, 'LineWidth', 1);
        end

        function paintEngagement(obj, g)
            %PAINTENGAGEMENT  Where the threads stop inside the parent.
            %   The parent's own depth is a convention; this line is data,
            %   and it is the number that governs thread shear. Drawn so the
            %   two can never be confused for each other.
            if ~g.Engagement.Ok
                return
            end
            e = g.Engagement;
            plot(obj.Ax, [-e.R e.R], [e.Y e.Y], '--', ...
                'Color', obj.EngagementColour, 'LineWidth', 1);
        end

        function paintShearPlanes(obj, g)
            %PAINTSHEARPLANES  Every interface load can shear across.
            %   Amber when the declared Joint.ShearPlane disagrees with the
            %   bolt section the line actually cuts.
            for k = 1:numel(g.ShearPlanes)
                s = g.ShearPlanes(k);
                if s.Mismatch
                    col = gui.palette('statusWarn');
                else
                    col = obj.ShearPlaneColour;
                end
                plot(obj.Ax, [-s.HalfWidth s.HalfWidth], [s.Y s.Y], '-', ...
                    'Color', col, 'LineWidth', 1.5);
            end
        end

        function paintLoadingPlane(obj, g)
            %PAINTLOADINGPLANE  n x grip, measured from the grip top.
            %   Turns red when it lands outside the grip, which is one of
            %   the four things this view exists to catch.
            if ~g.LoadingPlane.Ok
                return
            end
            lp = g.LoadingPlane;
            if lp.Outside
                col = gui.palette('statusFail');
            else
                col = obj.LoadingPlaneColour;
            end
            plot(obj.Ax, [-lp.HalfWidth lp.HalfWidth], [lp.Y lp.Y], '-', ...
                'Color', col, 'LineWidth', 1.25);
        end

        function fr = frame(obj, g)
            %FRAME  Reserve room either side of the section for the text.
            %   THE ONE PLACE PIXELS ENTER. Text is in points and the
            %   section in inches, so how much x-range a label needs
            %   depends on the zoom - which depends on the x-range. Three
            %   passes settle it; the answer only has to be roomy, not
            %   exact.
            ip = obj.Ax.InnerPosition;
            W  = ip(3);
            H  = ip(4);
            if ~isfinite(W) || ~isfinite(H) || W < 80 || H < 80
                % Not laid out yet (hidden figure). Estimate from the window:
                % grid padding, the y-axis rule and labels, the note row.
                fp = obj.Fig.Position;
                W  = max(fp(3) - 16 - 70, 200);
                H  = max(fp(4) - 16 - 60, 200);
            end
            fontPx = gui.JointSectionView.AnnotFontSize * gui.JointSectionView.PxPerPoint;

            maxChars = 0;
            if ~isempty(g.Callouts)
                maxChars = max(strlength([g.Callouts.Text]));
            end
            nDims  = numel(g.Dims);
            nCols  = 0;
            dimChars = 0;
            if nDims > 0
                nCols    = max(gui.JointSectionView.packColumns([g.Dims.Y0], [g.Dims.Y1]));
                dimChars = max(strlength([g.Dims.Text]));
            end

            leader = 0.35 * g.Scale;
            xl     = g.XLim;
            yr     = diff(g.YLim);
            s      = min(W / diff(xl), H / yr);          % px per inch
            colGap = 0.18 * g.Scale;
            for pass = 1:3
                textW  = gui.JointSectionView.CharWidthFactor * fontPx * maxChars / s;
                dimW   = gui.JointSectionView.CharWidthFactor * fontPx * dimChars / s;
                textH  = 1.2 * fontPx / s;
                right  = g.XLim(2);
                if maxChars > 0
                    right = g.XLim(2) + leader + textW + 0.10 * g.Scale;
                end
                left = g.XLim(1);
                if nCols > 0
                    left = g.XLim(1) - 0.10 * g.Scale - nCols * colGap - dimW - 0.10 * g.Scale;
                end
                xl = [left right];
                s  = min(W / diff(xl), H / yr);
            end

            fr = struct('XLim', xl, 'PxPerIn', s, ...
                'RowH', gui.JointSectionView.RowHeightFactor * fontPx / s, ...
                'TextH', textH, 'ColGap', colGap, ...
                'LadderX', g.XLim(2) + leader, ...
                'DimX0', g.XLim(1) - 0.10 * g.Scale);
        end

        function paintCallouts(obj, g, fr)
            %PAINTCALLOUTS  The right-hand ladder: one row per feature.
            %   Rows are spread so no two labels share a line, then each
            %   is tied back to its anchor with a leader. Labels never sit
            %   on the section.
            if isempty(g.Callouts)
                return
            end
            ys   = [g.Callouts.Y];
            rows = gui.JointSectionView.spreadRows(ys, fr.RowH, ...
                g.YLim(1) + fr.RowH / 2, g.YLim(2) - fr.RowH / 2);
            xText = fr.LadderX;
            xEnd  = xText - 0.06 * g.Scale;
            for k = 1:numel(g.Callouts)
                c = g.Callouts(k);
                plot(obj.Ax, [c.AnchorR, xEnd], [c.Y, rows(k)], '-', ...
                    'Color', obj.LeaderColour, 'LineWidth', 0.5);
                plot(obj.Ax, c.AnchorR, c.Y, '.', ...
                    'Color', obj.LeaderColour, 'MarkerSize', 7);
                text(obj.Ax, xText, rows(k), char(c.Text), ...
                    'FontSize', gui.JointSectionView.AnnotFontSize, ...
                    'Color', c.Color, 'Interpreter', 'none', ...
                    'HorizontalAlignment', 'left', ...
                    'VerticalAlignment', 'middle', 'Clipping', 'off');
            end
        end

        function paintDims(obj, g, fr)
            %PAINTDIMS  The left-hand dimension ladder.
            %   Drafting-style lines with end ticks, packed into columns so
            %   spans that do not overlap share one. The values are
            %   horizontal text in rows to the left of the columns - spread
            %   apart like the callouts, since a value is often longer than
            %   the span it measures - each tied to its line by a leader.
            if isempty(g.Dims)
                return
            end
            cols  = gui.JointSectionView.packColumns([g.Dims.Y0], [g.Dims.Y1]);
            nCols = max(cols);
            tick  = 0.06 * g.Scale;
            mids  = ([g.Dims.Y0] + [g.Dims.Y1]) / 2;
            rows  = gui.JointSectionView.spreadRows(mids, fr.RowH, ...
                g.YLim(1) + fr.RowH / 2, g.YLim(2) - fr.RowH / 2);
            xText = fr.DimX0 - (nCols - 1) * fr.ColGap - 0.10 * g.Scale;
            for k = 1:numel(g.Dims)
                d = g.Dims(k);
                x = fr.DimX0 - (cols(k) - 1) * fr.ColGap;
                plot(obj.Ax, [x x], [d.Y0 d.Y1], d.LineStyle, ...
                    'Color', d.Color, 'LineWidth', 0.75);
                plot(obj.Ax, [x - tick, x + tick], [d.Y0 d.Y0], '-', ...
                    'Color', d.Color, 'LineWidth', 0.75);
                plot(obj.Ax, [x - tick, x + tick], [d.Y1 d.Y1], '-', ...
                    'Color', d.Color, 'LineWidth', 0.75);
                plot(obj.Ax, [x - tick, xText + 0.03 * g.Scale], [mids(k), rows(k)], '-', ...
                    'Color', obj.LeaderColour, 'LineWidth', 0.5);
                text(obj.Ax, xText, rows(k), char(d.Text), ...
                    'FontSize', gui.JointSectionView.AnnotFontSize, ...
                    'Color', d.Color, 'Interpreter', 'none', ...
                    'HorizontalAlignment', 'right', ...
                    'VerticalAlignment', 'middle', 'Clipping', 'off');
            end
        end
    end

    % ---- Geometry ---------------------------------------------------------
    methods (Static)
        function writeImage(joint, file)
            %WRITEIMAGE  Draw joint off-screen and save it as an image.
            %   exportgraphics on the axes, not exportapp on the window:
            %   exportapp has failed on busy app states.
            arguments
                joint (1,1) model.Joint
                file  (1,1) string
            end
            s = gui.AppState();
            s.Joint = joint;
            v = gui.JointSectionView(s);
            closer = onCleanup(@() delete(v));
            v.build(false);
            v.redraw();
            exportgraphics(v.Ax, file, 'Resolution', 200);
        end

        function g = layout(joint)
            %LAYOUT  A model.Joint -> every coordinate the drawing needs.
            %   PURE, and public, so the geometry can be tested without a
            %   figure. Returns g.Ok false plus g.Notes when there is not
            %   enough to draw; never throws.
            %
            %   Grip, required length and engagement come from
            %   engine.boltLengthCheck rather than being recomputed here -
            %   one implementation, one answer.
            % Built field by field, not in one struct(...) call: a struct
            % array passed as a value there does not mean what it looks
            % like it means, and Bands is a struct array.
            g              = struct();
            g.Ok           = false;
            g.Notes        = string.empty(1, 0);
            g.Bands        = gui.JointSectionView.emptyBands();
            g.Callouts     = gui.JointSectionView.emptyCallouts();
            g.Dims         = gui.JointSectionView.emptyDims();
            g.ShearPlanes  = gui.JointSectionView.emptyShearPlanes();
            g.Scale        = 1;
            g.XLim         = [-1 1];
            g.YLim         = [-1 1];
            g.YTop         = 0;
            g.YBottom      = 0;
            g.Bolt         = struct();
            g.Frustum      = struct('Ok', false, 'R', [], 'Y', [], 'Angle', NaN);
            g.LoadingPlane = struct('Ok', false, 'Y', NaN, ...
                                    'Outside', false, 'HalfWidth', 0);
            g.Engagement   = struct('Ok', false, 'Y', NaN, 'R', 0, 'Le', NaN);

            if isempty(joint) || ~isa(joint, 'model.Joint')
                g.Notes(end + 1) = "No joint.";
                return
            end

            D = joint.Bolt.NominalDiameter;
            if ~isfinite(D) || D <= 0
                g.Notes(end + 1) = "No bolt selected.";
                return
            end
            g.Scale = D;

            if isempty(joint.FlangeStack)
                g.Notes(end + 1) = "No flange layers.";
            end

            chk = gui.JointSectionView.lengthCheck(joint);

            % ---- the clamped stack, head to tail ----
            bands = gui.JointSectionView.emptyBands();
            y = 0;

            hw = joint.HeadWasher;
            if gui.JointSectionView.washerPresent(hw)
                [b, y] = gui.JointSectionView.washerBand(hw, D, y, "washer (head)");
                bands(end + 1) = b;
            end

            gripTop = y;
            nFl     = numel(joint.FlangeStack);
            flangeIdx = zeros(1, nFl);
            for k = 1:nFl
                f  = joint.FlangeStack(k);
                hr = gui.JointSectionView.holeRadius(f, D);

                halfW   = f.EdgeDistance;
                assumed = ~isfinite(halfW) || halfW <= hr;
                if assumed
                    halfW = gui.JointSectionView.AssumedFlangeHalfWidth * D;
                end

                label = f.Name;
                if strlength(label) == 0
                    label = sprintf('flange %d', k);
                end
                fill = gui.JointSectionView.FlangeFill;
                if mod(k, 2) == 0
                    fill = gui.JointSectionView.FlangeFillAlt;
                end

                bands(end + 1) = gui.JointSectionView.bandStruct(y, f.Thickness, ...
                    hr, halfW, fill, string(label), assumed); %#ok<AGROW>
                flangeIdx(k) = numel(bands);
                y = y + f.Thickness;
            end
            flangeBottom = y;
            gripBottom   = y;

            isNut = joint.ThreadedMember.Type == model.ThreadedMemberType.Nut;

            % A threaded-in joint has no nut washer by convention - the
            % engine only reads HeadWasher on that branch.
            nw = joint.NutWasher;
            if isNut && gui.JointSectionView.washerPresent(nw)
                [b, y] = gui.JointSectionView.washerBand(nw, D, y, "washer (nut)");
                bands(end + 1) = b;
                gripBottom = y;
            end

            [Le, LeIsDefault, engagementNote] = ...
                gui.JointSectionView.engagement(chk, D, isNut);
            if strlength(engagementNote) > 0
                g.Notes(end + 1) = engagementNote;
            end

            memberOuter = joint.ThreadedMember.BearingDiameter / 2;
            if ~isfinite(memberOuter) || memberOuter <= 0
                memberOuter = gui.JointSectionView.MemberWidthFactor * D;
            end
            % HOST HEIGHT IS NOT ENGAGEMENT, except for a nut.
            %   A nut ends where its threads end, so its height IS Le.
            %   A parent - tapped or insert-carrying - is a body of material
            %   that the bolt bites Le into. Drawing it at Le made a tapped
            %   plate look like foil the bolt barely caught.
            %
            % Its thickness t2 is not modelled anywhere (engine.stiffness
            % says so in as many words and assumes h = min(D/2, t2/2) = D/2,
            % i.e. that t2 >= D). So the drawn depth is a convention resting
            % on the engine's own assumption: at least D, and always enough
            % material past the last engaged thread to read as a body.
            if isNut
                memberLabel = "nut";
                hostHeight  = Le;
                hostAssumed = false;
            else
                if joint.ThreadedMember.Type == model.ThreadedMemberType.Insert
                    memberLabel = "insert, parent";
                else
                    memberLabel = "tapped parent";
                end
                hostHeight  = max(Le + D / 2, D);
                hostAssumed = true;
            end

            hostTop = y;
            bands(end + 1) = gui.JointSectionView.bandStruct(y, hostHeight, ...
                gui.JointSectionView.threadRadius(joint, D), memberOuter, ...
                gui.JointSectionView.MemberFill, memberLabel, false);
            memberBottom = y + hostHeight;

            % Where the threads actually stop. Only worth drawing when the
            % host is deeper than the engagement - on a nut the two are the
            % same line and it would just be the band's own edge.
            g.Engagement = struct('Ok', hostAssumed && isfinite(Le) && Le > 0, ...
                'Y', y + Le, 'R', memberOuter, 'Le', Le);
            if hostAssumed
                g.Notes(end + 1) = "Parent depth drawn to t2 ≥ D. " + ...
                    "Dashed line: end of thread engagement.";
            end

            g.Bands = bands;

            % ---- the bolt ----
            [g.Bolt, boltNote] = gui.JointSectionView.boltGeometry(joint, D, memberBottom);
            if strlength(boltNote) > 0
                g.Notes(end + 1) = boltNote;
            end

            % ---- frustum, loading plane ----
            g.Frustum = gui.JointSectionView.frustumProfile( ...
                joint, gripTop, gripBottom, g.Bolt.HeadR);
            g.LoadingPlane = gui.JointSectionView.loadingPlane( ...
                joint, gripTop, gripBottom, memberOuter);
            if g.LoadingPlane.Ok && g.LoadingPlane.Outside
                g.Notes(end + 1) = sprintf( ...
                    "Loading plane outside the grip (n = %.2f).", ...
                    joint.LoadingPlaneFactor);
            end

            % ---- shear planes ----
            [g.ShearPlanes, shearNotes] = gui.JointSectionView.shearPlanes( ...
                joint, bands, flangeIdx, flangeBottom, memberOuter, isNut, g.Bolt);
            g.Notes = [g.Notes, shearNotes];

            % ---- extents ----
            outerR = max([bands.OuterR, g.Bolt.HeadR, memberOuter]);
            g.YTop    = g.Bolt.HeadTop;
            % TotalLength, not ShankLength: the latter is the unthreaded
            % run, and clipping the axis to it would cut off the threads.
            g.YBottom = max(memberBottom, g.Bolt.TotalLength);
            pad = 0.25 * D;
            g.XLim = [-(outerR + pad), outerR + pad];
            g.YLim = [g.YTop - pad, g.YBottom + pad];

            % ---- callouts (right ladder) ----
            g.Callouts = gui.JointSectionView.callouts(g, joint);

            % ---- dimensions (left ladder) ----
            [g.Dims, dimNotes] = gui.JointSectionView.dims( ...
                chk, joint, gripTop, gripBottom, hostTop, Le, LeIsDefault, g.Bolt);
            g.Notes = [g.Notes, dimNotes];

            g.Notes = [g.Notes, gui.JointSectionView.conventionNote(bands)];
            g.Ok = true;
        end

        function y = spreadRows(y0, rowH, yMin, yMax)
            %SPREADROWS  Push label rows apart so none overlap.
            %   Sorted by anchor, each row is moved down until it clears
            %   the one above by rowH; if the last row then falls past
            %   yMax the stack is walked back up. Order is preserved, so a
            %   leader never crosses another's anchor. Pure.
            arguments
                y0   (1,:) double
                rowH (1,1) double
                yMin (1,1) double
                yMax (1,1) double
            end
            n = numel(y0);
            y = y0;
            if n == 0
                return
            end
            [ys, order] = sort(y0);
            ys(1) = max(ys(1), yMin);
            for i = 2:n
                ys(i) = max(ys(i), ys(i - 1) + rowH);
            end
            if ys(end) > yMax
                ys(end) = yMax;
                for i = (n - 1):-1:1
                    ys(i) = min(ys(i), ys(i + 1) - rowH);
                end
            end
            y(order) = ys;
        end

        function col = packColumns(y0, y1)
            %PACKCOLUMNS  First-fit column for each span, so spans that do
            %   not overlap share a column. Column 1 is nearest the
            %   section. Pure.
            arguments
                y0 (1,:) double
                y1 (1,:) double
            end
            n   = numel(y0);
            lo  = min(y0, y1);
            hi  = max(y0, y1);
            col = zeros(1, n);
            for i = 1:n
                c = 1;
                while true
                    taken = col == c;
                    if ~any(taken & (lo < hi(i)) & (hi > lo(i)))
                        col(i) = c;
                        break
                    end
                    c = c + 1;
                end
            end
        end
    end

    % ---- Geometry helpers -------------------------------------------------
    methods (Static, Access = private)
        function b = emptyBands()
            b = struct('Y0', {}, 'Height', {}, 'InnerR', {}, ...
                       'OuterR', {}, 'Fill', {}, 'Label', {}, ...
                       'WidthAssumed', {});
        end

        function b = bandStruct(y0, h, innerR, outerR, fill, label, assumed)
            b = struct('Y0', y0, 'Height', h, 'InnerR', innerR, ...
                       'OuterR', outerR, 'Fill', fill, 'Label', string(label), ...
                       'WidthAssumed', logical(assumed));
        end

        function c = emptyCallouts()
            c = struct('Y', {}, 'AnchorR', {}, 'Text', {}, 'Color', {});
        end

        function c = calloutStruct(y, anchorR, txt, color)
            c = struct('Y', y, 'AnchorR', anchorR, 'Text', string(txt), 'Color', color);
        end

        function d = emptyDims()
            d = struct('Y0', {}, 'Y1', {}, 'Text', {}, 'Color', {}, 'LineStyle', {});
        end

        function d = dimStruct(y0, y1, txt, color, style)
            d = struct('Y0', y0, 'Y1', y1, 'Text', string(txt), ...
                       'Color', color, 'LineStyle', style);
        end

        function s = emptyShearPlanes()
            s = struct('Y', {}, 'HalfWidth', {}, 'Condition', {}, 'Mismatch', {});
        end

        function s = joinNotes(notes)
            s = char(strjoin(notes, '  ·  '));
        end

        function chk = lengthCheck(joint)
            %LENGTHCHECK  engine.boltLengthCheck, or empty on a half-filled joint.
            %   The engine owns grip, required length and the
            %   ratio-over-length engagement precedence. Everything this
            %   drawing prints as a number comes from here.
            chk = [];
            try
                chk = engine.boltLengthCheck(joint);
            catch
                % Half-filled joint. Callers fall back to drawing defaults.
            end
        end

        function tf = washerPresent(w)
            %WASHERPRESENT  model.Washer has no Present flag.
            %   A washer is absent iff it is untouched at its model default:
            %   zero thickness and both diameters unset.
            tf = w.Thickness > 0 || ~isnan(w.OuterDiameter) || ...
                 ~isnan(w.InnerDiameter);
        end

        function [b, yNext] = washerBand(w, D, y, label)
            outerR = w.OuterDiameter / 2;
            if ~isfinite(outerR) || outerR <= 0
                outerR = 1.1 * D;
            end
            innerR = w.InnerDiameter / 2;
            if ~isfinite(innerR) || innerR <= 0
                innerR = 0.54 * D;
            end
            t = w.Thickness;
            if ~isfinite(t) || t <= 0
                t = 0.06 * D;
            end
            b = gui.JointSectionView.bandStruct(y, t, innerR, outerR, ...
                gui.JointSectionView.WasherFill, label, false);
            yNext = y + t;
        end

        function r = holeRadius(f, D)
            r = f.HoleDiameter / 2;
            if ~isfinite(r) || r <= 0
                % A clearance hole, not an interference fit: the gap has to
                % be visible or the drawing implies the bolt fills the hole.
                r = 0.53 * D;
            end
        end

        function r = threadRadius(joint, D)
            r = joint.Bolt.MinorDiameter / 2;
            if ~isfinite(r) || r <= 0
                r = 0.42 * D;
            end
        end

        function [Le, isDefault, note] = engagement(chk, D, isNut)
            %ENGAGEMENT  Thread engagement, from the engine where possible.
            %   engine.boltLengthCheck owns the ratio-over-length precedence
            %   and the 1.5D fallback. Replicating it here would be a second
            %   implementation of an engineering quantity.
            note      = "";
            Le        = NaN;
            isDefault = false;
            if ~isempty(chk)
                Le = chk.Engagement;
            end
            if ~isfinite(Le) || Le <= 0
                Le        = gui.JointSectionView.NutHeightFactor * D;
                isDefault = true;
                if isNut
                    note = "Nut height: drawing default, no engagement set.";
                else
                    note = "Engagement depth: drawing default, none set.";
                end
            end
        end

        function [b, note] = boltGeometry(joint, D, memberBottom)
            %BOLTGEOMETRY  Head, shank and thread, in axial coordinates.
            %   y = 0 is the under-head bearing plane, so the head is at
            %   NEGATIVE y and the shank runs positive down the stack.
            note  = "";
            headR = joint.Bolt.HeadBearingDiameter / 2;
            conv  = gui.JointSectionView.HeadDiameterFactor * D / 2;
            if ~isfinite(headR) || headR <= 0
                headR = conv;
            else
                % The bearing face is the load-carrying annulus, not the
                % outside of the head; drawing the head at exactly the
                % bearing diameter makes every head look undersized.
                headR = max(headR, conv);
            end

            headH = gui.JointSectionView.HeadHeightFactor * D;

            shankR = joint.Bolt.BodyDiameter / 2;
            if ~isfinite(shankR) || shankR <= 0
                shankR = D / 2;
            end
            threadR = gui.JointSectionView.threadRadius(joint, D);

            % Bolt.Length is under-head to tip. With no length set, draw the
            % shank to the bottom of what it threads into so the picture
            % still closes - and say so in the note.
            L = joint.Bolt.Length;
            if ~isfinite(L) || L <= 0
                L    = memberBottom;
                note = "No bolt length set: shank drawn to the bottom of the threaded member.";
            end

            % ThreadLength is measured FROM THE TIP.
            tl = joint.Bolt.ThreadLength;
            if ~isfinite(tl) || tl <= 0
                tl = 0;
            end
            tl = min(tl, L);
            threadKnown = tl > 0;

            % Joint.BodyLengthInGrip (L1) is what the engine analyses when
            % it is set (engine.stiffness, level 1 of its precedence): the
            % unthreaded body ends L1 below the head. The drawing follows
            % the engine, so the thread it shows is the thread the margins
            % assume - which is what the shear-plane check reads.
            L1 = joint.BodyLengthInGrip;
            if isfinite(L1) && L1 >= 0 && L1 < L
                if abs((L - tl) - L1) > 1e-6
                    note = strtrim(note + " " + sprintf( ...
                        "Thread drawn from L1 = %.3f (body length in grip).", L1));
                end
                tl          = L - L1;
                threadKnown = true;
            end

            b = struct( ...
                'HeadR', headR, 'HeadHeight', headH, 'HeadTop', -headH, ...
                'ShankR', shankR, ...
                'TotalLength', L, ...
                'ShankLength', L - tl, ...
                'ThreadR', threadR, 'ThreadLength', tl, 'ThreadTop', L - tl, ...
                'ThreadKnown', threadKnown, ...
                'MajorR', D / 2, ...
                'Thread', gui.JointSectionView.threadProfile( ...
                              joint, D, L - tl, tl, threadR));
        end

        function t = threadProfile(joint, D, yTop, len, minorR)
            %THREADPROFILE  Real thread teeth, when the thread data supports them.
            %   Not a convention: pitch is model.Bolt.Pitch (a Dependent
            %   property, = 1/ThreadsPerInch) and the crest and root radii
            %   are NominalDiameter and MinorDiameter. Every tooth is at its
            %   true axial position, so a 28-TPI thread draws 28 teeth to
            %   the inch and the picture stays to scale.
            %
            %   GUI_SPEC.md Section 16 says to skip coil hatching, and this is not that:
            %   hatching is decoration, whereas a visible pitch is how you
            %   see at a glance that a thread runs where you meant it to.
            %
            %   One polyline per side, whatever the tooth count.
            t = struct('Ok', false, 'R', [], 'Y', [], 'Teeth', 0);
            if ~isfinite(len) || len <= 0
                return
            end
            p = joint.Bolt.Pitch;
            if ~isfinite(p) || p <= 0
                return
            end
            majorR = D / 2;
            if ~isfinite(minorR) || minorR <= 0 || majorR <= minorR
                return
            end

            % Nudged before flooring. A thread length that is an exact whole
            % number of pitches - 0.500 in at 28 TPI is exactly 14 - lands
            % either side of the integer depending on the division, and
            % losing the last tooth to floating point is a silent wrong
            % answer in a picture that claims to be to scale.
            n = floor(len / p + 1e-9);
            if n < gui.JointSectionView.MinThreadTeeth || ...
               n > gui.JointSectionView.MaxThreadTeeth
                return
            end

            % Root, crest, root, crest ... one full tooth per pitch.
            r = zeros(1, 2 * n + 1);
            y = zeros(1, 2 * n + 1);
            for i = 0:(n - 1)
                r(2 * i + 1) = minorR;
                y(2 * i + 1) = yTop + i * p;
                r(2 * i + 2) = majorR;
                y(2 * i + 2) = yTop + (i + 0.5) * p;
            end
            r(end) = minorR;
            y(end) = yTop + n * p;

            t = struct('Ok', true, 'R', r, 'Y', y, 'Teeth', n);
        end

        function f = frustumProfile(joint, gripTop, gripBottom, headR)
            %FRUSTUMPROFILE  The compression cone at the user's half-angle.
            %   Expands from each bearing face toward mid-grip. One polyline
            %   per side; the caller mirrors it.
            f = struct('Ok', false, 'R', [], 'Y', [], 'Angle', NaN);
            h = gripBottom - gripTop;
            if ~isfinite(h) || h <= 0
                return
            end
            ang = joint.FrustumAngle;
            if ~isfinite(ang) || ang <= 0 || ang >= 90
                return
            end
            yMid    = gripTop + h / 2;
            rMid    = headR + tand(ang) * (h / 2);
            f.R     = [headR, rMid, headR];
            f.Y     = [gripTop, yMid, gripBottom];
            f.Angle = ang;
            f.Ok    = true;
        end

        function lp = loadingPlane(joint, gripTop, gripBottom, halfWidth)
            %LOADINGPLANE  n x grip, from the grip top.
            %   The model stores only the factor n, never a location, so the
            %   position is this drawing's convention. n > 1 puts the plane
            %   below the grip, which is a real thing to notice.
            lp = struct('Ok', false, 'Y', NaN, 'Outside', false, ...
                'HalfWidth', halfWidth);
            n = joint.LoadingPlaneFactor;
            h = gripBottom - gripTop;
            if ~isfinite(n) || ~isfinite(h) || h <= 0
                return
            end
            lp.Y       = gripTop + n * h;
            lp.Outside = n > 1 || n < 0;
            lp.Ok      = true;
        end

        function [planes, notes] = shearPlanes(joint, bands, flangeIdx, ...
                flangeBottom, memberOuter, isNut, bolt)
            %SHEARPLANES  Every interface a shear load crosses.
            %   Between consecutive flanges, and - for a threaded-in joint -
            %   between the last flange and the parent it bolts to. A nut
            %   washer is not a shear interface, so a single flange under a
            %   nut has none.
            %
            %   CONSISTENCY, NOT ANALYSIS. Joint.ShearPlane is declared by
            %   the analyst and read by the engine as declared. This only
            %   reports whether the drawn thread start agrees with that
            %   declaration; NASA-STD-5020B Eq. 20-23 use different
            %   exponents for the two conditions, so a disagreement is an
            %   engineering error, not a cosmetic one.
            planes = gui.JointSectionView.emptyShearPlanes();
            notes  = string.empty(1, 0);
            nFl    = numel(flangeIdx);
            if nFl == 0
                return
            end

            ys = zeros(1, 0);
            hw = zeros(1, 0);
            for k = 1:(nFl - 1)
                a = bands(flangeIdx(k));
                b = bands(flangeIdx(k + 1));
                ys(end + 1) = a.Y0 + a.Height;                 %#ok<AGROW>
                hw(end + 1) = min(a.OuterR, b.OuterR);         %#ok<AGROW>
            end
            if ~isNut
                a = bands(flangeIdx(end));
                ys(end + 1) = flangeBottom;
                hw(end + 1) = min(a.OuterR, memberOuter);
            end
            if isempty(ys)
                notes(end + 1) = "No shear plane drawn: one flange layer under a nut.";
                return
            end

            declared = joint.ShearPlane;
            for k = 1:numel(ys)
                cond     = "";
                mismatch = false;
                if bolt.ThreadKnown
                    if ys(k) >= bolt.ThreadTop - 1e-9
                        cond = "thread";
                    else
                        cond = "body";
                    end
                    mismatch = ...
                        (declared == model.ShearPlaneCondition.ThreadsInShear && cond == "body") || ...
                        (declared == model.ShearPlaneCondition.BodyInShear    && cond == "thread");
                end
                planes(end + 1) = struct('Y', ys(k), 'HalfWidth', hw(k), ...
                    'Condition', cond, 'Mismatch', mismatch); %#ok<AGROW>
            end

            if any([planes.Mismatch])
                if declared == model.ShearPlaneCondition.ThreadsInShear
                    notes(end + 1) = "Declared threads-in-shear; unthreaded body at the shear plane.";
                else
                    notes(end + 1) = "Declared body-in-shear; thread runs through the shear plane.";
                end
            end
        end

        function c = callouts(g, joint)
            %CALLOUTS  Text for the right-hand ladder, in stack order.
            %   Every named feature of the drawing, each anchored where
            %   its leader should land. The ladder's row positions are
            %   decided at paint time; the anchors and words are decided
            %   here, where they can be tested.
            c = gui.JointSectionView.emptyCallouts();
            for k = 1:numel(g.Bands)
                b = g.Bands(k);
                if b.OuterR <= b.InnerR || b.Height <= 0
                    continue
                end
                txt = b.Label;
                if b.Label ~= "nut" && b.Label ~= "insert, parent" && ...
                   b.Label ~= "tapped parent"
                    txt = sprintf("%s, t = %.3f", b.Label, b.Height);
                end
                c(end + 1) = gui.JointSectionView.calloutStruct( ...
                    b.Y0 + b.Height / 2, b.OuterR, txt, ...
                    gui.palette('defaultText')); %#ok<AGROW>
            end

            if g.Frustum.Ok
                c(end + 1) = gui.JointSectionView.calloutStruct( ...
                    g.Frustum.Y(2), g.Frustum.R(2), ...
                    sprintf("frustum, %g°", g.Frustum.Angle), ...
                    gui.JointSectionView.FrustumColour); %#ok<AGROW>
            end

            for k = 1:numel(g.ShearPlanes)
                s = g.ShearPlanes(k);
                txt = "shear plane";
                if numel(g.ShearPlanes) > 1
                    txt = sprintf("shear plane %d", k);
                end
                if strlength(s.Condition) > 0
                    txt = txt + ": " + s.Condition;
                end
                col = gui.JointSectionView.ShearPlaneColour;
                if s.Mismatch
                    col = gui.palette('statusWarn');
                end
                c(end + 1) = gui.JointSectionView.calloutStruct( ...
                    s.Y, s.HalfWidth, txt, col); %#ok<AGROW>
            end

            if g.LoadingPlane.Ok
                lp  = g.LoadingPlane;
                col = gui.JointSectionView.LoadingPlaneColour;
                if lp.Outside
                    col = gui.palette('statusFail');
                end
                c(end + 1) = gui.JointSectionView.calloutStruct( ...
                    lp.Y, lp.HalfWidth, ...
                    sprintf("loading plane, n = %.2f", joint.LoadingPlaneFactor), ...
                    col); %#ok<AGROW>
            end

            if g.Engagement.Ok
                % Named for what stops there, and carrying Le so it reads
                % as the same thing as the Le dimension on the left.
                if joint.ThreadedMember.Type == model.ThreadedMemberType.Insert
                    txt = "insert ends, Le";
                else
                    txt = "engagement ends, Le";
                end
                c(end + 1) = gui.JointSectionView.calloutStruct( ...
                    g.Engagement.Y, g.Engagement.R, txt, ...
                    gui.JointSectionView.EngagementColour); %#ok<AGROW>
            end
        end

        function [d, notes] = dims(chk, joint, gripTop, gripBottom, ...
                hostTop, Le, LeIsDefault, bolt)
            %DIMS  The left-hand dimension ladder.
            %   Numbers come from the engine (grip, Lmin) or the model (L);
            %   the only value this file supplies is a flagged drawing
            %   default for Le. Lmin turns red when the bolt is short - the
            %   first of GUI_SPEC.md Section 16's four catches, made visible.
            d     = gui.JointSectionView.emptyDims();
            notes = string.empty(1, 0);
            col   = gui.JointSectionView.DimColour;

            grip = gripBottom - gripTop;
            if ~isempty(chk) && isfinite(chk.GripLength) && chk.GripLength > 0
                grip = chk.GripLength;
            end
            if grip > 0
                d(end + 1) = gui.JointSectionView.dimStruct(gripTop, gripBottom, ...
                    sprintf("grip %.3f", grip), col, '-'); %#ok<AGROW>
            end

            if isfinite(Le) && Le > 0
                txt = sprintf("Le %.3f", Le);
                if LeIsDefault
                    txt = txt + " (default)";
                end
                d(end + 1) = gui.JointSectionView.dimStruct(hostTop, hostTop + Le, ...
                    txt, gui.JointSectionView.EngagementColour, '-'); %#ok<AGROW>
            end

            L = joint.Bolt.Length;
            if isfinite(L) && L > 0
                d(end + 1) = gui.JointSectionView.dimStruct(0, bolt.TotalLength, ...
                    sprintf("L %.3f", L), col, '-'); %#ok<AGROW>
            end

            if ~isempty(chk) && isfinite(chk.RequiredLength) && chk.RequiredLength > 0
                lcol  = col;
                short = chk.Evaluated && ~chk.IsAdequate;
                if short
                    lcol = gui.palette('statusFail');
                    notes(end + 1) = sprintf("Bolt short: L %.3f < Lmin %.3f.", ...
                        chk.SuppliedLength, chk.RequiredLength);
                end
                d(end + 1) = gui.JointSectionView.dimStruct(0, chk.RequiredLength, ...
                    sprintf("Lmin %.3f", chk.RequiredLength), lcol, '--'); %#ok<AGROW>
            end
        end

        function note = conventionNote(bands)
            %CONVENTIONNOTE  Say plainly which lines are not measurements.
            note = "Head height, nut envelope and parent depth: drawing " + ...
                   "conventions, not inputs.";
            if any([bands.WidthAssumed])
                note = note + " Dashed outer edge: no edge distance set.";
            end
        end
    end

    % ---- Test seams -------------------------------------------------------
    methods
        function f = figureHandle(obj)
            f = obj.Fig;
        end

        function a = axesHandle(obj)
            a = obj.Ax;
        end

        function s = noteText(obj)
            s = char(obj.NoteLabel.Text);
        end
    end
end
