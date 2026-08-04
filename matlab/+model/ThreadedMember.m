classdef ThreadedMember
    %THREADEDMEMBER  What the bolt threads into (nut, insert, or tapped hole).
    %   For a Nut and an Insert alike, Material + the thread-shear area drive
    %   an ultimate/yield pair (engine.marginNutStrength /
    %   engine.marginInsert), and RatedUltimateLoad acts as a CEILING on the
    %   ultimate criterion — the lower of computed and rated governs. It does
    %   NOT bound the yield criterion: a rated ULTIMATE capacity says nothing
    %   about the onset of yielding.
    %
    %   A ceiling, not an alternative: NASA-STD-5020B §4.4.1 say a
    %   nut is "limited to the load rating of the nut" and that for inserts
    %   "the lower value should be used". A procured item can expand under
    %   load, reducing the thread engagement area, so a computed allowable is
    %   optimistic. A stale or parent-mismatched rating can then only cost
    %   margin, never grant it.
    %
    %   The area is: for a Nut, ALWAYS the computed 0.75·pi·E·Le form (E =
    %   Bolt.PitchDiameter) — engine.marginNutStrength does not consult
    %   ShearEngagementArea at all, since §4.4.1 gives a nut a rated LOAD and
    %   contemplates no shear engagement area for one; for an Insert,
    %   ShearEngagementArea when supplied (e.g. a Heli-Coil table value),
    %   else the computed 0.75·pi·D2·(Le-1.125·p) form (D2 = StiPitchDiameter,
    %   the STI tapped-hole pitch diameter — see that property's own doc for
    %   why Bolt.PitchDiameter cannot stand in for it here). Material is the
    %   MATING part: the nut for a Nut, and the PARENT material the insert is
    %   installed in for an Insert — an insert's pull-out capacity belongs to
    %   the metal it is threaded into (§4.4.1).
    %
    %   For a TappedHole, Material is the PARENT material
    %   whose Fsu drives the parent-thread-shear check
    %   (engine.marginTappedParentThread); RatedUltimateLoad may stay 0.
    %   EngagementLength is the thread engagement Le (nut thread height /
    %   tapped depth) used by the 0.75·pi·E·Le thread-shear areas (Phase 3.3).
    %
    %   EngagementRatio — thread engagement expressed as a multiple of the
    %   bolt's nominal diameter (L/D), NaN when not used. Helical inserts
    %   (Heli-Coil) are specified by LENGTH CLASS, not an absolute inch
    %   value: Stanley Heli-Coil catalog p.12 ("Q" Nominal Length table)
    %   and NASM33537 Rev 4 §6.1 both give nominal length as 1, 1.5, 2, 2.5,
    %   or 3 x the nominal major diameter of the screw thread — a ratio IS
    %   the form actually specified for a procured insert, not a derived
    %   convenience. It is also the only form that survives
    %   engine.boltSizingSweep, which applies ONE ThreadedMember template
    %   across many candidate bolt sizes of different NominalDiameter — a
    %   fixed EngagementLength inch value would be correct for at most one
    %   row of that sweep, while a ratio resolves correctly for all of
    %   them. When set (not NaN), EngagementRatio governs: every consumer
    %   resolves the engagement length Le via the single resolver helper
    %   resolveEngagementLength (matlab/+engine/private/), which computes
    %   Le = EngagementRatio x Bolt.NominalDiameter and OVERRIDES
    %   EngagementLength when both are set — never read EngagementLength
    %   directly where Le is needed; call the resolver instead.
    %
    %   tm = model.ThreadedMember(Type=model.ThreadedMemberType.Nut, ...
    %                             Material=nutMat, RatedUltimateLoad=4080, ...
    %                             EngagementLength=0.3);

    properties
        Type              (1,1) model.ThreadedMemberType = model.ThreadedMemberType.Nut
        Material          (1,1) model.Material = model.Material()   % nut/insert/parent material
        RatedUltimateLoad (1,1) double {mustBeNonnegative} = 0      % spec-rated Pult (nut) / rated pull-out (insert), lbf
        % ShearEngagementArea — insert minimum shear engagement area, in^2,
        % tabulated by the insert manufacturer per (fastener size, thread
        % engagement L/D). The Heli-Coil table presents it as the GRADIENT of
        % allowable pull-out versus parent-material shear strength; that slope
        % IS this area: allowable pull-out = ShearEngagementArea x parent
        % shear stress (NASA-STD-5020B §4.4.1). When set, engine.marginInsert
        % computes the parent-specific ultimate/yield pull-out pair from it
        % (governing over RatedUltimateLoad); NaN -> the computed
        % 0.75·pi·D2·(Le-1.125·p) catalogue-geometry path. NOT read on the
        % Nut path at all (engine.marginNutStrength): §4.4.1 gives a nut a
        % rated LOAD and contemplates no shear engagement area for one, so a
        % Nut's area is always the computed 0.75·pi·E·Le form regardless of
        % this field.
        %
        % NOT analyst-supplied: neither the GUI (Joint Config, Bolt Sizing)
        % nor the bulk workbook loader expose a way to type this field --
        % NASA-STD-5020B §4.4.1 wants a nut's rated LOAD or an insert's
        % SPECIFIED catalogue geometry, not an analyst-typed area (a
        % non-catalogue insert's escape hatch is a custom
        % data.Library.addInsert entry, which carries provenance a typed
        % field would not). It remains an API/test seam only: set directly
        % by engine.marginInsert's own callers in tests, and left at the
        % model default (NaN) by every GUI/bulk-load path, which instead
        % relies on that function's own catalogue-geometry resolution
        % (StiPitchDiameter).
        ShearEngagementArea (1,1) double {mustBePositiveOrNaN} = NaN
        % StiPitchDiameter — the STI (Screw Thread Insert) tapped-hole
        % pitch diameter, in, from the insert catalogue (NASM33537 Rev 4
        % Table IV; equivalently Stanley HELI-COIL catalogue HC2000 Rev 12
        % Table VII p.20). This is the diameter at which the PARENT's
        % internal thread shears — LARGER than the bolt's own pitch
        % diameter (joint.Bolt.PitchDiameter), which is why the bolt's
        % PitchDiameter cannot be substituted for it the way it stands in
        % for E in the nut/tapped-hole 0.75·pi·E·Le forms. When set (and
        % Type is Insert), engine.marginInsert computes a DERIVED
        % shear-engagement area from it (As = 0.75·pi·D2·(Le-1.125·p), see
        % that function's header) whenever ShearEngagementArea itself is
        % NaN — a labelled fallback beneath a directly-supplied
        % ShearEngagementArea (API/test seam only, see that property's own
        % doc), itself above the flat RatedUltimateLoad basis. NaN when the
        % thread size has no catalogued insert (e.g. #0-80, #5-44 — no
        % helical insert is offered for them in NASM33537 or the Stanley
        % catalogue) or when no insert spec has been resolved for this
        % joint. Populated at build time from
        % data.Library.insertFor(nominalDiameter, tpi) by the GUI and the
        % bulk loader — the engine itself never reads the library.
        StiPitchDiameter    (1,1) double {mustBePositiveOrNaN} = NaN
        EngagementLength  (1,1) double {mustBePositiveOrNaN} = NaN  % thread engagement Le, in (nut height / tapped depth)
        % EngagementRatio — thread engagement as a multiple of the bolt's
        % nominal diameter (L/D), NaN when not used. See the class header
        % for why a ratio (Stanley Heli-Coil catalog p.12; NASM33537 Rev 4
        % §6.1) is the specified form for a procured insert. When set, it
        % OVERRIDES EngagementLength wherever Le is resolved (via the
        % private resolveEngagementLength helper) — never consulted
        % directly by name; always go through that resolver.
        EngagementRatio   (1,1) double {mustBePositiveOrNaN} = NaN
        BearingDiameter   (1,1) double {mustBePositiveOrNaN} = NaN  % nut/head bearing dia for under-nut bearing, in
        HostName          (1,1) string = ""                         % parent/host body name (cosmetic)
    end

    methods
        function obj = ThreadedMember(args)
            arguments
                args.?model.ThreadedMember
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end
    end
end
