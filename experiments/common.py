"""Shared configuration and helpers for all experiments.

Everything that defines the experimental setup lives here so that the
coalition analysis, gas benchmark and availability simulation use exactly the
same university configuration and policy definitions as the Solidity code.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
FIGURES = ROOT / "figures"
TABLES = ROOT / "paper" / "tables"

# ---------------------------------------------------------------------------
# University configuration (primary experiment). Mirrors test/utils/CredentialFixture.sol.
# ---------------------------------------------------------------------------
REGISTRAR, DEAN, EXAM = "Registrar", "Dean", "ExamOfficer"
ROLES = (REGISTRAR, DEAN, EXAM)
STAFF: tuple[str, ...] = (REGISTRAR, REGISTRAR, DEAN, DEAN, DEAN, EXAM, EXAM)
N_STAFF = len(STAFF)

PRIMARY_THRESHOLD = 4
SENSITIVITY_THRESHOLDS = (3, 4, 5)

SEED = 435  # fixed seed used by every stochastic step


# ---------------------------------------------------------------------------
# Policies. Each predicate mirrors the corresponding Solidity policy's
# isEligible + isSatisfied, applied to the set of roles that approved.
# `present_total` is the number of active approvers (N); used by Unanimous.
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Policy:
    key: str  # stable id used in CSVs
    label: str  # human-readable name for figures
    eligible: Callable[[str], bool]
    satisfied: Callable[[dict[str, int], int, int], bool]  # (role_counts, total, n_eligible)


def _count(roles: Sequence[str], policy_eligible: Callable[[str], bool]) -> dict[str, int]:
    counts = {r: 0 for r in ROLES}
    for r in roles:
        if policy_eligible(r):
            counts[r] += 1
    return counts


def single_issuer() -> Policy:
    return Policy(
        "A_single",
        "A: Single issuer",
        eligible=lambda r: r == REGISTRAR,
        satisfied=lambda c, total, n: total >= 1,
    )


def unanimous() -> Policy:
    return Policy(
        "B_unanimous",
        "B: Unanimous (7-of-7)",
        eligible=lambda r: True,
        satisfied=lambda c, total, n: n > 0 and total == n,
    )


def majority(m: int = PRIMARY_THRESHOLD) -> Policy:
    return Policy(
        f"C_majority_{m}of7",
        f"C: Threshold {m}-of-7",
        eligible=lambda r: True,
        satisfied=lambda c, total, n: total >= m,
    )


def role_constrained(m: int = PRIMARY_THRESHOLD) -> Policy:
    return Policy(
        f"D_role_{m}of7",
        f"D: Role-constrained {m}-of-7",
        eligible=lambda r: True,
        satisfied=lambda c, total, n: total >= m and all(c[r] >= 1 for r in ROLES),
    )


def primary_policies() -> list[Policy]:
    return [single_issuer(), unanimous(), majority(), role_constrained()]


def sensitivity_policies() -> list[Policy]:
    out = []
    for m in SENSITIVITY_THRESHOLDS:
        out += [majority(m), role_constrained(m)]
    return out


def can_issue(policy: Policy, approver_roles: Sequence[str], staff: Sequence[str] = STAFF) -> bool:
    """Would approvals from `approver_roles` (a subset of `staff`) let this policy issue?"""
    counts = _count(approver_roles, policy.eligible)
    total = sum(counts.values())
    n_eligible = sum(1 for r in staff if policy.eligible(r))
    return policy.satisfied(counts, total, n_eligible)


# ---------------------------------------------------------------------------
# Credential hashing. Must match CredentialRegistry.computeCommitment.
# ---------------------------------------------------------------------------
def keccak256(data: bytes) -> bytes:
    return keccak.new(digest_bits=256, data=data).digest()


COMMITMENT_DOMAIN = keccak256(b"KZ-ACADEMIC-CREDENTIAL-v1")


def canonical_json(doc: dict) -> bytes:
    """Sorted keys, no insignificant whitespace, UTF-8, no trailing newline."""
    return json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def document_hash(doc: dict) -> bytes:
    return keccak256(canonical_json(doc))


def commitment(doc_hash: bytes, salt: bytes) -> bytes:
    """keccak256(abi.encode(DOMAIN, documentHash, salt)); abi.encode of three
    bytes32 values is their plain 96-byte concatenation."""
    assert len(doc_hash) == 32 and len(salt) == 32
    return keccak256(COMMITMENT_DOMAIN + doc_hash + salt)


def hex32(b: bytes) -> str:
    return "0x" + b.hex()
