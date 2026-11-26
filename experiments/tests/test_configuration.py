"""Checks for configuration_study.py (experiments D and E)."""

import csv
from math import comb

import pytest

import configuration_study as cs
from common import DATA

P = (2, 3, 2)


def test_matches_primary_results():
    assert cs.k_and_s(P, 4, False) == (4, 3)
    assert cs.k_and_s(P, 4, True) == (4, 1)
    assert cs.capable_at(P, 4, True, 4) == (24, 35)


@pytest.mark.parametrize("key,roles", [("C_majority_4of7", False), ("D_role_4of7", True)])
def test_closed_form_completion_matches_simulation(key, roles):
    with (DATA / "availability_results.csv").open(newline="") as f:
        for r in csv.DictReader(f):
            if r["policy"] != key:
                continue
            exact = cs.completion(P, 4, roles, float(r["absence_prob"]), float(r["role_outage_prob"]))
            assert float(r["completion_rate"]) == pytest.approx(exact, abs=0.012)


def test_zero_correlation_is_independent_model():
    for roles, key in ((False, "C_majority_4of7"), (True, "D_role_4of7")):
        with (DATA / "coalition_probability.csv").open(newline="") as f:
            for r in csv.DictReader(f):
                if r["policy"] == key:
                    assert cs.fraud(P, 4, roles, float(r["p_compromise"]), 0.0) == pytest.approx(
                        float(r["p_issue"]), abs=1e-7)


def test_full_correlation_closed_form():
    # Offices captured as blocks: D needs all three; C (m=4 of 2-3-2) needs any two.
    p = 0.1
    assert cs.fraud(P, 4, True, p, 1.0) == pytest.approx(p**3)
    assert cs.fraud(P, 4, False, p, 1.0) == pytest.approx(3 * p**2 * (1 - p) + p**3)


def test_d_never_worse_than_c_on_security():
    for cfg, m, _ in cs.CONFIGS:
        for p in cs.P_GRID:
            for rho in cs.RHO_GRID:
                assert cs.fraud(cfg, m, True, p, rho) <= cs.fraud(cfg, m, False, p, rho) + 1e-15


def test_onchain_three_three_three():
    path = DATA / "configuration_onchain.csv"
    if not path.exists():
        pytest.skip("run: forge test --match-contract ConfigurationCheck")
    with path.open(newline="") as f:
        for r in csv.DictReader(f):
            cap, tot = cs.capable_at((3, 3, 3), int(r["threshold"]), r["policy"] == "D", int(r["size"]))
            assert cap == int(r["capable"]) and tot == comb(9, int(r["size"]))
