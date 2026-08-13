function p = preload(joint)
%PRELOAD  Min/max bolt preload incl. thermal (NASA-STD-5020B Eq. 3/4/5 + Eq. 24
%   + Eq. 1/2; thermal change per NASA TM-106943 Eq. 10).
%   p = engine.preload(joint) computes the initial and worst-case preloads
%   for one joint. All loads in lbf, torque in in-lbf, temperature in °C
%   (see UNITS.md).
%
%   Returned struct fields (all lbf):
%       PpiMax       max initial preload at installation (Eq. 3)
%       PpiMin       min initial preload at installation (Eq. 4/5)
%       ThermalDelta thermal preload GAIN applied on the max side (>= 0;
%                    = P_thermal_max below)
%       PpMax        max in-service preload = PpiMax + P_thermal_max
%       PpMin        min in-service preload =
%                    (1 - relaxation)·PpiMin - creep - P_thermal_min
%
%   Preload method (PreloadSpec.Method):
%     TorqueControl — nominal torque + tolerance, NASA-STD-5020B c-factor form:
%         Ppi_nom = T_nom / (K·D)                                 (Eq. 24)
%         PpiMax  = c_max·(1 + Γ)·Ppi_nom                         (Eq. 3)
%         PpiMin  = c_min·(1 - Γ)·Ppi_nom      separation-critical (Eq. 4)
%         PpiMin  = c_min·(1 - Γ/√nf)·Ppi_nom  otherwise           (Eq. 5)
%       where c_max = 1 + TorqueTolerance and c_min = 1 - TorqueTolerance
%       are the NASA-STD-5020B torque-tolerance factors (§4.3.1: "40 ± 2 N-m" ->
%       c_max = 1.05, c_min = 0.95), Γ = PreloadSpec.Uncertainty, and
%       nf = joint.BoltCount.
%     DirectPreload — nominal preload specified directly:
%         PpiMax = (1 + Γ)·Pnom,   PpiMin = (1 - Γ)·Pnom
%
%   WASHERS ARE IN THE THERMAL SUM (corrected 2026-08-13). They are rigid
%   in the FRUSTUM — kc legitimately spans the flange stack alone — but they
%   are not thermally absent: they sit in the clamped stack, carry the clamp
%   load, and expand with their own CTE. Dropping them while kb spanned them
%   was arithmetically identical to assuming every washer shares the BOLT's
%   CTE, so the error is exactly (α_washer − α_bolt)·t_washer and VANISHES
%   when they match. On a steel washer (1.17e-5) under an A-286 bolt
%   (1.69e-5) the old form ran ~17% HIGH on the Ex 8-b geometry —
%   conservative there, but unconservative whenever α_washer > α_bolt.
%
%   Thermal: preload change from CTE mismatch per NASA TM-106943 (Chambers)
%   Eq. 10 — P_th = (Kb·Kc)/(Kb+Kc)·L·ΔT·(αj − αb) — with the stiffnesses
%   from engine.stiffness, L = engine.stiffness's Lbolt (the WASHER-INCLUSIVE
%   clamped length kb spans — Eq. 10 carries ONE L, shared by its Eq. 6 bolt
%   term and Eq. 7 joint term, so the span the bolt stretches over is the
%   span the members expand over), αj the thickness-weighted member
%   CTE, and αb the bolt CTE. Both temperature excursions are evaluated:
%   the worst preload GAIN goes on the max side (P_thermal_max) and the
%   worst preload LOSS on the min side (P_thermal_min); each is floored at
%   zero. If PreloadSpec.ThermalRate is set (nonzero, non-NaN) it OVERRIDES
%   the stiffness form: ThermalDelta = ThermalRate (lbf/°C) × the larger
%   excursion from ReferenceTemperature, applied symmetrically (+ on the
%   max side, - on the min side — conservative both ways). ThermalRate is
%   NOT an analyst-facing input (no GUI control, no bulk-template column —
%   see model.PreloadSpec); it is set programmatically only, by validation
%   fixtures that need to reproduce a book answer key without full frustum
%   geometry (e.g. validation.dabjSection9). Every GUI- or template-built
%   joint carries ThermalRate = 0, so it always takes the stiffness path.
%   On the stiffness path, engine.stiffness errors (threaded-in
%   configuration, missing frustum geometry) propagate: supply the
%   geometry (or, for a code-built validation fixture only, a ThermalRate
%   override).
%
%   Call graph:
%       Precedents (calls)      engine.stiffness — thermal path only, when
%                               PreloadSpec.ThermalRate is unset/zero AND a
%                               temperature excursion exists (Max or Min
%                               differs from Reference); NOT wrapped in a
%                               try/catch here (contrast engine.boltDesignLoad,
%                               engine.marginTensionUlt, and
%                               engine.marginBearingUnderHead, which all
%                               catch engine.stiffness's errors and report
%                               NotEvaluated instead of propagating them).
%       Dependents (called by)  engine.analyze, engine.summary.
%       Tests                   tests/tDabjCase.m — preloadMatchesDABJ,
%                               torqueBandDerivedFromNominal;
%                               tests/tStiffness.m — thermalFromStiffness
%                               (stiffness-path thermal term),
%                               tensionRuptureBranch (rupture-branch fixture).
%
%   Validation status/coverage: see VALIDATION.md (Preload, rows 1-4).

