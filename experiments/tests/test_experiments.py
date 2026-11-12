"""Sanity checks for the experiment code (run: python -m pytest experiments/tests)."""

from math import comb

import numpy as np
import pytest

import availability_simulation as av
import coalition_analysis as ca
from common import COMMITMENT_DOMAIN, canonical_json, commitment, document_hash, keccak256, majority, role_constrained
from common import primary_policies, single_issuer, unanimous
from credentials import generate

# The exact diploma string used in test/utils/CredentialFixture.sol.
FIXTURE_DIPLOMA = (
    '{"credentialType":"BachelorDiploma","degree":"BSc Computer Science","graduationDate":"2026-06-15",'
    '"honours":"Cum Laude","issuer":"NU-SYNTHETIC","studentId":"S-000001","studentName":"Aigerim Synthetic"}'
)


# ---------------- hashing ----------------
def test_keccak_known_vector():
    # keccak256("") is a well-known constant (Ethereum, not NIST SHA3-256).
    assert keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"


def test_domain_tag():
    assert COMMITMENT_DOMAIN == keccak256(b"KZ-ACADEMIC-CREDENTIAL-v1")


def test_canonical_json_matches_solidity_fixture():
    doc = {
        "studentName": "Aigerim Synthetic", "studentId": "S-000001", "issuer": "NU-SYNTHETIC",
        "honours": "Cum Laude", "graduationDate": "2026-06-15", "degree": "BSc Computer Science",
        "credentialType": "BachelorDiploma",
    }
    assert canonical_json(doc).decode() == FIXTURE_DIPLOMA


def test_any_change_changes_commitment():
    doc = {"a": 1, "b": "x"}
    salt = bytes(32)
    base = commitment(document_hash(doc), salt)
    assert commitment(document_hash({"a": 2, "b": "x"}), salt) != base
    assert commitment(document_hash(doc), b"\x01" + bytes(31)) != base


def test_generation_is_deterministic():
    assert generate(5) == generate(5)
    assert generate(5, seed=1) != generate(5)


# ---------------- Experiment A ----------------
def test_coalition_totals_are_binomial():
    for pol in primary_policies():
        for k, capable, total in ca.by_size(ca.capable_masks(pol)):
            assert total == comb(7, k) and 0 <= capable <= total


def test_known_coalition_counts():
    rows = {k: c for k, c, _ in ca.by_size(ca.capable_masks(role_constrained(4)))}
    assert rows[3] == 0 and rows[4] == 24  # 35 - 5 (no Registrar) - 1 (no Dean) - 5 (no Exam Officer)
    rows = {k: c for k, c, _ in ca.by_size(ca.capable_masks(single_issuer()))}
    assert rows[1] == 2  # either Registrar alone
    rows = {k: c for k, c, _ in ca.by_size(ca.capable_masks(unanimous()))}
    assert [rows[k] for k in range(1, 8)] == [0, 0, 0, 0, 0, 0, 1]


def test_role_constraint_never_weakens_threshold():
    for m in (3, 4, 5):
        c = ca.capable_masks(majority(m))
        d = ca.capable_masks(role_constrained(m))
        assert all(c[mask] or not d[mask] for mask in c)  # D-capable implies C-capable


@pytest.mark.parametrize("pol", primary_policies(), ids=lambda p: p.key)
def test_probability_model_endpoints(pol):
    rows = ca.by_size(ca.capable_masks(pol))
    assert ca.prob_issue(rows, 0.0) == 0.0
    assert ca.prob_issue(rows, 1.0) == pytest.approx(1.0)


# ---------------- Experiment C ----------------
def test_no_absence_everything_completes():
    delays = av.draw(np.random.default_rng(0), absence=0.0, role_outage=0.0)
    for key, pol, m in av.policy_set(4):
        assert av.evaluate(delays, pol, m)["completion_rate"] == 1.0


def test_full_absence_nothing_completes():
    delays = av.draw(np.random.default_rng(0), absence=1.0, role_outage=0.0)
    for key, pol, m in av.policy_set(4):
        assert av.evaluate(delays, pol, m)["completion_rate"] == 0.0


def test_unanimous_matches_closed_form():
    delays = av.draw(np.random.default_rng(1), absence=0.1, role_outage=0.0)
    rate = av.evaluate(delays, "B_unanimous", 7)["completion_rate"]
    assert rate == pytest.approx(0.9**7, abs=0.015)


def test_failure_breakdown_sums():
    delays = av.draw(np.random.default_rng(2), absence=0.2, role_outage=0.05)
    for key, pol, m in av.policy_set(4):
        r = av.evaluate(delays, pol, m)
        fails = r["fail_insufficient_count"] + r["fail_missing_role"] + r["fail_unanimity"]
        assert fails == pytest.approx(1 - r["completion_rate"])
