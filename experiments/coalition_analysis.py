"""Experiment A: insider-coalition resistance.

For every coalition size k = 1..7 we enumerate all C(7, k) subsets of the
university's employees (2 Registrars, 3 Deans, 2 Exam Officers) and check
whether that subset alone can satisfy each policy.

    success_fraction(k) = #capable k-coalitions / C(7, k)

This is a *combinatorial* exposure measure, not a probability of fraud.
`coalition_probability.csv` adds one explicitly labelled probability model:
each employee is compromised independently with probability p. That
independence assumption is ours and must be stated wherever it is used.

If data/coalition_onchain.csv exists (written by
`forge test --match-contract CoalitionExport`), every coalition outcome
computed here is checked against the outcome observed on the real contracts.

Outputs (data/):
    coalition_results.csv      policy, k, capable, total, success_fraction
    coalition_summary.csv      min coalition size, minimal winning coalitions, ...
    coalition_probability.csv  P(some compromised set can issue) vs p
"""

from __future__ import annotations

import csv
import sys
from itertools import combinations
from math import comb

import numpy as np

from common import DATA, N_STAFF, STAFF, Policy, can_issue, primary_policies, sensitivity_policies

P_GRID = np.round(np.linspace(0.0, 0.5, 51), 3)


def capable_masks(policy: Policy) -> dict[int, bool]:
    """Outcome for every non-empty coalition, keyed by bitmask (bit i = STAFF[i])."""
    out = {}
    for mask in range(1, 1 << N_STAFF):
        members = [STAFF[i] for i in range(N_STAFF) if mask >> i & 1]
        out[mask] = can_issue(policy, members)
    return out


def by_size(outcomes: dict[int, bool]) -> list[tuple[int, int, int]]:
    rows = []
    for k in range(1, N_STAFF + 1):
        masks = [sum(1 << i for i in c) for c in combinations(range(N_STAFF), k)]
        capable = sum(outcomes[m] for m in masks)
        rows.append((k, capable, len(masks)))
        assert len(masks) == comb(N_STAFF, k)
    return rows


def minimal_winning(outcomes: dict[int, bool]) -> list[int]:
    """Capable coalitions none of whose proper subsets is capable."""
    winners = [m for m, ok in outcomes.items() if ok]
    return [m for m in winners if not any(ok and (s & m) == s and s != m for s, ok in outcomes.items())]


def prob_issue(rows: list[tuple[int, int, int]], p: float) -> float:
    """P(the compromised set can issue), employees compromised i.i.d. with prob p.
    Valid because 'can issue' is monotone: any superset of a capable set is capable."""
    return sum(capable * p**k * (1 - p) ** (N_STAFF - k) for k, capable, _ in rows)


def load_onchain() -> dict[tuple[str, int], bool] | None:
    path = DATA / "coalition_onchain.csv"
    if not path.exists():
        return None
    with path.open(newline="") as f:
        return {(r["policy"], int(r["mask"])): r["can_issue"] == "1" for r in csv.DictReader(f)}


def main() -> int:
    policies = [(p, "primary") for p in primary_policies()]
    policies += [(p, "sensitivity") for p in sensitivity_policies() if p.key not in {q.key for q, _ in policies}]
    onchain = load_onchain()

    results, summary, probability = [], [], []
    mismatches = 0
    for pol, group in policies:
        outcomes = capable_masks(pol)
        if onchain is not None:
            for mask, ok in outcomes.items():
                if (pol.key, mask) not in onchain:
                    print(f"  missing on-chain outcome {pol.key} mask={mask}")
                    mismatches += 1
                elif onchain[(pol.key, mask)] != ok:
                    print(f"  MISMATCH {pol.key} mask={mask}: python={ok} chain={onchain[(pol.key, mask)]}")
                    mismatches += 1

        rows = by_size(outcomes)
        for k, capable, total in rows:
            results.append([pol.key, pol.label, group, k, capable, total, round(capable / total, 6)])

        mins = minimal_winning(outcomes)
        min_size = min(bin(m).count("1") for m in mins)
        summary.append(
            [
                pol.key,
                pol.label,
                group,
                min_size,
                sum(1 for m in mins if bin(m).count("1") == min_size),
                len(mins),
                sum(ok for ok in outcomes.values()),
                round(rows[min_size - 1][1] / rows[min_size - 1][2], 6),
            ]
        )
        for p in P_GRID:
            probability.append([pol.key, pol.label, group, float(p), round(prob_issue(rows, float(p)), 8)])

    _write("coalition_results.csv", ["policy", "label", "group", "k", "capable", "total", "success_fraction"], results)
    _write(
        "coalition_summary.csv",
        [
            "policy",
            "label",
            "group",
            "min_coalition_size",
            "smallest_capable_coalitions",
            "minimal_winning_coalitions",
            "capable_coalitions_total",
            "success_fraction_at_min_size",
        ],
        summary,
    )
    _write("coalition_probability.csv", ["policy", "label", "group", "p_compromise", "p_issue"], probability)

    if onchain is None:
        print("note: data/coalition_onchain.csv not found; skipped on-chain cross-check")
    elif mismatches:
        print(f"ERROR: {mismatches} coalition outcomes disagree with the contracts")
        return 1
    else:
        print(f"on-chain cross-check: all {len(policies) * 127} coalition outcomes agree")

    for row in summary:
        print(f"  {row[1]:<32} min coalition = {row[3]}  ({row[4]} smallest capable coalitions)")
    return 0


def _write(name: str, header: list[str], rows: list[list]) -> None:
    DATA.mkdir(exist_ok=True)
    with (DATA / name).open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


if __name__ == "__main__":
    sys.exit(main())
