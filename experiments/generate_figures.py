"""Generate every figure and table used in the paper from data/*.csv.

Run after the three experiments (see experiments/run_all.py).
Figures -> figures/*.pdf and *.png ; LaTeX tables -> paper/tables/*.tex
"""

from __future__ import annotations

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
import pandas as pd

from itertools import combinations

from common import DATA, FIGURES, N_STAFF, STAFF, TABLES, can_issue, primary_policies, sensitivity_policies

# Categorical palette (validated: CVD + normal-vision separation pass on a light
# surface). Two slots are below 3:1 contrast, so every series is also identified
# by marker shape and a direct label / legend, never by colour alone.
POLICY_STYLE = {
    "A_single": ("A: Single issuer", "#2a78d6", "o"),
    "B_unanimous": ("B: Unanimous 7-of-7", "#eb6834", "s"),
    "C_majority_4of7": ("C: Threshold 4-of-7", "#1baf7a", "^"),
    "D_role_4of7": ("D: Role-constrained 4-of-7", "#eda100", "D"),
}
PRIMARY = list(POLICY_STYLE)
INK, INK_2, GRID = "#1f1f1e", "#5f5e58", "#e4e3de"
STEPS_BLUE = ("#86b6ef", "#2a78d6", "#184f95")  # ordered components (one-hue ramp)
KGAS = FuncFormatter(lambda v, _: f"{v / 1000:,.0f}k")

plt.rcParams.update(
    {
        "font.size": 9,
        "axes.edgecolor": INK_2,
        "axes.labelcolor": INK,
        "xtick.color": INK_2,
        "ytick.color": INK_2,
        "text.color": INK,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "axes.grid.axis": "y",
        "grid.color": GRID,
        "grid.linewidth": 0.8,
        "lines.linewidth": 2,
        "lines.markersize": 6,
        "legend.frameon": False,
        "savefig.bbox": "tight",
        "savefig.dpi": 200,
    }
)


def save(fig, name: str) -> None:
    FIGURES.mkdir(exist_ok=True)
    # No timestamps in the files, so re-running produces byte-identical figures.
    fig.savefig(FIGURES / f"{name}.pdf", metadata={"CreationDate": None, "ModDate": None})
    fig.savefig(FIGURES / f"{name}.png", metadata={"Software": None})
    plt.close(fig)
    print(f"  figures/{name}.pdf")


def line(ax, x, y, key, **kw):
    label, color, marker = POLICY_STYLE[key]
    ax.plot(x, y, color=color, marker=marker, label=label, markeredgecolor="white", markeredgewidth=0.8, **kw)


# ---------------------------------------------------------------------------
# Experiment A
# ---------------------------------------------------------------------------
def fig_coalition() -> None:
    df = pd.read_csv(DATA / "coalition_results.csv")
    fig, ax = plt.subplots(figsize=(5.2, 3.4))
    # True values, no offsets. Where lines coincide, larger hollow-edged markers
    # drawn first stay visible around the smaller ones.
    sizes = {"A_single": 6, "B_unanimous": 11, "C_majority_4of7": 8.5, "D_role_4of7": 5}
    for key in ("B_unanimous", "C_majority_4of7", "A_single", "D_role_4of7"):
        d = df[df.policy == key]
        line(ax, d.k, d.success_fraction, key, ms=sizes[key])
    ax.set_xlabel("Coalition size k (compromised employees)")
    ax.set_ylabel("Coalition success fraction")
    ax.set_xticks(range(1, 8))
    ax.set_ylim(-0.06, 1.08)
    handles, labels = ax.get_legend_handles_labels()
    order = sorted(range(len(labels)), key=lambda i: labels[i])
    fig.legend([handles[i] for i in order], [labels[i] for i in order],
               loc="upper center", bbox_to_anchor=(0.5, 0.0), ncol=2, fontsize=8)
    save(fig, "fig_coalition")