arguments
    joint (1,1) model.Joint
end

ps = joint.PreloadSpec;
G  = ps.Uncertainty;                 % Γ

% ---- Initial (installation) preload range ------------------------------
switch ps.Method
    case model.PreloadMethod.TorqueControl
        D  = joint.Bolt.NominalDiameter;    % in
        K  = ps.NutFactor;
        nf = joint.BoltCount;
        % NASA-STD-5020B Eq. 24 — Ppi_nom = T / (Knom·D)
        PpiNom = ps.NominalTorque / (K * D);
        % NASA-STD-5020B torque-tolerance factors — c_max = 1 + tol, c_min = 1 - tol
        cMax = 1 + ps.TorqueTolerance;
        cMin = 1 - ps.TorqueTolerance;
        % NASA-STD-5020B Eq. 3 — Ppi_max = c_max·(1 + Γ)·Ppi_nom
        PpiMax = cMax * (1 + G) * PpiNom;
        if ps.SeparationCritical
            % NASA-STD-5020B Eq. 4 (separation-critical) — Ppi_min = c_min·(1 - Γ)·Ppi_nom
            PpiMin = cMin * (1 - G) * PpiNom;
        else
            % NASA-STD-5020B Eq. 5 (not separation-critical) — Ppi_min = c_min·(1 - Γ/√nf)·Ppi_nom
            PpiMin = cMin * (1 - G/sqrt(nf)) * PpiNom;
        end
    case model.PreloadMethod.DirectPreload
        % NASA-STD-5020B Eq. 3/4 uncertainty form with c = 1 (no torque
        % tolerance) — PpiMax = (1 + Γ)·Pnom, PpiMin = (1 - Γ)·Pnom
        PpiMax = (1 + G) * ps.NominalPreload;
        PpiMin = (1 - G) * ps.NominalPreload;
    otherwise
        error("engine:preload:unknownMethod", ...
            "Unsupported preload method: %s", string(ps.Method));
end

% ---- Thermal preload change (max-side gain / min-side loss, °C) --------
if ~isnan(ps.ThermalRate) && ps.ThermalRate ~= 0
    % Override path: supplied rate × the larger excursion from reference,
    % applied SYMMETRICALLY (+ on max, - on min — conservative both ways).
    % NASA TM-106943 (Chambers) Eq. 10 approximated by a supplied rate —
    % ThermalDelta = ThermalRate·dT
    dT = max(joint.MaxTemperature - joint.ReferenceTemperature, ...
             joint.ReferenceTemperature - joint.MinTemperature);
    td = ps.ThermalRate * dT;                                % lbf
    PthermalMax = td;
    PthermalMin = td;
