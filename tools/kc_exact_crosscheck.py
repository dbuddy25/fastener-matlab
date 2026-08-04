#!/usr/bin/env python3
"""Exact per-layer member stiffness, as a cross-check on the Ebar collapse.

WHY THIS EXISTS
    Job B (STIFFNESS_PLAN.md section 3) adopts the general asymmetric frustum
    form, which collapses a multi-material stack to a single harmonic mean
    modulus Ebar = L / sum(t_i/E_i). That is EXACT whenever every material
    boundary lands on the frustum knee plane -- the canonical two-plate joint --
    and approximate otherwise, because it weights layers by thickness alone
    while true series compliance weights by the integral of dx/A(x), and A is
    smallest at the bearing faces.

    This script computes the exact per-layer result so a suspicious joint can be
    checked in a minute instead of re-deriving the argument. It is a TOOL, not
    part of the engine: nothing in matlab/ imports it.

METHOD
    With f(d) = ln[(d + D)/(d - D)], the compliance of one frustum running from
    diameter da to db is (f(da) - f(db)) / (pi*E*D*tan(alpha)) -- Shigley,
    algebraically identical to SAND2008-0371 Eq. (18). Two opposing cones grow
    at tan(alpha) from the head bearing diameter d1 and the nut bearing diameter
    d2, meeting where

        x_knee = L/2 + (d2 - d1)/(4*tan(alpha))
        d3     = (d1 + d2)/2 + L*tan(alpha)

    Cutting at each layer boundary AND at the knee, then summing compliances:

        1/kc = (1/(pi*D*tan(alpha))) * sum over segments of
               [ f(d_in) - f(d_out) ] / E_segment

    With every E equal this telescopes to (f1 + f2 - 2*f3)/E, i.e. exactly the
    slide's closed form -- so the reduction check below is analytic, not
    empirical.

USAGE
    python3 tools/kc_exact_crosscheck.py        # runs the self-checks

    Or import exact_kc / ebar_kc and pass your own stack as [(t, E), ...]
    ordered from the HEAD face to the nut face.
"""

import math

ALPHA_DEG = 30.0  # frustum half-angle; see STIFFNESS_PLAN.md section 5 on why not 45


def _f(d, D):
    return math.log((d + D) / (d - D))


def exact_kc(D, d1, d2, layers, alpha_deg=ALPHA_DEG):
    """Per-layer frustum, series-combined, cut at layer boundaries and the knee.

    D       bolt nominal diameter, in
    d1, d2  head-side and nut-side cone start diameters, in
    layers  [(thickness_in, modulus_psi), ...] ordered head -> nut
    """
    tA = math.tan(math.radians(alpha_deg))
    L = sum(t for t, _ in layers)
    x_knee = L / 2 + (d2 - d1) / (4 * tA)
    if not 0 < x_knee < L:
        raise ValueError(
            f"knee at x={x_knee:.4f} falls outside the grip (0, {L:.4f}) -- "
            "the bearing diameters are too dissimilar for two cones to meet "
            "inside the stack"
        )

    comp = 0.0
    # Head-side cone: x from 0 to x_knee, diameter d1 + 2*x*tanA
    x = 0.0
    for t, E in layers:
        if x >= x_knee:
            break
        seg = min(t, x_knee - x)
        comp += (_f(d1 + 2 * x * tA, D) - _f(d1 + 2 * (x + seg) * tA, D)) / E
        x += t
    # Nut-side cone: y from 0 to L - x_knee measured from the nut face
    y, y_lim = 0.0, L - x_knee
    for t, E in reversed(layers):
        if y >= y_lim:
            break
        seg = min(t, y_lim - y)
        comp += (_f(d2 + 2 * y * tA, D) - _f(d2 + 2 * (y + seg) * tA, D)) / E
        y += t

    return (math.pi * D * tA) / comp


def ebar_kc(D, d1, d2, layers, alpha_deg=ALPHA_DEG):
    """The collapsed form: one cone pair, single harmonic-mean modulus."""
    tA = math.tan(math.radians(alpha_deg))
    L = sum(t for t, _ in layers)
    Ebar = L / sum(t / E for t, E in layers)
    d3 = (d1 + d2) / 2 + L * tA
    return math.pi * D * Ebar * tA / (_f(d1, D) + _f(d2, D) - 2 * _f(d3, D))


def _self_check():
    STEEL, ALUM, TI, COMP = 29e6, 10e6, 16e6, 8e6
    D, dc = 0.25, 0.40

    cases = [
        ("uniform (reduction check)", [(0.25, ALUM), (0.25, ALUM)]),
        ("steel / alum, two equal layers", [(0.25, STEEL), (0.25, ALUM)]),
        ("thin steel shim at head", [(0.06, STEEL), (0.44, ALUM)]),
        ("Ti / alum / Ti", [(0.15, TI), (0.20, ALUM), (0.15, TI)]),
        ("soft composite at mid", [(0.20, STEEL), (0.10, COMP), (0.20, STEEL)]),
        ("soft composite at both faces", [(0.10, COMP), (0.30, STEEL), (0.10, COMP)]),
    ]
    print(f"{'stack':<34}{'exact kc':>13}{'Ebar kc':>13}{'kc err':>9}")
    print("-" * 69)
    for name, lay in cases:
        ke, kE = exact_kc(D, dc, dc, lay), ebar_kc(D, dc, dc, lay)
        print(f"{name:<34}{ke:>13,.0f}{kE:>13,.0f}{100 * (kE - ke) / ke:>8.1f}%")

    # Reduction: uniform modulus must agree to machine precision.
    uni = [(0.25, ALUM), (0.25, ALUM)]
    assert abs(exact_kc(D, dc, dc, uni) / ebar_kc(D, dc, dc, uni) - 1) < 1e-12

    # Split invariance: splitting a layer must not change the exact result.
    a = exact_kc(D, dc, dc, [(0.40, ALUM), (0.10, STEEL)])
    b = exact_kc(D, dc, dc, [(0.20, ALUM), (0.20, ALUM), (0.10, STEEL)])
    assert abs(a / b - 1) < 1e-12

    # Order blindness: same layers reversed, asymmetric bearing diameters so the
    # reversal is not a mirror. Ebar cannot tell them apart; exact can.
    lay = [(0.35, STEEL), (0.15, ALUM)]
    e1, e2 = exact_kc(D, 0.40, 0.50, lay), exact_kc(D, 0.40, 0.50, lay[::-1])
    b1, b2 = ebar_kc(D, 0.40, 0.50, lay), ebar_kc(D, 0.40, 0.50, lay[::-1])
    print(f"\norder sensitivity (d1=0.40, d2=0.50):")
    print(f"  steel head / alum nut   exact {e1:>12,.0f}   Ebar {b1:>12,.0f}")
    print(f"  alum head / steel nut   exact {e2:>12,.0f}   Ebar {b2:>12,.0f}")
    assert abs(b1 / b2 - 1) < 1e-12, "Ebar should be order-blind"
    assert abs(e1 / e2 - 1) > 0.10, "exact should see the order"

    print("\nself-checks passed (reduction, split invariance, order sensitivity)")


if __name__ == "__main__":
    _self_check()
