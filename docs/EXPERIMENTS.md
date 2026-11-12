# Experiments

Every number below is produced by `python experiments/run_all.py` and stored in
`data/`. Figures are in `figures/`, LaTeX tables in `paper/tables/`. Re-running
the pipeline regenerates all of them.

Common setup (`experiments/common.py`): one synthetic university with
2 Registrars, 3 Deans and 2 Exam Officers (N = 7). Seed `435` everywhere.

| Policy | Rule |
|---|---|
| A Single issuer | any one Registrar |
| B Unanimous | all 7 |
| C Threshold | 4 of 7, any roles (sensitivity: 3, 5) |
| D Role-constrained | 4 of 7 **and** ≥ 1 Registrar, ≥ 1 Dean, ≥ 1 Exam Officer (sensitivity: 3, 5) |

## A. Insider coalition resistance

**Method.** Enumerate all 127 non-empty coalitions. A coalition "can issue" if
its members alone satisfy the policy. Success fraction(k) = capable
k-coalitions / C(7, k).

**Validation.** `test/experiments/CoalitionExport.t.sol` runs every coalition
against the deployed contracts. `coalition_analysis.py` requires all 1,016
outcomes (8 policy variants × 127) to agree with the on-chain results.

**Not a probability.** The success fraction counts subsets. It is not a
probability of fraud. `coalition_probability.csv` adds one explicit model, in
which each employee is compromised independently with probability p. That
independence is an assumption, and it must be stated wherever the file is
used.

**Results** (`coalition_results.csv`, `coalition_summary.csv`):

| k | A | B | C 4-of-7 | D 4-of-7 |
|---|---|---|---|---|
| 1 | 0.286 | 0 | 0 | 0 |
| 3 | 0.714 | 0 | 0 | 0 |
| 4 | 0.857 | 0 | **1.000** | **0.686** (24/35) |
| 5 | 0.952 | 0 | 1.000 | 0.905 |
| 6–7 | 1 | 0 / 1 | 1 | 1 |

- Under the same threshold, role constraints **do not raise the minimum
  coalition size** (4 for both C and D).
- They cut the share of minimum-size coalitions that can forge (35/35 → 24/35
  at m = 4; 35/35 → 12/35 at m = 3). This is the measured security
  contribution of role separation.
- At m = 5 the effect almost disappears (21/21 → 19/21). With 5 of 7 people,
  nearly every coalition already covers all three roles.

## B. Gas

**Method.** `script/GasBenchmark.s.sol` broadcasts real transactions to a fresh
Anvil node per policy (hardfork `cancun`, the same as the compiler target).
`gas_benchmark.py` reads `gasUsed` from the receipts. The workload is:
deployment, adding 7 approvers, 10 complete issuances using each policy's
minimal approver set, role and status changes, and 1 revocation. C and D use
the **same** four signers (R1, D1, D2, E1). Verification is a free `eth_call`;
it is reported as an `eth_estimateGas` value. Tool versions and the date are
recorded in `gas_metadata.json`.

**Results** (median gas per completed issuance, `gas_per_issuance.csv`):

| | A | B | C | D |
|---|---|---|---|---|
| Total | 198,846 | 758,182 | 480,981 | 481,868 |
| Transactions | 2 | 8 | 5 | 5 |

- D costs **+887 gas (+0.18%)** per issuance over C. That is the cost of the
  role check in `finalize` (81,556 vs 80,669 gas).
- Total gas is driven by the *number of approvals* (~84.8k gas each), not by
  the policy logic.
- Deploying D's policy contract costs more (286,817 vs 170,266 gas). This is
  a one-off cost.
- `gas_cost_eth.csv` converts gas to ETH at **assumed** gas prices. These are
  illustrative, not measured fees.

## C. Availability and delay (simulation)

**This simulates human workflow time only.** Blockchain execution (2–8
transactions per issuance) is not included. It is measured separately in B
and takes seconds to minutes, compared with approval delays of working days.

**Assumptions** (`availability_simulation.py`; illustrative, not NU data):

| Parameter | Value |
|---|---|
| Per-employee action delay | LogNormal, median 1 working day, σ = 0.75 (individual p95 ≈ 3.4 days) |
| Individual absence for the whole window | p ∈ {0, 5, 10, 15, 20, 30}%, baseline 10% |
| Whole-role outage (correlated absence) | q ∈ {0, 5, 10}% per role, with 10% individual absence |
| Deadline | 5 working days |
| Trials | 20,000 per scenario, common random numbers across policies |
| Governance | absentees are not deactivated or replaced during the window |

**Results at 10% absence** (`availability_results.csv`):

| | Completes | On time | Median (days) | P95 (days) |
|---|---|---|---|---|
| A | 99.0% | 98.7% | 0.71 | 2.08 |
| B | 47.7% | 42.7% | 2.68 | 6.14 |
| C 4-of-7 | 99.6% | 99.5% | 1.10 | 2.22 |
| D 4-of-7 | 97.6% | 96.9% | 1.22 | 2.87 |

- D's extra failures come from the role constraint: enough people are
  present, but one role is missing (2.1% of trials at baseline).
- The gap grows with correlated absence. At a 5% role-outage probability,
  D completes 83.9% versus 96.8% for C. At 10%, it is 71.8% versus 93.0%.
- Unanimous is impractical under any absence (0.9⁷ ≈ 47.8% completion at 10%).
- The closed-form checks match the simulation: A = 1 − 0.1² = 99.0% and
  B = 0.9⁷ = 47.8%.

## Trade-off summary

At equal threshold (4 of 7), role-constrained approval reduces the share of
4-person coalitions that can forge from 100% to 68.6%. It costs 0.18% more gas,
but noticeably reduces availability when a whole role can be unavailable. It
does not raise the minimum number of insiders needed. These results are for
one 7-person configuration under the assumptions above.
