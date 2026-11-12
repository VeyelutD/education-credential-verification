"""Experiment C: approval-workflow availability and delay (Monte Carlo).

This simulates *human* workflow time only. It contains no blockchain timing:
on-chain execution (2 + #approvals transactions, see gas_per_issuance.csv)
takes seconds to minutes, which is negligible next to approval delays measured
in working days, and it is reported separately.

Model (all parameters are ASSUMPTIONS, chosen for illustration and varied in
the sensitivity runs; they are not measured NU data):
  * The 7 employees (2 Registrars, 3 Deans, 2 Exam Officers) each act on the
    request after an independent delay ~ LogNormal(median = 1 working day,
    sigma = 0.75), i.e. p95 of about 3.4 working days per person.
    The proposal itself is one of these actions.
  * Individual absence: each employee is independently unavailable for the
    whole issuance window with probability `absence` (leave, travel, illness).
  * Role outage: each role is, independently, entirely unavailable with
    probability `role_outage` (correlated absence, e.g. all exam officers busy
    during an exam period).
  * No governance intervention: absent approvers are not deactivated or
    replaced during the window (that would change N for Unanimous).
  * Issuance delay = the earliest time at which the approvals received so far
    satisfy the policy. If the present employees can never satisfy it, the
    issuance "cannot complete" and the cause is classified:
      fail_insufficient_count  fewer than m eligible employees present
      fail_missing_role        >= m present, but a required role is absent
                               (Single issuer: no Registrar present)
      fail_unanimity           Unanimous: at least one employee absent
  * Deadline: 5 working days.

Every scenario evaluates all policies on the *same* random draws (common
random numbers), seeded from common.SEED.

Output: data/availability_results.csv
"""

from __future__ import annotations

import csv

import numpy as np

from common import DATA, DEAN, EXAM, PRIMARY_THRESHOLD, REGISTRAR, SEED, STAFF

TRIALS = 20_000
DELAY_MEDIAN_DAYS = 1.0
DELAY_SIGMA = 0.75
DEADLINE_DAYS = 5.0
BASE_ABSENCE = 0.10
ABSENCE_GRID = (0.0, 0.05, 0.10, 0.15, 0.20, 0.30)
ROLE_OUTAGE_GRID = (0.0, 0.05, 0.10)
THRESHOLDS = (3, 4, 5)

ROLE_INDEX = {REGISTRAR: 0, DEAN: 1, EXAM: 2}
STAFF_ROLE = np.array([ROLE_INDEX[r] for r in STAFF])  # (7,)


def draw(rng: np.random.Generator, absence: float, role_outage: float) -> np.ndarray:
    """Delays in days, shape (TRIALS, 7); np.inf where the employee is unavailable."""
    delays = rng.lognormal(mean=np.log(DELAY_MEDIAN_DAYS), sigma=DELAY_SIGMA, size=(TRIALS, len(STAFF)))
    absent = rng.random((TRIALS, len(STAFF))) < absence
    role_down = rng.random((TRIALS, 3)) < role_outage  # per role
    absent |= role_down[:, STAFF_ROLE]
    delays[absent] = np.inf
    return delays


