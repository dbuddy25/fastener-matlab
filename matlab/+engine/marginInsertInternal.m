function r = marginInsertInternal(joint, loadCase, factors, preload)
%MARGININSERTINTERNAL  Insert INTERNAL-thread allowable (the specified value).
%   r = engine.marginInsertInternal(joint, loadCase, factors, preload)
%   checks the first of NASA-STD-5020B §4.4.1's two insert allowables: the
%   tensile capability of the INSERT'S OWN internal threads, where the bolt
%   engages it. Only evaluated when
%   joint.ThreadedMember.Type == Insert; otherwise MS = NaN.
%
%   THE STANDARD NAMES TWO, AND THEY ARE DIFFERENT FAILURES (§4.4.1, p27):
%     "Many threaded inserts have two allowable tensile loads that should
%      be considered: the minimum allowed tensile load capability of the
%      insert internal threads, and the minimum allowed tensile load for
%      pullout of the insert from the parent material. One or both may be
%      provided in the insert specification (or the procurement
%      specification). The lower value should be used for strength
%      analysis."
%   This function is the FIRST. engine.marginInsert is the second
%   (pull-out). Each carries its own row, and the lower governs through
%   engine.analyze's WorstMargin — which is exactly "the lower value should
%   be used" without either mode being hidden inside the other.
%
%   IT IS A SPECIFIED VALUE, NEVER A COMPUTED ONE. §4.4.1 p26:
%     "Assessment of a procured item such as a nut or a threaded insert
%      should be based on the strength specified for that item rather than
%      on thread-stripping analysis. Such items can expand under load,
%      reducing the thread engagement areas."
%   So this row reads ThreadedMember.RatedUltimateLoad — the manufacturer's
%   or procurement specification's value — and computes NO thread-shear
%   area for the insert's own threads. With no rating supplied there is
%   nothing to check and the row is NotEvaluated, which is the honest
%   outcome: the standard says the value should come from the spec, and the
%   tool will not invent one.
%
%   ULTIMATE ONLY, deliberately. A specification rating is an ultimate
%   quantity; §4.4.2 requires yield design loads but supplies no yield
%   counterpart for a procured item's rating, and dividing the rating by a
%   yield factor pair would be this tool inventing an allowable the
%   manufacturer never published. Same treatment as the tapped-hole row.
%
%       MS = RatedUltimateLoad / Pb − 1
%
%   Pb is engine.boltDesignLoad's clamped form — NASA-STD-5020B Eq. 8,
%   Pb = PpMax + FFU·FSU·n·phi·PtL — or, when the Fig. 8 gate assures
%   separation before rupture, the Eq. 6 principle FFU·FSU·PtL with no
%   preload term. boltDesignLoad picks the branch and says which in Note,
%   shared with every other threaded-member row so they cannot disagree.
%
%   Returned struct fields (same shape as engine.marginInsert, so both
%   insert rows are interchangeable to a caller):
%       MS, Method, Detail, Rating, Pb, PbYield, As, Pult, AllowYld
%
%   Call graph:
%       Precedents (calls)      engine.boltDesignLoad.
%       Dependents (called by)  engine.analyze ("Insert internal-thread").
%       Tests                   tests/tThreadShear.m (the insert block).
%
%   Validation status/coverage: VALIDATION.md, Margin checks row 9 — the
%   arithmetic is one division; what is worth checking is that the right
%   allowable lands on the right row.

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "Insert internal-thread allowable = the value SPECIFIED for the procured insert (ThreadedMember.RatedUltimateLoad), per NASA-STD-5020B §4.4.1 — the first of the two insert allowables the standard names, and one that must come from the specification rather than thread-stripping analysis (p26: procured items can expand under load, reducing engagement areas). Ultimate only: a spec rating is an ultimate quantity and §4.4.2 prints no yield counterpart for one. MS = rating / Pb − 1, with Pb per NASA-STD-5020B Eq. 8 (clamped, PpMax+FFU·FSU·n·phi·PtL) or, when the Fig. 8 gate assures separation before rupture, Pb = FFU·FSU·PtL (Eq. 6 principle, no preload/n·phi — see Detail for which branch applied)";

if joint.ThreadedMember.Type ~= model.ThreadedMemberType.Insert
    r = notEval(method, "Not evaluated: threaded member is not an insert (" + ...
        string(joint.ThreadedMember.Type) + ").");
    return
end

rating = joint.ThreadedMember.RatedUltimateLoad;   % specified allowable, lbf (0 = none)
if isnan(rating) || rating <= 0
    r = notEval(method, ...
        "Not evaluated: no internal-thread allowable is specified for this " + ...
        "insert (ThreadedMember.RatedUltimateLoad). NASA-STD-5020B §4.4.1 " + ...
        "requires this value to come from the insert or procurement " + ...
        "specification, so it is not derived here. Insert pull-out from the " + ...
        "parent is a separate check and is reported on its own row.");
    return
end

d = engine.boltDesignLoad(joint, loadCase, factors, preload);
if isnan(d.Pb)
    r = notEval(method, "Not evaluated: " + d.Note + ".");
    r.Rating = rating;
    return
end

% NASA-STD-5020B §4.4.1 — MS = P_allow / Pb − 1 on the SPECIFIED insert
% internal-thread allowable (thread-family convention: factors sit inside
% Pb on the external term).
MS = rating / d.Pb - 1;

detail = string(sprintf( ...
    "specified internal-thread allowable %.0f lbf, Pb %.0f lbf", rating, d.Pb));
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end

r = struct("MS", MS, "Method", method, "Detail", detail + ".", ...
    "Rating", rating, "Pb", d.Pb, "PbYield", NaN, ...
    "As", NaN, "Pult", rating, "AllowYld", NaN);
end

% ---- Local helpers --------------------------------------------------------
function r = notEval(method, detail)
%NOTEVAL  A full-field NotEvaluated result (every branch returns the same fields).
r = struct("MS", NaN, "Method", method, "Detail", string(detail), ...
    "Rating", NaN, "Pb", NaN, "PbYield", NaN, ...
    "As", NaN, "Pult", NaN, "AllowYld", NaN);
end
