function r = resolveEngagementLength(joint)
%RESOLVEENGAGEMENTLENGTH  Thread engagement length Le — ratio-or-absolute, one resolution.
%   r = resolveEngagementLength(joint) resolves the thread engagement
%   length Le used by the 0.75·pi·E·Le thread-shear area forms
%   (memberTensileUltAllowable, engine.marginBoltThreadShear) and by the
%   NASA-STD-5020B §4.7.4 bolt-length relations (engine.boltLengthCheck's
%   RequiredLength, engine.stiffness's Level-3 L1 fallback). It is the
%   SINGLE place Le is resolved from the two ways a caller may specify it
%   — every consumer calls this instead of reading
%   joint.ThreadedMember.EngagementLength directly, so none of them can
%   disagree about which number was used.
%
%   WHY A RATIO AT ALL: helical inserts (Heli-Coil) and other threaded
%   inserts are specified by LENGTH CLASS, not an absolute inch value —
%   Stanley Heli-Coil catalog p.12 ("Q" Nominal Length table) and
%   NASM33537 Rev 4 §6.1 both give nominal length as 1, 1.5, 2, 2.5, or 3 x
%   the nominal major diameter of the screw thread (the tabulated Q values
%   are exactly those multiples). A ratio is also the only form that
%   stays correct across engine.boltSizingSweep, which applies ONE
%   ThreadedMember template across candidate bolts of different
%   NominalDiameter — a fixed inch Le would be right for at most one row.
%
%   PRECEDENCE (ratio wins when set, regardless of whether the length is
%   also set — no silent blending of the two):
%       ThreadedMember.EngagementRatio set (not NaN):
%           Le = EngagementRatio * joint.Bolt.NominalDiameter
%       else:
%           Le = ThreadedMember.EngagementLength (unchanged, in)
%       Both unset -> Le = NaN (callers already treat a NaN Le as
%       "not evaluated").
%
%   BOTH SET: the ratio governs, and Note SAYS SO explicitly (names the
%   overridden EngagementLength value) — a reviewer must never be left
%   guessing which number a check actually used. This is why Basis is keyed
%   off which PROPERTY is set, not off whether the arithmetic happens to
%   succeed: if EngagementRatio is set but Bolt.NominalDiameter is NaN, Le
%   comes out NaN and Basis still reports "ratio" (the ratio governs; the
%   diameter is what is missing) rather than silently falling back to
%   EngagementLength, which would misreport which quantity the analyst
%   actually specified.
%
%   Returned struct fields:
%       Le     resolved engagement length, in (NaN if neither is set, or if
%              EngagementRatio is set but Bolt.NominalDiameter is NaN)
%       Basis  "ratio" | "length" | "none" — which property governed
%       Note   string: the resolution actually used, for the caller to fold
%              into its own Method/Detail (e.g. "Le = EngagementRatio*D =
%              1.5*0.1900 = 0.2850 in (EngagementRatio overrides
%              EngagementLength 0.3000 in)"); "" when Basis is "none"
%
%   Call graph:
%       Precedents (calls)      (leaf) — model.Joint / model.ThreadedMember /
%                               model.Bolt getters only.
%       Dependents (called by)  memberTensileUltAllowable (private),
%                               engine.marginBoltThreadShear,
%                               engine.boltLengthCheck, engine.stiffness.
%       Tests                   tests/tBoltLength.m — ratio-only,
%                               length-only, both-set (ratio wins),
%                               neither-set (NaN); tests/tBoltSizing.m —
%                               two candidate sizes, one ratio, two Le.

arguments
    joint (1,1) model.Joint
end

tm    = joint.ThreadedMember;
ratio = tm.EngagementRatio;
len   = tm.EngagementLength;
D     = joint.Bolt.NominalDiameter;

if ~isnan(ratio)
    % Ratio governs whenever it is set — Stanley Heli-Coil catalog p.12 /
    % NASM33537 Rev 4 §6.1 form (see header).
    Le = ratio * D;   % NaN-propagating if D is unset — see header
    if ~isnan(len)
        note = string(sprintf( ...
            "Le = EngagementRatio*D = %.4g*%.4f = %.4f in (EngagementRatio overrides EngagementLength %.4f in)", ...
            ratio, D, Le, len));
    else
        note = string(sprintf( ...
            "Le = EngagementRatio*D = %.4g*%.4f = %.4f in", ratio, D, Le));
    end
    basis = "ratio";
elseif ~isnan(len)
    Le    = len;
    note  = string(sprintf("Le = EngagementLength = %.4f in", Le));
    basis = "length";
else
    Le    = NaN;
    note  = "";
    basis = "none";
end

r = struct("Le", Le, "Basis", basis, "Note", note);
end
