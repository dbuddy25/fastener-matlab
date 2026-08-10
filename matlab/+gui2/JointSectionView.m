classdef JointSectionView < handle
    %JOINTSECTIONVIEW  To-scale axial cross-section of the joint (GUI_PORT_SPEC.md Section 13).
    %
    %   A NON-MODAL window, opened from Joint Config and kept alive beside
    %   the app. It listens to JointChanged and repaints as the form is
    %   edited, which is the whole point: the mistakes it catches are ones
    %   nobody thinks to go looking for, so a picture you have to remember
    %   to open is a picture that never gets opened.
    %
    %   WHY A WINDOW AND NOT THE RIGHT-HAND COLUMN. Section 13 says to host
    %   this in a column of Joint Config "rather than a separate window".
    %   Two things make that the wrong call here: that column already ends
    %   in the Analyze button on a scrollable page, so a fifth group renders
    %   below the fold exactly when it is wanted; and it is the 1x of a 2x/1x
    %   split, which cannot show a to-scale section with per-flange labels.
    %   DataAspectRatio forbids cheating the width. Repainting on
    %   JointChanged recovers what inline hosting was for.
    %
    %   IT DRAWS IN DATA COORDINATES, never pixels. Section 13 is explicit
    %   that this is the point - the pixel-scaling layer it replaces was
    %   ~170 lines in the original tool. x is RADIAL (0 on the centerline,
    %   symmetric), y is AXIAL in inches measured DOWN from the under-head
    %   bearing plane, with the axis YDir reversed so the head sits at the
    %   top and the stack reads head-to-tail like Joint Config's left column.
    %
    %   THREE DIMENSIONS IN THIS DRAWING ARE NOT DATA. The model carries no
    %   bolt head height, no head across-flats and no nut hex geometry, and
    %   neither does the library - see HeadHeightFactor below. They are
    %   drawing conventions, they are listed in the window's own note line,
    %   and nothing computed from them is ever shown as a number. A flange
    %   drawn to an assumed half-width gets a DASHED outer edge so an
    %   invented dimension can never be read as a measured one.
    %
    %   IT COMPUTES NO ENGINEERING VALUES. Grip and thread engagement come
    %   from engine.boltLengthCheck, not from arithmetic here, for the same
    %   reason ResultsPage refuses to call engine.preload: a second
    %   implementation is a second answer. layout() is a pure function of a
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
        % opening size - the first thing anyone said about this view.
        AxisFontSize  = 11
        LabelFontSize = 11
        AnnotFontSize = 10

        % Thread teeth are skipped outside this range: below it there is
        % nothing to see, above it the teeth merge into a grey band and the
        % dotted root outline reads better.
        MinThreadTeeth = 2
        MaxThreadTeeth = 120

        % Fill colours. Deliberately muted and few: this is a diagram, not
        % a rendering, and Section 13 says skip the gradients.
        BoltFill   = [0.62 0.66 0.72]
        WasherFill = [0.78 0.80 0.84]
        FlangeFill = [0.86 0.88 0.91]
        MemberFill = [0.72 0.76 0.70]
        EdgeColour = [0.25 0.27 0.30]
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
                state (1,1) gui2.AppState
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
        function build(obj)
            obj.Fig = uifigure('Name', 'Joint Cross-Section', ...
                'Position', [200 160 560 680]);

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
            % Head at the top. y counts DOWN the stack from the under-head
            % bearing plane, which is how the joint is described everywhere
            % else in this app.
            obj.Ax.YDir     = 'reverse';
            obj.Ax.Box      = 'on';
            obj.Ax.FontSize = gui2.JointSectionView.AxisFontSize;
            xlabel(obj.Ax, 'radius (in)');
            ylabel(obj.Ax, 'axial position from under-head (in)');

            obj.NoteLabel = uilabel(g, 'WordWrap', 'on', 'Text', '', ...
                'FontSize', gui2.JointSectionView.LabelFontSize);
            obj.NoteLabel.Layout.Row    = 2;
            obj.NoteLabel.Layout.Column = 1;
            obj.NoteLabel.FontColor     = gui2.palette('mutedText');

            % Repaints as the form is edited - the passive catching that
            % inline hosting was for.
            obj.Listener = event.listener(obj.State, 'JointChanged', ...
                @(~, ~) obj.redraw());

            obj.Fig.CloseRequestFcn = @(~, ~) obj.onClose();
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
                g = gui2.JointSectionView.layout(obj.State.Joint);
                obj.paint(g);
            catch err
                cla(obj.Ax);
                obj.NoteLabel.Text = sprintf( ...
                    'The section could not be drawn (%s). The joint itself is unaffected.', ...
                    err.message);
            end
        end
    end

    % ---- Painting ---------------------------------------------------------
    methods (Access = private)
        function paint(obj, g)
            cla(obj.Ax);
            hold(obj.Ax, 'on');

            if ~g.Ok
                obj.NoteLabel.Text = char(strjoin(g.Notes, '  '));
                hold(obj.Ax, 'off');
                return
            end

            obj.paintClampedStack(g);
            obj.paintBolt(g);
            obj.paintFrustum(g);
            obj.paintLoadingPlane(g);

            % Centreline last so it sits over the fills.
            plot(obj.Ax, [0 0], [g.YTop g.YBottom], '-.', ...
                'Color', [0.45 0.45 0.50], 'LineWidth', 0.5);

            obj.Ax.XLim = g.XLim;
            obj.Ax.YLim = g.YLim;
            obj.NoteLabel.Text = char(strjoin(g.Notes, '  '));
            hold(obj.Ax, 'off');
        end

        function paintClampedStack(obj, g)
            %PAINTCLAMPEDSTACK  Washers, flanges and the threaded host.
            %   Everything here is an ANNULUS in section: two rectangles,
            %   left and right of a real clearance hole. Drawing one solid
            %   block and putting the bolt on top of it would hide exactly
            %   the thing this view exists to show - whether the hole and
            %   the bolt in it are plausible.
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
                if strlength(b.Label) > 0
                    text(obj.Ax, b.OuterR + 0.04 * g.Scale, ...
                        b.Y0 + b.Height / 2, char(b.Label), ...
                        'FontSize', gui2.JointSectionView.AnnotFontSize, ...
                        'VerticalAlignment', 'middle', ...
                        'Color', gui2.palette('mutedText'));
                end
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
            %   path per side.
            if ~g.Frustum.Ok
                return
            end
            f   = g.Frustum;
            col = [0.55 0.40 0.65];
            plot(obj.Ax, f.R, f.Y, '--', 'Color', col, 'LineWidth', 1);
            plot(obj.Ax, -f.R, f.Y, '--', 'Color', col, 'LineWidth', 1);

            % Named, and carrying its angle. Two dashed lines on a diagram
            % of a bolt are not self-evidently a compression cone - the
            % first person to see this asked what they were.
            text(obj.Ax, f.R(2), f.Y(2), sprintf('  compression cone %g deg', ...
                f.Angle), 'FontSize', gui2.JointSectionView.AnnotFontSize, ...
                'Color', col, 'VerticalAlignment', 'middle');
        end

        function paintLoadingPlane(obj, g)
            %PAINTLOADINGPLANE  n x grip, measured from the grip top.
            %   Turns RED when it lands outside the grip, which is one of
            %   the four things this view exists to catch.
            if ~g.LoadingPlane.Ok
                return
            end
            lp = g.LoadingPlane;
            if lp.Outside
                col = gui2.palette('statusFail');
            else
                col = [0.15 0.35 0.65];
            end
            plot(obj.Ax, [-lp.HalfWidth lp.HalfWidth], [lp.Y lp.Y], '-', ...
                'Color', col, 'LineWidth', 1.25);
            text(obj.Ax, -lp.HalfWidth, lp.Y, ' loading plane', ...
                'FontSize', gui2.JointSectionView.AnnotFontSize, ...
                'Color', col, 'VerticalAlignment', 'bottom');
        end
    end

    % ---- Geometry ---------------------------------------------------------
    methods (Static)
        function g = layout(joint)
            %LAYOUT  A model.Joint -> every coordinate the drawing needs.
            %   PURE, and public, so the geometry can be tested without a
            %   figure. Returns g.Ok false plus g.Notes when there is not
            %   enough to draw; never throws.
            %
            %   Grip and engagement come from engine.boltLengthCheck rather
            %   than being recomputed here - one implementation, one answer.
            % Built field by field, NOT in one struct(...) call: a struct
            % array passed as a value there does not mean what it looks
            % like it means, and Bands is a struct array.
            g              = struct();
            g.Ok           = false;
            g.Notes        = string.empty(1, 0);
            g.Bands        = struct('Y0', {}, 'Height', {}, 'InnerR', {}, ...
                                    'OuterR', {}, 'Fill', {}, 'Label', {}, ...
                                    'WidthAssumed', {});
            g.Scale        = 1;
            g.XLim         = [-1 1];
            g.YLim         = [-1 1];
            g.YTop         = 0;
            g.YBottom      = 0;
            g.Bolt         = struct();
            g.Frustum      = struct('Ok', false, 'R', [], 'Y', [], 'Angle', NaN);
            g.LoadingPlane = struct('Ok', false, 'Y', NaN, ...
                                    'Outside', false, 'HalfWidth', 0);

            if isempty(joint) || ~isa(joint, 'model.Joint')
                g.Notes(end + 1) = "No joint to draw.";
                return
            end

            D = joint.Bolt.NominalDiameter;
            if ~isfinite(D) || D <= 0
                g.Notes(end + 1) = ...
                    "Choose a bolt on Joint Config - the section is drawn to " + ...
                    "its nominal diameter.";
                return
            end
            g.Scale = D;

            if isempty(joint.FlangeStack)
                g.Notes(end + 1) = ...
                    "Add at least one flange layer to see the clamped stack.";
            end

            % ---- the clamped stack, head to tail ----
            bands  = struct('Y0', {}, 'Height', {}, 'InnerR', {}, ...
                            'OuterR', {}, 'Fill', {}, 'Label', {}, ...
                            'WidthAssumed', {});
            y = 0;

            hw = joint.HeadWasher;
            if gui2.JointSectionView.washerPresent(hw)
                [b, y] = gui2.JointSectionView.washerBand(hw, D, y, 'head washer');
                bands(end + 1) = b;
            end

            gripTop = y;
            for k = 1:numel(joint.FlangeStack)
                f  = joint.FlangeStack(k);
                hr = gui2.JointSectionView.holeRadius(f, D);

                halfW   = f.EdgeDistance;
                assumed = ~isfinite(halfW) || halfW <= hr;
                if assumed
                    halfW = gui2.JointSectionView.AssumedFlangeHalfWidth * D;
                end

                label = f.Name;
                if strlength(label) == 0
                    label = sprintf('flange %d', k);
                end

                bands(end + 1) = struct('Y0', y, 'Height', f.Thickness, ...
                    'InnerR', hr, 'OuterR', halfW, ...
                    'Fill', gui2.JointSectionView.FlangeFill, ...
                    'Label', string(label), 'WidthAssumed', assumed); %#ok<AGROW>
                y = y + f.Thickness;
            end
            gripBottom = y;

            isNut = joint.ThreadedMember.Type == model.ThreadedMemberType.Nut;

            % A threaded-in joint has no nut washer by convention - the
            % engine only reads HeadWasher on that branch.
            nw = joint.NutWasher;
            if isNut && gui2.JointSectionView.washerPresent(nw)
                [b, y] = gui2.JointSectionView.washerBand(nw, D, y, 'nut washer');
                bands(end + 1) = b;
                gripBottom = y;
            end

            [Le, engagementNote] = gui2.JointSectionView.engagement(joint, D, isNut);
            if strlength(engagementNote) > 0
                g.Notes(end + 1) = engagementNote;
            end

            memberOuter = joint.ThreadedMember.BearingDiameter / 2;
            if ~isfinite(memberOuter) || memberOuter <= 0
                memberOuter = gui2.JointSectionView.MemberWidthFactor * D;
            end
            if isNut
                memberLabel = "nut";
            elseif joint.ThreadedMember.Type == model.ThreadedMemberType.Insert
                memberLabel = "insert + parent";
            else
                memberLabel = "tapped parent";
            end
            bands(end + 1) = struct('Y0', y, 'Height', Le, ...
                'InnerR', gui2.JointSectionView.threadRadius(joint, D), ...
                'OuterR', memberOuter, ...
                'Fill', gui2.JointSectionView.MemberFill, ...
                'Label', memberLabel, 'WidthAssumed', false);
            memberBottom = y + Le;

            g.Bands = bands;

            % ---- the bolt ----
            g.Bolt = gui2.JointSectionView.boltGeometry(joint, D, memberBottom);

            % ---- frustum, loading plane ----
            g.Frustum = gui2.JointSectionView.frustumProfile( ...
                joint, gripTop, gripBottom, g.Bolt.HeadR);
            g.LoadingPlane = gui2.JointSectionView.loadingPlane( ...
                joint, gripTop, gripBottom, memberOuter);

            % ---- extents ----
            outerR = max([bands.OuterR, g.Bolt.HeadR, memberOuter]);
            g.YTop    = g.Bolt.HeadTop;
            % TotalLength, not ShankLength: the latter is now the unthreaded
            % run, and clipping the axis to it would cut off the threads.
            g.YBottom = max(memberBottom, g.Bolt.TotalLength);
            pad = 0.25 * D;
            g.XLim = [-(outerR + pad), outerR + pad];
            g.YLim = [g.YTop - pad, g.YBottom + pad];

            g.Notes = [g.Notes, gui2.JointSectionView.conventionNote(bands)];
            g.Ok = true;
        end
    end

    % ---- Geometry helpers -------------------------------------------------
    methods (Static, Access = private)
        function tf = washerPresent(w)
            %WASHERPRESENT  model.Washer has no Present flag.
            %   A washer is absent iff it is untouched at its model default:
            %   zero thickness and both diameters unset. Matches the
            %   predicate the first build settled on.
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
            b = struct('Y0', y, 'Height', t, 'InnerR', innerR, ...
                'OuterR', outerR, ...
                'Fill', gui2.JointSectionView.WasherFill, ...
                'Label', string(label), 'WidthAssumed', false);
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

        function [Le, note] = engagement(joint, D, isNut)
            %ENGAGEMENT  Thread engagement, from the engine where possible.
            %   engine.boltLengthCheck owns the ratio-over-length precedence
            %   and the 1.5D fallback. Replicating it here would be a second
            %   implementation of an engineering quantity.
            note = "";
            Le   = NaN;
            try
                chk = engine.boltLengthCheck(joint);
                Le  = chk.Engagement;
            catch
                % Half-filled joint. Fall through to the drawing default.
            end
            if ~isfinite(Le) || Le <= 0
                Le = gui2.JointSectionView.NutHeightFactor * D;
                if isNut
                    note = "Nut height is a drawing default - no engagement set.";
                else
                    note = "Engagement depth is a drawing default - none set.";
                end
            end
        end

        function b = boltGeometry(joint, D, memberBottom)
            %BOLTGEOMETRY  Head, shank and thread, in axial coordinates.
            %   y = 0 is the under-head bearing plane, so the head is at
            %   NEGATIVE y and the shank runs positive down the stack.
            headR = joint.Bolt.HeadBearingDiameter / 2;
            conv  = gui2.JointSectionView.HeadDiameterFactor * D / 2;
            if ~isfinite(headR) || headR <= 0
                headR = conv;
            else
                % The bearing face is the load-carrying annulus, not the
                % outside of the head; drawing the head at exactly the
                % bearing diameter makes every head look undersized.
                headR = max(headR, conv);
            end

            headH = gui2.JointSectionView.HeadHeightFactor * D;

            shankR = joint.Bolt.BodyDiameter / 2;
            if ~isfinite(shankR) || shankR <= 0
                shankR = D / 2;
            end
            threadR = gui2.JointSectionView.threadRadius(joint, D);

            % Bolt.Length is under-head to tip. With no length set, draw the
            % shank to the bottom of what it threads into so the picture
            % still closes - and say so in the note.
            L = joint.Bolt.Length;
            if ~isfinite(L) || L <= 0
                L = memberBottom;
            end

            % ThreadLength is measured FROM THE TIP.
            tl = joint.Bolt.ThreadLength;
            if ~isfinite(tl) || tl <= 0
                tl = 0;
            end
            tl = min(tl, L);

            b = struct( ...
                'HeadR', headR, 'HeadHeight', headH, 'HeadTop', -headH, ...
                'ShankR', shankR, ...
                'TotalLength', L, ...
                'ShankLength', L - tl, ...
                'ThreadR', threadR, 'ThreadLength', tl, 'ThreadTop', L - tl, ...
                'MajorR', D / 2, ...
                'Thread', gui2.JointSectionView.threadProfile( ...
                              joint, D, L - tl, tl, threadR));
        end

        function t = threadProfile(joint, D, yTop, len, minorR)
            %THREADPROFILE  Real thread teeth, when the thread data supports them.
            %   NOT a convention: pitch is model.Bolt.Pitch (a Dependent
            %   property, = 1/ThreadsPerInch) and the crest and root radii
            %   are NominalDiameter and MinorDiameter. Every tooth is at its
            %   true axial position, so a 28-TPI thread draws 28 teeth to
            %   the inch and the picture stays to scale.
            %
            %   Section 13 says to skip coil hatching, and this is not that:
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
            if n < gui2.JointSectionView.MinThreadTeeth || ...
               n > gui2.JointSectionView.MaxThreadTeeth
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
            %   The model stores only the FACTOR n, never a location, so the
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

        function note = conventionNote(bands)
            %CONVENTIONNOTE  Say plainly which lines are not measurements.
            note = "Head height and hex geometry are drawing conventions - " + ...
                   "the model carries neither.";
            if any([bands.WidthAssumed])
                note = note + " Dashed outer edges are assumed widths " + ...
                       "(no edge distance set).";
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