def fig_coalition_sensitivity() -> None:
    df = pd.read_csv(DATA / "coalition_results.csv")
    fig, axes = plt.subplots(1, 3, figsize=(7.0, 2.4), sharey=True)
    for ax, m in zip(axes, (3, 4, 5)):
        for key, (label, color, marker) in {
            f"C_majority_{m}of7": (f"C: {m}-of-7, any roles", "#1baf7a", "^"),
            f"D_role_{m}of7": (f"D: {m}-of-7, ≥1 per role", "#eda100", "D"),
        }.items():
            d = df[df.policy == key]
            ax.plot(d.k, d.success_fraction, color=color, marker=marker, label=label,
                    markeredgecolor="white", markeredgewidth=0.8)
        ax.set_title(f"Threshold m = {m}", fontsize=9)
        ax.set_xticks(range(1, 8))
        ax.set_xlabel("Coalition size k")
    axes[0].set_ylabel("Success fraction")
    handles = [plt.Line2D([], [], color="#1baf7a", marker="^", label="C: m-of-7, any roles"),
               plt.Line2D([], [], color="#eda100", marker="D", label="D: m-of-7, at least one per role")]
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(0.5, -0.17), ncol=2, fontsize=8)
    save(fig, "fig_coalition_sensitivity")


# ---------------------------------------------------------------------------
# Experiment B
# ---------------------------------------------------------------------------
def fig_gas() -> None:
    df = pd.read_csv(DATA / "gas_per_issuance.csv").groupby("policy").median(numeric_only=True).loc[PRIMARY]
    fig, ax = plt.subplots(figsize=(5.6, 2.6))
    ax.grid(axis="y", visible=False)
    ax.grid(axis="x", visible=True)
    y = range(len(PRIMARY))[::-1]
    left = [0] * len(PRIMARY)
    for part, color, label in zip(("propose", "approve_total", "finalize"), STEPS_BLUE,
                                  ("propose (incl. proposer approval)", "additional approvals", "finalize")):
        vals = df[part].tolist()
        ax.barh(list(y), vals, left=left, color=color, edgecolor="white", linewidth=2, height=0.6, label=label)
        left = [a + b for a, b in zip(left, vals)]
    for yi, total, txs in zip(y, df.total, df.transactions):
        ax.text(total + 8000, yi, f"{int(total):,} gas · {int(txs)} txs", va="center", fontsize=8)
    ax.set_yticks(list(y), [POLICY_STYLE[k][0] for k in PRIMARY])
    ax.set_xlabel("Gas per completed issuance (median of 10, Anvil receipts)")
    ax.set_xlim(0, max(left) * 1.32)
    ax.xaxis.set_major_formatter(KGAS)
    ax.legend(fontsize=7, loc="lower left", bbox_to_anchor=(0, 1.0), ncol=3)
    save(fig, "fig_gas")


# ---------------------------------------------------------------------------
# Experiment C
# ---------------------------------------------------------------------------
def _sweep() -> pd.DataFrame:
    df = pd.read_csv(DATA / "availability_results.csv")
    return df[(df.scenario == "absence_sweep") & df.policy.isin(PRIMARY)]


def fig_delay() -> None:
    df = _sweep()
    fig, axes = plt.subplots(1, 2, figsize=(7.0, 2.6), sharey=True)
    for ax, col, title in zip(axes, ("median_delay_days", "p95_delay_days"),
                              ("Median issuance delay", "95th-percentile issuance delay")):
        for key in PRIMARY:
            d = df[df.policy == key]
            line(ax, d.absence_prob * 100, d[col], key)
        ax.set_title(title + " (completed issuances)", fontsize=9, loc="left")
        ax.set_xlabel("Per-employee absence probability (%)")
    axes[0].set_ylabel("Working days")
    axes[1].legend(fontsize=7, loc="upper left", bbox_to_anchor=(0, 0.92))
    save(fig, "fig_delay")