else
    % Stiffness path: compute the CTE-mismatch preload change from the
    % joint stiffness for BOTH excursions (hot and cold).
    dThot  = joint.MaxTemperature - joint.ReferenceTemperature;   % °C, >= 0
    dTcold = joint.MinTemperature - joint.ReferenceTemperature;   % °C, <= 0
    if dThot == 0 && dTcold == 0
        % No thermal excursion — no CTE-mismatch load (stiffness not needed).
        PthermalMax = 0;
        PthermalMin = 0;
    else
        % engine.stiffness errors (threaded-in configuration, missing
        % frustum geometry) propagate — supply the geometry or a
        % ThermalRate override.
        s = engine.stiffness(joint);
        kSeries = s.Kb * s.Kc / (s.Kb + s.Kc);   % bolt+members in series, lbf/in

        % THE SPAN COMES FROM engine.stiffness, NOT FROM GripLength.
        % TM-106943 Eq. 10 carries ONE L, shared by the bolt term and the
        % joint term — its Eq. 6/7 are
        %     delta_b = Pth/Kb + alpha_b·L·dT
        %     delta_j = -Pth/Kj + alpha_j·L·dT
        % equated to give Eq. 10. So L must be the span the bolt actually
        % stretches over, which is the WASHER-INCLUSIVE clamped length kb
        % was built over. This used to read joint.GripLength (the flange
        % stack ALONE) while kb spanned grip + washers — see the header's
        % washer note for what that cost.
        L = s.Lbolt;                             % washer-inclusive clamped length, in

        % Thickness-weighted member CTE over that SAME span: flange layers
        % AND washers. A washer is rigid in the frustum (it adds no member
        % compliance, so Kc legitimately spans the flanges only) but it is
        % NOT thermally absent — it sits in the clamped stack, carries the
        % clamp load, and expands with its own CTE.
        tMem   = [joint.FlangeStack.Thickness];
        cteMem = arrayfun(@(fl) fl.Material.CTE, joint.FlangeStack);
        for w = [joint.HeadWasher, joint.NutWasher]
            if w.Thickness > 0
                tMem(end+1)   = w.Thickness;   %#ok<AGROW>
                cteMem(end+1) = w.Material.CTE; %#ok<AGROW>
            end
        end
        alphaB = joint.BoltMaterial.CTE;         % bolt CTE, 1/°C

        % NO CONFIDENT NUMBER FROM AN INPUT NOBODY SUPPLIED. Two failure
        % routes, both now closed. Until 2026-08-13 model.Material.CTE
        % DEFAULTED TO ZERO, so an unspecified material was read as "does
        % not expand" — a physical claim, not an absence — and this term
        % produced a confident number from data that was never given.
        % (library.json's Rigid entry even documented a guard against
        % that, which did not exist.) CTE now defaults to NaN so the
        % absence is detectable; without the check below that NaN would
        % reach Pth and then vanish anyway, because max([NaN NaN 0]) is 0
        % in MATLAB — the same silent failure by a quieter route. Refuse
        % instead, naming what to fix.
        requireCTE(joint, tMem, cteMem, alphaB);

        alphaJ = sum(tMem .* cteMem) / sum(tMem);
        % NASA TM-106943 (Chambers) Eq. 10 — Pth = (Kb·Kc/(Kb+Kc))·L·ΔT·(αj − αb)
        PthHot  = kSeries * L * dThot  * (alphaJ - alphaB);  % lbf
        PthCold = kSeries * L * dTcold * (alphaJ - alphaB);  % lbf
        % Worst preload GAIN on the max side, worst LOSS on the min side,
        % each floored at zero (an excursion that only helps is not credited).
        PthermalMax = max([PthHot, PthCold, 0]);
        PthermalMin = max([-PthHot, -PthCold, 0]);
    end
end
ThermalDelta = PthermalMax;                      % reported: max-side gain, lbf

% ---- In-service min/max preload ----------------------------------------
% NASA-STD-5020B Eq. 1 — PpMax = PpiMax + P_thermal_max
PpMax = PpiMax + PthermalMax;
% NASA-STD-5020B Eq. 2 — PpMin = (1 - relaxation)·PpiMin - creep - P_thermal_min
PpMin = (1 - ps.RelaxationFraction) * PpiMin - ps.CreepLoss - PthermalMin;

p = struct( ...
    "PpiMax",       PpiMax, ...
    "PpiMin",       PpiMin, ...
    "ThermalDelta", ThermalDelta, ...
    "PpMax",        PpMax, ...
    "PpMin",        PpMin);
end

% ---- Local helpers --------------------------------------------------------
function requireCTE(joint, tMem, cteMem, alphaB)
%REQUIRECTE  Refuse a thermal calculation that is missing a coefficient.
%   NASA-STD-5020B Table 1 (p22) defines P_dt as the change of preload with
%   temperature, and TFSR 5 (§4.3.1, p21) REQUIRES max/min preload to
%   account for "the effects of maximum and minimum expected temperatures".
%   A CTE-mismatch term computed with a missing coefficient is not a
%   conservative approximation of that requirement. It is not even
%   conservative in a known direction: an absent coefficient read as zero
%   understates the mismatch when the real material expands more than the
%   bolt and OVERSTATES it when less, and the analyst has no way to tell
%   which from the reported margin.
%
%   Errors rather than returning a NotEvaluated marker because engine.preload
%   returns PpMax/PpMin, which every downstream margin consumes as a number;
%   there is no "not evaluated" preload for them to propagate. This mirrors
%   the engine.stiffness errors that already propagate out of this same
%   branch. engine.analyzeBulk catches per row and reports it in the Error
%   column, so one under-specified joint never takes down a bulk run.
missing = strings(1, 0);
if isnan(alphaB)
    missing(end+1) = "bolt material """ + joint.BoltMaterial.Name + """";
end
for k = 1:numel(cteMem)
    if isnan(cteMem(k))
        missing(end+1) = string(sprintf("a clamped member of %.4g in thickness", tMem(k))); %#ok<AGROW>
    end
end
if isempty(missing)
    return
end
error("engine:preload:missingCTE", ...
    "Thermal preload (NASA TM-106943 Eq. 10, required by NASA-STD-5020B " + ...
    "TFSR 5) needs a coefficient of thermal expansion for every part in " + ...
    "the clamped stack, and these have none: %s. Add a CTE to the " + ...
    "material in the hardware library, or set PreloadSpec.ThermalRate to " + ...
    "supply the preload change directly. Washers count: they sit in the " + ...
    "clamped stack and expand even though the frustum model treats them " + ...
    "as rigid.", strjoin(missing, "; "));
end
