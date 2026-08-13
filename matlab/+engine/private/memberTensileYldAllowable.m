function a = memberTensileYldAllowable(joint)
%MEMBERTENSILEYLDALLOWABLE  The internally threaded member's YIELD allowable.
%   a = memberTensileYldAllowable(joint) resolves the yield-tensile allowable
%   of whatever the bolt threads into — nut, insert or tapped parent — as the
%   thread-shear area times that member's shear YIELD strength:
%
%       AllowYld = As * Fsy          (this tool's own criterion, see below)
%
%   Private to +engine. Loads in lbf, areas in in^2, strengths in psi.
%
%   WHY IT EXISTS. The area resolution, its source precedence and the mode
%   naming already live in memberTensileUltAllowable, which scopes ITSELF to
%   ultimate ("YIELD allowables stay in the margin functions: Ptu-allow is an
%   ultimate quantity"). So each margin function grew its own inline
%   `As * sy.Fsy`, and there was nowhere for a SYSTEM yield allowable to get
%   the same number from. This calls that helper for the area and adds only
%   the strength, so the row and the system minimum cannot disagree about
%   which area source governed — the same extraction, for the same reason, as
%   engine.applyTemperatures and engine.jointPatternTotals.
%
%   WHICH HALF HAS AN EQUATION NUMBER, AND WHICH DOES NOT. This header used
%   to say flatly "NO EQUATION NUMBER IS CLAIMED", which was half wrong and
%   was corrected by the 2026-08-13 equation audit:
%
%     - The AREA form genuinely has none. NASA-STD-5020B §4.4.2 requires
%       yield design loads but prints no thread-shear yield equation, and
%       5020B prints no thread-shear-AREA equation anywhere (verified
%       against the full Eq. 1-87 inventory; Eq. 12/13 are the fastener
%       cross-section shear allowable, a different failure mode). The area
%       here is the ULTIMATE one (memberTensileUltAllowable, TM-106943
%       Eq. 76/79) evaluated against shear yield instead of shear ultimate.
%       That substitution is this tool's own criterion — no number claimed.
%
%     - The Fsy DOES have one: NASA-STD-5020B Eq. 63 (p66, Appendix A.8),
%       Fsy = Fty/sqrt(3), which the standard derives from Eq. 61 + Eq. 62.
%       engine.shearYieldStrength cites it; do not restate it as
%       unnumbered.
%
%   The authority to derive Fsy at all is §4.4.2, p31 (NOT p30 — the page
%   this header used to give): "Because shear yield strength is not a
%   standard material property, when evaluating the margin of safety under
%   yield design loads and performing combined loads analysis, the normal
%   and shear components of stress should be transformed into principal
%   stresses; and a failure theory (e.g., von Mises or Tresca) should be
%   used that is compatible with the concept of tensile yield strength."
%   engine.shearYieldStrength's Basis string must stay visible in whatever
%   Detail the caller writes, so a derived Fsy never passes as test data.
%
%   THREE RULES, each mirroring a convention the rows already follow:
%
%   (1) NEVER RATING-CAPPED. A spec rating is an ULTIMATE allowable and says
%       nothing about the onset of permanent deformation, so it caps the
%       ultimate criterion and not this one (the same deliberate choice
%       marginNutStrength and marginInsert already document).
%
%   (2) A RATED-ONLY MEMBER HAS NO YIELD MODE. When the member is assessable
%       only through its rating — no area could be formed — Assessed is FALSE
%       with the reason "a rating carries no yield information". This is not a
%       gap being tolerated: it is the established doctrine
%       (marginNutStrength's flat-rating basis is ULTIMATE-ONLY for exactly
%       this reason), and it is what keeps the DABJ §9 answer key intact — that
%       fixture's nut is rated with no engagement length, so its yield mode is
%       unassessable and a system yield minimum degenerates to the bolt's.
%
%   (3) A TAPPED HOLE DOES GET A YIELD MODE HERE. marginTappedParentThread's
%       row stays ultimate-only — that deferral is about the ROW and DABJ Ex
%       6-a's pin — but §4.4.2 p29 is explicit that the yield assessment
%       "will address all elements of the threaded fastening system, including
%       the fastener, the internally threaded part such as a nut or an insert,
%       and the clamped parts". "Such as" is illustrative; in a tapped
%       configuration the parent IS the internally threaded part, and there is
%       no reading in which it is an element at ultimate and not at yield. The
%       obstacle that caused the deferral — shear yield not being a standard
%       property — is the one p31 answers. So the system minimum assesses it,
%       with the same area form and the same von Mises fallback the insert
%       already uses.
%
%   Returned struct fields:
%       Mode      display name of the member mode ("" when not applicable)
%       Assessed  logical: AllowYld is usable
%       AllowYld  As * Fsy, lbf (NaN when not assessed)
%       As        thread-shear area used, in^2 (NaN when none)
%       AreaSrc   how the area was obtained (from the ultimate helper)
%       FsyBasis  engine.shearYieldStrength's Basis string — ALWAYS surfaced
%                 by the caller, so a derived Fsy never passes as test data
%       Reason    why it could not be assessed ("" when Assessed)
%
%   Call graph:
%       Precedents (calls)      memberTensileUltAllowable (area/mode/source),
%                               engine.shearYieldStrength (Fsy + Basis).
%       Dependents (called by)  engine.marginInsert, engine.marginNutStrength
%                               (their own yield criteria), and
%                               engine.systemTensileYieldAllowable.
%       Tests                   tests/tThreadShear.m (the existing yield pins
%                               prove this extraction bit-identical),
%                               tests/tSystemAllowable.m.
%
%   Validation status/coverage: no new VALIDATION.md row — this moves an
%   existing computation, it does not introduce one.

arguments
    joint (1,1) model.Joint
end

a = struct("Mode", "", "Assessed", false, "AllowYld", NaN, ...
    "As", NaN, "AreaSrc", "", "FsyBasis", "", "Reason", "");

% The area, its source and the mode name all come from the ultimate helper,
% so there is exactly one implementation of the precedence rules.
ua     = memberTensileUltAllowable(joint);
a.Mode = ua.Mode;

if strlength(ua.Mode) == 0
    a.Reason = ua.Reason;   % unknown member type — already worded there
    return
end

% Rule (2): rated-only. The mode is assessable at ULTIMATE through its
% rating, and not at yield at all.
if isnan(ua.As)
    if ua.Assessed
        a.Reason = "a rating carries no yield information (" + ua.Mode + ...
            " is assessable only through its specified ultimate load)";
    else
        a.Reason = ua.Reason;   % no area AND no rating — reuse the wording
    end
    return
end

a.As      = ua.As;
a.AreaSrc = ua.AreaSrc;

% ThreadedMember.Material IS the material carrying the internal thread for
% every type — the nut itself for a Nut, the parent body for an Insert or a
% TappedHole. One property, which is why no switch is needed here (Joint
% Config relabels the control per type for the same reason).
mat        = joint.ThreadedMember.Material;
sy         = engine.shearYieldStrength(mat);
a.FsyBasis = sy.Basis;

if isnan(sy.Fsy)
    a.Reason = "a thread-shear area is available (" + a.AreaSrc + ") but " + ...
        mat.Name + " lacks Fsy (and Fty to estimate it)";
    return
end

% §4.4.2 yield counterpart of the ultimate area form — no 5020B equation
% number exists for it (see the header).
a.AllowYld = a.As * sy.Fsy;
a.Assessed = true;
end