def fig_availability() -> None:
    df = pd.read_csv(DATA / "availability_results.csv")
    sweep = _sweep()
    fig, axes = plt.subplots(1, 2, figsize=(7.0, 2.7), sharey=True)
    for key in PRIMARY:
        d = sweep[sweep.policy == key]
        line(axes[0], d.absence_prob * 100, d.within_deadline_rate * 100, key)
    axes[0].set_title("Issued within 5 working days", fontsize=9, loc="left")
    axes[0].set_xlabel("Per-employee absence probability (%)")
    axes[0].set_ylabel("Credentials (%)")

    base = df[(df.scenario == "absence_sweep") & (df.absence_prob == 0.10)]
    outage = pd.concat([base, df[df.scenario == "role_outage"]])
    for key in PRIMARY:
        d = outage[outage.policy == key].sort_values("role_outage_prob")
        line(axes[1], d.role_outage_prob * 100, d.completion_rate * 100, key)
    axes[1].set_title("Can complete at all (10% individual absence)", fontsize=9, loc="left")
    axes[1].set_xlabel("Whole-role outage probability (%)")
    axes[1].set_xticks([0, 5, 10])
    fig.legend(*axes[0].get_legend_handles_labels(), loc="lower center", bbox_to_anchor=(0.5, -0.17), ncol=4, fontsize=8)
    save(fig, "fig_availability")


# ---------------------------------------------------------------------------
# Configurations and correlation (experiments D and E)
# ---------------------------------------------------------------------------
def fig_ks() -> None:
    """k (insiders needed) against s (absences tolerated), primary university."""
    d = _ks_rows()
    fig, ax = plt.subplots(figsize=(5.2, 3.3))
    ax.plot([0, 7], [7, 0], color=GRID, linewidth=1.5, zorder=1)
    ax.text(6.25, 0.95, "k + s = 7", color=INK_2, fontsize=8)
    for label, k, sv, frac in d:
        letter = label[0]
        key = {"A": "A_single", "B": "B_unanimous", "C": "C_majority_4of7", "D": "D_role_4of7"}[letter]
        _, color, marker = POLICY_STYLE[key]
        ax.scatter(k, sv, s=75, color=color, marker=marker, edgecolors="white", linewidths=1.2, zorder=3)
        text = label.split(":")[0]
        if letter in "CD":
            text += f" {label.split()[-1]}\n{frac:.0%}" + (" capable" if letter == "C" else "")
        if letter == "D":  # centred below, clear of the neighbouring markers
            ax.annotate(text, (k, sv), xytext=(0, -9), textcoords="offset points", fontsize=7.5,
                        ha="center", va="top")
        else:
            ax.annotate(text, (k, sv), xytext=(8, 4), textcoords="offset points", fontsize=7.5)
    ax.set_xlabel("k: smallest coalition able to issue")
    ax.set_ylabel("s: absences always tolerated")
    ax.set_xlim(0.5, 8.2)
    ax.set_ylim(-0.4, 4.9)
    ax.set_xticks(range(1, 8))
    ax.grid(axis="x", visible=True)
    save(fig, "fig_ks")


def fig_correlation() -> None:
    df = pd.read_csv(DATA / "correlation_results.csv")
    df = df[(df.staffing == "2-3-2") & (df.gamma == 0.0)]
    fig, axes = plt.subplots(1, 2, figsize=(7.0, 2.7))
    d = df[df.p == 0.10]
    axes[0].plot(d.rho, d.fraud_C, color="#1baf7a", marker="^", label="C: 4-of-7, any roles")
    axes[0].plot(d.rho, d.fraud_D, color="#eda100", marker="D", label="D: 4-of-7, one per role")
    axes[0].set_yscale("log")
    axes[0].set_title("P(compromised set can issue), p = 0.1", fontsize=9, loc="left")
    axes[0].set_ylabel("Probability (log scale)")
    axes[0].legend(fontsize=7, loc="center right", bbox_to_anchor=(1.0, 0.6))
    for pv, color, marker in ((0.05, STEPS_BLUE[0], "o"), (0.10, STEPS_BLUE[1], "s"), (0.20, STEPS_BLUE[2], "^")):
        d = df[df.p == pv]
        axes[1].plot(d.rho, d.break_even, color=color, marker=marker, label=f"p = {pv:.2f}")
    axes[1].set_yscale("log")
    axes[1].set_title("Break-even weight of a capable set", fontsize=9, loc="left")
    axes[1].legend(fontsize=7, loc="upper right")
    for ax in axes:
        ax.set_xlabel("Within-office correlation \u03c1")
    fig.tight_layout()
    save(fig, "fig_correlation")


