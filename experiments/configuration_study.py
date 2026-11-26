"""Experiments D and E: university configurations and correlated collusion.

Everything here is exact (enumeration over the number of people per office),
so there is no sampling error and no seed.

D. For several staffings (registrars, deans, exam officers) compare the
   role-agnostic threshold (C) with the role-constrained one (D):
     k         smallest capable coalition
     s         absences always tolerated
     fraction  share of k-person coalitions that are capable
     complete  P(issuance can complete), 10% individual absence, with and
               without a 5% whole-role outage
   Delegates are modelled as additional permanent holders of a role, e.g.
   2-3-2 plus one delegate registrar and one delegate exam officer = 3-3-3
   with the threshold left at 4.

E. Correlated compromise. Each person is compromised with marginal
   probability p. With probability rho an office is "captured as a block" (one
   shared draw for the whole office); otherwise its members are independent.
   Any two members of an office then have correlation rho. Offices are
   independent of each other, except that with probability gamma the whole
   university shares one draw (cross-office correlation). rho, gamma and p are
   ASSUMPTIONS to be varied, not estimates.

   Every coalition capable under D is capable under C, so D never has the
   higher fraud probability. The question is whether the reduction is worth
   the issuances D loses:
       break_even = (complete_C - complete_D) / (fraud_C - fraud_D)
   i.e. how many times worse a capable compromised set must be than a blocked
   issuance before D is preferable. It compares two different kinds of event
   and is only an aid to judgement.

Outputs: data/configuration_results.csv, data/correlation_results.csv
"""

from __future__ import annotations

import csv
from itertools import product
from math import comb

from common import DATA

ABSENCE = 0.10
OUTAGE = 0.05
Config = tuple[int, int, int]

# (staffing, threshold, note). Thresholds are strict majorities unless noted.
CONFIGS: list[tuple[Config, int, str]] = [
    ((2, 3, 2), 4, "primary"),
    ((3, 3, 3), 4, "2-3-2 with two delegates, threshold kept"),
    ((3, 3, 3), 5, "majority"),
    ((3, 5, 3), 6, "majority"),
    ((4, 4, 4), 7, "majority"),
    ((4, 8, 4), 9, "majority"),
]

P_GRID = (0.05, 0.10, 0.20)
RHO_GRID = tuple(round(0.1 * i, 1) for i in range(11))
GAMMA_GRID = (0.0, 0.02)


def satisfied(counts: tuple[int, ...], m: int, roles: bool) -> bool:
    return sum(counts) >= m and (not roles or all(c >= 1 for c in counts))


def office_counts(cfg: Config):
    return product(*(range(n + 1) for n in cfg))


def ways(cfg: Config, counts: tuple[int, ...]) -> int:
    w = 1
    for n, c in zip(cfg, counts):
        w *= comb(n, c)
    return w


def capable_at(cfg: Config, m: int, roles: bool, k: int) -> tuple[int, int]:
    cap = sum(ways(cfg, c) for c in office_counts(cfg) if sum(c) == k and satisfied(c, m, roles))
    return cap, comb(sum(cfg), k)


def k_and_s(cfg: Config, m: int, roles: bool) -> tuple[int, int]:
    n = sum(cfg)
    k = next(i for i in range(1, n + 1) if capable_at(cfg, m, roles, i)[0])
    s = -1
    for absent in range(n + 1):
        if any(not satisfied(c, m, roles) for c in office_counts(cfg) if sum(c) == n - absent):
            break
        s = absent
    return k, s


def binom(n: int, c: int, p: float) -> float:
    return comb(n, c) * p**c * (1 - p) ** (n - c)


def completion(cfg: Config, m: int, roles: bool, absence: float, outage: float) -> float:
    """P(those present can satisfy the policy); offices independent."""

    def office(n: int, c: int) -> float:
        up = (1 - outage) * binom(n, c, 1 - absence)
        return up + (outage if c == 0 else 0.0)

    return sum(
        office(cfg[0], c[0]) * office(cfg[1], c[1]) * office(cfg[2], c[2])
        for c in office_counts(cfg)
        if satisfied(c, m, roles)
    )


def fraud(cfg: Config, m: int, roles: bool, p: float, rho: float, gamma: float = 0.0) -> float:
    """P(compromised set can issue) under the block-capture model."""

    def office(n: int, c: int) -> float:
        block = p if c == n else (1 - p if c == 0 else 0.0)
        return rho * block + (1 - rho) * binom(n, c, p)

    separate = sum(
        office(cfg[0], c[0]) * office(cfg[1], c[1]) * office(cfg[2], c[2])
        for c in office_counts(cfg)
        if satisfied(c, m, roles)
    )
    return gamma * p + (1 - gamma) * separate


def main() -> None:
    rows = []
    for cfg, m, note in CONFIGS:
        for roles in (False, True):
            k, s = k_and_s(cfg, m, roles)
            cap, tot = capable_at(cfg, m, roles, k)
            rows.append([
                "-".join(map(str, cfg)), sum(cfg), m, note, "D" if roles else "C", k, s, cap, tot, round(cap / tot, 6),
                round(completion(cfg, m, roles, ABSENCE, 0.0), 6),
                round(completion(cfg, m, roles, ABSENCE, OUTAGE), 6),
            ])
    _write("configuration_results.csv",
           ["staffing", "n", "threshold", "note", "policy", "k", "s", "capable_at_k", "total_at_k",
            "fraction_at_k", "complete_absence10", "complete_absence10_outage5"], rows)

    rows = []
    for cfg, m, note in (CONFIGS[0], CONFIGS[2]):
        cc = completion(cfg, m, False, ABSENCE, OUTAGE)
        cd = completion(cfg, m, True, ABSENCE, OUTAGE)
        for p in P_GRID:
            for gamma in GAMMA_GRID:
                for rho in RHO_GRID:
                    fc, fd = (fraud(cfg, m, r, p, rho, gamma) for r in (False, True))
                    rows.append(["-".join(map(str, cfg)), m, p, gamma, rho, f"{fc:.9f}", f"{fd:.9f}",
                                 round(1 - fd / fc, 6), round((cc - cd) / (fc - fd), 4)])
    _write("correlation_results.csv",
           ["staffing", "threshold", "p", "gamma", "rho", "fraud_C", "fraud_D", "relative_reduction",
            "break_even"], rows)
    print("configurations:", len(CONFIGS), " correlation points:", len(rows))


def _write(name: str, header: list[str], rows: list[list]) -> None:
    with (DATA / name).open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


if __name__ == "__main__":
    main()
