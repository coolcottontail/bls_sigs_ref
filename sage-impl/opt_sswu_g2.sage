#!/usr/bin/env sage
# vim: syntax=python

import sys

from util import get_cmdline_options
try:
    from __sage__g1_common import Hp2, p, sgn0
    from __sage__g2_common import Ell2, F2, X, roots_of_unity, clear_h2, print_g2_hex, print_iv_F2
    from __sage__bls_sig_common import print_hash_test_vector
except ImportError:
    sys.exit("Error loading preprocessed sage files. Try running `make clean pyfiles`")

# 3-isogenous curve to Ell2
Ell2p_a = F2(240 * X)
Ell2p_b = F2(1012 * (1 + X))
Ell2p = EllipticCurve(F2, [Ell2p_a, Ell2p_b])
# isogeny map back to Ell2
# since this takes a while to compute, save it in a file and reload it from disk
try:
    iso2 = load("iso_g2")
    assert iso2.codomain() == Ell2
except:
    iso2 = EllipticCurveIsogeny(Ell2p, [6 * (1 - X), 1], codomain=Ell2)
    iso2.dump("iso_g2", True)

# xi is the distinguished non-square for the SWU map
xi_2 = F2(-2 - X)
# eta values for converting a failed attempt at sqrt(g(X0(t))) to sqrt(g(X1(t)))
sqrt_sqrt_m1 = sqrt(X)
sqrt_sqrt_m1 *= sgn0(sqrt_sqrt_m1)
sqrt_m_sqrt_m1 = sqrt(-X)
sqrt_m_sqrt_m1 *= sgn0(sqrt_m_sqrt_m1)
eta1 = sqrt(xi_2 ** 3 / sqrt_sqrt_m1)
eta3 = sqrt(xi_2 ** 3 / sqrt_m_sqrt_m1)
etas = (eta1, X * eta1, eta3, X * eta3)
etas = tuple( sgn0(eta) * eta for eta in etas )

# y^2 = g2p(x) is the curve equation for Ell2p
def g2p(x):
    return F2(x**3 + Ell2p_a * x + Ell2p_b)

# apply optimized simplified SWU map to a point t
def osswu2_help(t):
    # compute the value X0(t)
    num_den_common = F2(xi_2 ** 2 * t ** 4 + xi_2 * t ** 2)
    if num_den_common == 0:
        # exceptional case: use x0 = Ell2p_b / (xi_2 * Ell2p_a), which is square by design
        x0 = F2(Ell2p_b) / F2(xi_2 * Ell2p_a)
    else:
        x0 = F2(-Ell2p_b * (num_den_common + 1)) / F2(Ell2p_a * num_den_common)
    print_iv_F2(x0, "x0", "osswu2_help")

    # g(X0), where y^2 = g(x) is the curve 3-isogenous to BLS12-381 Ell2
    gx0 = g2p(x0)

    # check whether gx0 is square by computing gx0 ^ ((p+1)/4)
    sqrt_candidate = gx0 ** ((p**2 + 7) // 16)
    # the square root will be given by sqrt_candidate times a root of unity; check them all
    for root_of_unity in roots_of_unity:
        y0_candidate = sqrt_candidate * root_of_unity
        if y0_candidate ** 2 == gx0:
            y0 = sgn0(t) * sgn0(y0_candidate) * y0_candidate
            assert sgn0(y0) == sgn0(t)
            return Ell2p(x0, y0)

    # if we got here, the g(X0(t)) was not square
    # X1(t) == xi t^2 X0(t), g(X1(t)) = xi^2 t^6 X0(t)
    x1 = F2(xi_2 * t ** 2 * x0)
    gx1 = xi_2 ** 3 * t ** 6 * gx0
    assert gx1 == g2p(x1)

    # if g(X0(t)) is not square, then sqrt(g(X1(t))) == eta * t^3 * g(X0(t)) ^ ((p+7)/16) for one of the etas above
    for eta_value in etas:
        y1_candidate = sqrt_candidate * eta_value * t ** 3
        if y1_candidate ** 2 == gx1:
            y1 = sgn0(t) * sgn0(y1_candidate) * y1_candidate
            return Ell2p(x1, y1)

    # if we got here, something went very wrong
    raise RuntimeError("osswu2_help failed")

# F2 elm from vector of F elms
def from_vec(v):
    return F2(v[0] + X * v[1])

# map from a string
def map2curve_osswu2(alpha, dst):
    t1 = from_vec(Hp2(alpha, 0, dst))
    t2 = from_vec(Hp2(alpha, 1, dst))
    P = osswu2_help(t1)
    P2 = osswu2_help(t2)
    return clear_h2(iso2(P + P2))

if __name__ == "__main__":
    (_, sig_inputs) = get_cmdline_options()
    for hash_in in sig_inputs:
        print_hash_test_vector(hash_in, '\x02', map2curve_osswu2, print_g2_hex, Ell2)