def _ks_rows() -> list[tuple[str, int, int, float]]:
    summ = pd.read_csv(DATA / "coalition_summary.csv").set_index("policy")
    pols = {q.key: q for q in primary_policies() + sensitivity_policies()}
    rows = []
    for key, pol in pols.items():
        sv = -1
        for size in range(N_STAFF + 1):
            if all(can_issue(pol, [STAFF[i] for i in range(N_STAFF) if i not in a])
                   for a in combinations(range(N_STAFF), size)):
                sv = size
            else:
                break
        r = summ.loc[key]
        rows.append((pol.label, int(r.min_coalition_size), sv, float(r.success_fraction_at_min_size)))
    return rows


# ---------------------------------------------------------------------------
# LaTeX tables
# ---------------------------------------------------------------------------
def _tex(name: str, caption: str, label: str, header: list[str], rows: list[list[str]], align: str) -> None:
    TABLES.mkdir(parents=True, exist_ok=True)
    lines = [
        "% Generated by experiments/generate_figures.py -- do not edit by hand.",
        # table* spans both IEEE columns; these tables are too wide for one column.
        "\\begin{table*}[t]", "\\centering", "\\small", f"\\caption{{{caption}}}", f"\\label{{{label}}}",
        f"\\begin{{tabular}}{{{align}}}", "\\hline", " & ".join(header) + " \\\\", "\\hline",
        *(" & ".join(r) + " \\\\" for r in rows), "\\hline", "\\end{tabular}", "\\end{table*}", "",
    ]
    (TABLES / f"{name}.tex").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"  paper/tables/{name}.tex")


def tables() -> None:
    coal = pd.read_csv(DATA / "coalition_results.csv")
    rows = []
    for k in range(1, 8):
        r = [str(k)]
        for key in PRIMARY:
            d = coal[(coal.policy == key) & (coal.k == k)].iloc[0]
            r.append(f"{d.capable}/{d.total} ({d.success_fraction:.3f})")
        rows.append(r)
    _tex("table_coalition", "Coalitions of $k$ employees able to issue, per policy (2 Registrars, 3 Deans, 2 Exam Officers).",
         "tab:coalition", ["$k$", "A", "B", "C (4-of-7)", "D (4-of-7, roles)"], rows, "c" + "r" * 4)

    summ = pd.read_csv(DATA / "gas_summary.csv")
    per = pd.read_csv(DATA / "gas_per_issuance.csv").groupby("policy").median(numeric_only=True)
    ops = [("deploy_policy", "Deploy policy"), ("deploy_registry", "Deploy registry"),
           ("add_approver", "Add approver"), ("change_role", "Change role"),
           ("set_approver_active", "(De)activate approver"), ("propose", "Propose"),
           ("approve", "Approve (each)"), ("finalize", "Finalize"), ("revoke", "Revoke"),
           ("verify_view_estimate", "Verify (eth\\_call estimate)")]
    rows = []
    for op, name in ops:
        r = [name]
        for key in PRIMARY:
            v = summ[(summ.policy == key) & (summ.operation == op)]
            r.append(f"{int(v['median'].iloc[0]):,}" if len(v) else "--")
        rows.append(r)
    rows.append(["\\textbf{Total per issuance}"] + [f"\\textbf{{{int(per.loc[k, 'total']):,}}}" for k in PRIMARY])
    rows.append(["Transactions per issuance"] + [str(int(per.loc[k, "transactions"])) for k in PRIMARY])
    _tex("table_gas", "Median gas from Anvil transaction receipts (10 issuances per policy).", "tab:gas",
         ["Operation", "A", "B", "C", "D"], rows, "l" + "r" * 4)

    av = _sweep()
    av = av[av.absence_prob == 0.10].set_index("policy")
    rows = []
    for key in PRIMARY:
        r = av.loc[key]
        fail = r.fail_insufficient_count + r.fail_missing_role + r.fail_unanimity
        rows.append([POLICY_STYLE[key][0], f"{r.completion_rate:.1%}", f"{r.within_deadline_rate:.1%}",
                     f"{r.median_delay_days:.2f}", f"{r.p95_delay_days:.2f}", f"{fail:.1%}",
                     f"{r.fail_missing_role:.1%}"])
    rows = [[c.replace("%", "\\%") for c in r] for r in rows]
    _tex("table_availability",
         "Simulated workflow at 10\\% individual absence (20{,}000 trials, seed 435, deadline 5 working days). "
         "Delays in working days over completed issuances.",
         "tab:availability", ["Policy", "Completes", "On time", "Median", "P95", "Cannot complete", "of which: role"],
         rows, "l" + "r" * 6)