def evaluate(delays: np.ndarray, policy: str, m: int) -> dict:
    """Vectorised earliest-satisfaction time for one policy."""
    eligible = np.ones(len(STAFF), bool) if policy != "A_single" else STAFF_ROLE == 0
    d = np.where(eligible[None, :], delays, np.inf)
    order = np.argsort(d, axis=1)
    sorted_d = np.take_along_axis(d, order, axis=1)  # (T, 7)
    sorted_role = STAFF_ROLE[order]  # (T, 7)
    arrived = np.isfinite(sorted_d)

    # cumulative valid approvals per role after the j-th arrival: (T, 7, 3)
    one_hot = (sorted_role[..., None] == np.arange(3)) & arrived[..., None]
    cum = np.cumsum(one_hot, axis=1)
    total = cum.sum(axis=2)

    if policy == "A_single":
        ok = total >= 1
    elif policy == "B_unanimous":
        ok = total == len(STAFF)  # N = 7 active approvers; absentees remain active on-chain
    elif policy == "C_majority":
        ok = total >= m
    elif policy == "D_role":
        ok = (total >= m) & (cum >= 1).all(axis=2)
    else:
        raise ValueError(policy)
    ok &= arrived

    done = ok.any(axis=1)
    first = ok.argmax(axis=1)
    t = np.where(done, sorted_d[np.arange(len(d)), first], np.inf)

    # failure classification
    present = np.isfinite(d)
    present_total = present.sum(axis=1)
    present_roles = np.stack([(present & (STAFF_ROLE == r)).sum(axis=1) for r in range(3)], axis=1)
    fail = ~done
    if policy == "B_unanimous":
        f_count, f_role, f_unan = 0, 0, int(fail.sum())
    elif policy == "A_single":
        f_count, f_role, f_unan = 0, int(fail.sum()), 0  # no registrar available
    elif policy == "C_majority":
        f_count, f_role, f_unan = int(fail.sum()), 0, 0
    else:
        # "missing role" = enough people present (>= m) but a required role absent,
        # i.e. failures caused specifically by the role constraint.
        too_few = present_total < m
        f_count = int((fail & too_few).sum())
        f_role, f_unan = int((fail & ~too_few).sum()), 0
        assert not (fail & ~too_few & ~(present_roles == 0).any(axis=1)).any()

    completed = t[done]
    return {
        "completion_rate": done.mean(),
        "within_deadline_rate": (t <= DEADLINE_DAYS).mean(),
        "median_delay_days": float(np.median(completed)) if completed.size else float("nan"),
        "p95_delay_days": float(np.percentile(completed, 95)) if completed.size else float("nan"),
        "fail_insufficient_count": f_count / len(d),
        "fail_missing_role": f_role / len(d),
        "fail_unanimity": f_unan / len(d),
    }


def policy_set(m: int) -> list[tuple[str, str, int]]:
    """(csv key, evaluate() name, threshold)."""
    return [
        ("A_single", "A_single", 1),
        ("B_unanimous", "B_unanimous", 7),
        (f"C_majority_{m}of7", "C_majority", m),
        (f"D_role_{m}of7", "D_role", m),
    ]


def main() -> None:
    rows = []
    scenarios = [("absence_sweep", a, 0.0) for a in ABSENCE_GRID]
    scenarios += [("role_outage", BASE_ABSENCE, q) for q in ROLE_OUTAGE_GRID if q > 0]
    for idx, (name, absence, outage) in enumerate(scenarios):
        rng = np.random.default_rng([SEED, idx])
        delays = draw(rng, absence, outage)
        thresholds = THRESHOLDS if (name == "absence_sweep" and absence == BASE_ABSENCE) else (PRIMARY_THRESHOLD,)
        seen = set()
        for m in thresholds:
            for key, pol, thr in policy_set(m):
                if key in seen:
                    continue
                seen.add(key)
                r = evaluate(delays, pol, thr)
                rows.append([name, key, absence, outage, thr, TRIALS, *(round(v, 6) for v in r.values())])

    header = [
        "scenario",
        "policy",
        "absence_prob",
        "role_outage_prob",
        "threshold",
        "trials",
        "completion_rate",
        "within_deadline_rate",
        "median_delay_days",
        "p95_delay_days",
        "fail_insufficient_count",
        "fail_missing_role",
        "fail_unanimity",
    ]
    DATA.mkdir(exist_ok=True)
    with (DATA / "availability_results.csv").open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)

    print(f"wrote {len(rows)} rows -> data/availability_results.csv")
    print(f"\nbaseline (absence={BASE_ABSENCE}, no role outage, deadline={DEADLINE_DAYS} days):")
    for r in rows:
        if r[0] == "absence_sweep" and r[2] == BASE_ABSENCE and r[1].endswith(("single", "unanimous", "4of7")):
            print(f"  {r[1]:<18} complete {r[6]:6.1%}  on time {r[7]:6.1%}  median {r[8]:.2f}d  p95 {r[9]:.2f}d")


if __name__ == "__main__":
    main()