def table_ks() -> None:
    """(k, s) per policy: k = smallest capable coalition, s = absences always tolerated."""
    summ = pd.read_csv(DATA / "coalition_summary.csv").set_index("label").smallest_capable_coalitions
    rows = [[lab, str(k), str(sv), f"{summ[lab] if not hasattr(summ[lab], 'iloc') else summ[lab].iloc[0]} ({fr:.3f})"]
            for lab, k, sv, fr in _ks_rows()]
    _tex("table_ks", "Smallest capable coalition $k$, absences always tolerated $s$, and number (fraction) of "
         "capable coalitions of size $k$.", "tab:ks", ["Policy", "$k$", "$s$", "Capable at $k$"], rows, "lccr")
    f = TABLES / "table_ks.tex"
    f.write_text(f.read_text(encoding="utf-8").replace("table*", "table"), encoding="utf-8", newline="\n")


def table_config() -> None:
    df = pd.read_csv(DATA / "configuration_results.csv")
    rows = []
    for r in df.itertuples():
        rows.append([f"{r.staffing}", str(r.threshold), r.policy, str(r.k), str(r.s),
                     f"{r.capable_at_k:,}/{r.total_at_k:,} ({r.fraction_at_k:.3f})".replace(",", "{,}"),
                     f"{r.complete_absence10 * 100:.2f}\\%", f"{r.complete_absence10_outage5 * 100:.2f}\\%"])
    _tex("table_config", "University configurations (registrars-deans-examination officers). Completion is exact, at "
         "10\\% individual absence, without and with a 5\\% whole-role outage.", "tab:config",
         ["Staffing", "Threshold", "Policy", "$k$", "$s$", "Capable at $k$", "Completes", "with outage"],
         rows, "lcccc" + "rrr")


def macros() -> None:
    """Write paper/tables/results_macros.tex: every result quoted in the paper text
    as a LaTeX macro, so no number is ever typed by hand."""
    coal = pd.read_csv(DATA / "coalition_results.csv").set_index(["policy", "k"])
    per = pd.read_csv(DATA / "gas_per_issuance.csv").groupby("policy").median(numeric_only=True)
    summ = pd.read_csv(DATA / "gas_summary.csv").set_index(["policy", "operation"])["median"]
    av = pd.read_csv(DATA / "availability_results.csv")
    base = av[(av.scenario == "absence_sweep") & (av.absence_prob == 0.10)].set_index("policy")
    out5 = av[(av.scenario == "role_outage") & (av.role_outage_prob == 0.05)].set_index("policy")
    out10 = av[(av.scenario == "role_outage") & (av.role_outage_prob == 0.10)].set_index("policy")

    def frac(policy: str, k: int) -> str:
        r = coal.loc[(policy, k)]
        return f"{r.capable}/{r.total}"

    def pct(x: float) -> str:
        return f"{x * 100:.1f}\\%"

    def gas(x: float) -> str:
        return f"{int(x):,}".replace(",", "{,}")

    letters = {"A_single": "A", "B_unanimous": "B", "C_majority_4of7": "C", "D_role_4of7": "D"}
    overhead = per.loc["D_role_4of7", "total"] - per.loc["C_majority_4of7", "total"]
    m = {
        "Seed": "435",
        "Trials": "20{,}000",
        "CoalAkOne": frac("A_single", 1),
        "CoalCkFour": frac("C_majority_4of7", 4),
        "CoalDkFour": frac("D_role_4of7", 4),
        "CoalDkFourFrac": f"{coal.loc[('D_role_4of7', 4)].success_fraction:.3f}",
        "CoalDkFive": frac("D_role_4of7", 5),
        "CoalCthreekThree": frac("C_majority_3of7", 3),
        "CoalDthreekThree": frac("D_role_3of7", 3),
        "CoalCfivekFive": frac("C_majority_5of7", 5),
        "CoalDfivekFive": frac("D_role_5of7", 5),
        "GasApproveEach": gas(summ.loc[("D_role_4of7", "approve")]),
        "GasFinalizeC": gas(summ.loc[("C_majority_4of7", "finalize")]),
        "GasFinalizeD": gas(summ.loc[("D_role_4of7", "finalize")]),
        "GasRoleOverhead": gas(overhead),
        "GasRoleOverheadPct": f"{overhead / per.loc['C_majority_4of7', 'total'] * 100:.2f}\\%",
        "GasDeployRegistry": gas(summ.loc[("D_role_4of7", "deploy_registry")]),
        "MissingRoleD": pct(base.loc["D_role_4of7", "fail_missing_role"]),
    }
    for key, L in letters.items():
        m[f"GasTotal{L}"] = gas(per.loc[key, "total"])
        m[f"Txs{L}"] = str(int(per.loc[key, "transactions"]))
        m[f"Complete{L}"] = pct(base.loc[key, "completion_rate"])
        m[f"OnTime{L}"] = pct(base.loc[key, "within_deadline_rate"])
        m[f"MedianDelay{L}"] = f"{base.loc[key, 'median_delay_days']:.2f}"
        m[f"PninetyfiveDelay{L}"] = f"{base.loc[key, 'p95_delay_days']:.2f}"
        m[f"OutageFive{L}"] = pct(out5.loc[key, "completion_rate"])
        m[f"OutageTen{L}"] = pct(out10.loc[key, "completion_rate"])

    # Smallest set of absent employees that makes issuance impossible (dual of the
    # minimum coalition). Approvers stay registered, so Unanimous still needs all 7.
    for pol in primary_policies():
        for size in range(1, N_STAFF + 1):
            blocking = sum(
                not can_issue(pol, [STAFF[i] for i in range(N_STAFF) if i not in absent])
                for absent in combinations(range(N_STAFF), size)
            )
            if blocking:
                m[f"Block{letters[pol.key]}"] = str(size)
                m[f"BlockSets{letters[pol.key]}"] = str(blocking)
                break

    # P(issue) under the i.i.d. compromise ASSUMPTION.
    prob = pd.read_csv(DATA / "coalition_probability.csv").set_index(["policy", "p_compromise"]).p_issue
    for key, L in letters.items():
        m[f"ProbTen{L}"] = f"{prob.loc[(key, 0.1)]:.4f}"
        m[f"ProbThirty{L}"] = f"{prob.loc[(key, 0.3)]:.4f}"

    # Published numbers: Lone & Naaz (2020), Table 4.1 (sign, addCert).
    sign, add = 87_708, 182_043
    m["LoneSign"], m["LoneAdd"] = gas(sign), gas(add)
    m["LoneSeven"] = gas(7 * sign + add)
    m["RatioBA"] = f"{per.loc['B_unanimous', 'total'] / per.loc['A_single', 'total']:.1f}"
    for L, key in (("C", "C_majority_4of7"), ("D", "D_role_4of7")):
        m[f"DeployPolicy{L}"] = gas(summ.loc[(key, "deploy_policy")])
    for name, gwei in (("EthLowD", 0.5), ("EthHighD", 30)):  # ASSUMED gas prices
        m[name] = f"{per.loc['D_role_4of7', 'total'] * gwei * 1e-9:.5f}"
    m["GasRevoke"] = gas(summ.loc[("D_role_4of7", "revoke")])
    m["GasPropose"] = gas(summ.loc[("D_role_4of7", "propose")])
    m["GasAddApprover"] = gas(summ.loc[("D_role_4of7", "add_approver")])

    cor = pd.read_csv(DATA / "correlation_results.csv")
    cor = cor[(cor.staffing == "2-3-2") & (cor.gamma == 0.0) & (cor.p == 0.10)].set_index("rho")
    for name, rho in (("Zero", 0.0), ("Half", 0.5), ("One", 1.0)):
        r = cor.loc[rho]
        m[f"CorC{name}"], m[f"CorD{name}"] = f"{r.fraud_C:.4f}", f"{r.fraud_D:.4f}"
        m[f"CorRed{name}"] = f"{r.relative_reduction * 100:.0f}\\%"
        m[f"CorBreak{name}"] = f"{r.break_even:.1f}"
    cor = pd.read_csv(DATA / "correlation_results.csv")
    cor = cor[(cor.staffing == "2-3-2") & (cor.gamma == 0.02) & (cor.p == 0.10)].set_index("rho")
    m["CorRedOneGamma"] = f"{cor.loc[1.0].relative_reduction * 100:.0f}\\%"

    cor = pd.read_csv(DATA / "correlation_results.csv")
    cor = cor[(cor.staffing == "2-3-2") & (cor.gamma == 0.0)]
    for name, pv in (("Five", 0.05), ("Ten", 0.10), ("Twenty", 0.20)):
        d = cor[cor.p == pv].set_index("rho")
        for rn, rho in (("Zero", 0.0), ("Half", 0.5), ("One", 1.0)):
            w = d.loc[rho].break_even
            m[f"Break{name}{rn}"] = gas(round(w)) if w >= 100 else f"{w:.1f}"
        m[f"Peak{name}"] = f"{d.fraud_D.idxmax():.1f}"
        m[f"PeakVal{name}"] = f"{d.fraud_D.max():.4f}"

    cfg = pd.read_csv(DATA / "configuration_results.csv").set_index(["staffing", "threshold", "policy"])
    m["CfgPrimD"] = f"{cfg.loc[('2-3-2', 4, 'D')].complete_absence10 * 100:.2f}\\%"
    r = cfg.loc[("3-3-3", 4, "D")]
    m["CfgDelegD"] = f"{r.complete_absence10 * 100:.2f}\\%"
    m["CfgDelegFrac"], m["CfgDelegCount"] = f"{r.fraction_at_k:.3f}", str(int(r.capable_at_k))
    m["CfgPrimCount"] = str(int(cfg.loc[("2-3-2", 4, "D")].capable_at_k))
    big = cfg[(cfg.note == "majority")].xs("D", level="policy").fraction_at_k
    m["CfgFracMin"], m["CfgFracMax"] = f"{big.min():.3f}", f"{big.max():.3f}"
    m["OutageBound"] = f"{(1 - 0.05) ** 3 * 100:.1f}\\%"
    m["BlockCoalExcluded"] = str(int(coal.loc[("C_majority_4of7", 4)].capable - coal.loc[("D_role_4of7", 4)].capable))
    m["ExactB"] = f"{0.9 ** 7 * 100:.1f}\\%"
    m["ExactA"] = f"{(1 - 0.1 ** 2) * 100:.1f}\\%"

    lines = ["% Generated by experiments/generate_figures.py -- do not edit by hand."]
    lines += [f"\\newcommand{{\\{k}}}{{{v}}}" for k, v in m.items()]
    TABLES.mkdir(parents=True, exist_ok=True)
    (TABLES / "results_macros.tex").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"  paper/tables/results_macros.tex ({len(m)} macros)")


def main() -> None:
    print("figures:")
    fig_coalition()
    fig_coalition_sensitivity()
    fig_gas()
    fig_delay()
    fig_availability()
    fig_ks()
    fig_correlation()
    print("tables:")
    tables()
    table_ks()
    table_config()
    macros()


if __name__ == "__main__":
    main()
