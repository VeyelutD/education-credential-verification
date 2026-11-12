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

from common import DATA, FIGURES, TABLES

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
    for ext in ("pdf", "png"):
        fig.savefig(FIGURES / f"{name}.{ext}")
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
    fig, ax = plt.subplots(figsize=(5.2, 3.2))
    offsets = {"A_single": 0.0, "B_unanimous": 0.0, "C_majority_4of7": 0.012, "D_role_4of7": -0.012}
    for key in PRIMARY:
        d = df[df.policy == key]
        line(ax, d.k, d.success_fraction + offsets[key], key)
    ax.set_xlabel("Coalition size k (compromised employees)")
    ax.set_ylabel("Coalition success fraction")
    ax.set_xticks(range(1, 8))
    ax.set_ylim(-0.04, 1.06)
    ax.set_title("Share of k-employee coalitions able to issue without honest approval", fontsize=9, loc="left")
    d4 = df[(df.policy == "D_role_4of7") & (df.k == 4)].iloc[0]
    ax.annotate(
        f"D at k=4: {d4.capable}/{d4.total} = {d4.success_fraction:.3f}\nC at k=4: 35/35 = 1.000",
        xy=(4, d4.success_fraction - 0.012),
        xytext=(4.6, 0.38),
        fontsize=8,
        color=INK_2,
        arrowprops={"arrowstyle": "-", "color": INK_2, "lw": 0.8},
    )
    ax.legend(loc="upper left", fontsize=8)
    ax.text(1, -0.24, "Lines for C and D are offset by ±0.012 where they coincide (k ≤ 3 and k ≥ 6).",
            transform=ax.transAxes, ha="right", fontsize=7, color=INK_2)
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
# Trade-off
# ---------------------------------------------------------------------------
def fig_tradeoff() -> None:
    coal = pd.read_csv(DATA / "coalition_results.csv")
    gas = pd.read_csv(DATA / "gas_per_issuance.csv").groupby("policy").total.median()
    av = _sweep()
    av = av[av.absence_prob == 0.10].set_index("policy")

    fig, ax = plt.subplots(figsize=(5.2, 3.2))
    for key in PRIMARY:
        label, color, marker = POLICY_STYLE[key]
        sec = coal[(coal.policy == key) & (coal.k == 4)].success_fraction.iloc[0]
        ax.scatter(gas[key], sec, s=70, color=color, marker=marker, edgecolors="white", linewidths=1.5, zorder=3)
        dy = {"C_majority_4of7": 0.06, "D_role_4of7": -0.10}.get(key, 0.06)
        ax.annotate(f"{label}\non time: {av.loc[key, 'within_deadline_rate']:.1%}",
                    (gas[key], sec), xytext=(8, dy * 100), textcoords="offset points", fontsize=7.5)
    ax.set_xlabel("Gas per completed issuance (median)")
    ax.set_ylabel("Success fraction of 4-employee coalitions\n(lower = more insider-resistant)")
    ax.set_ylim(-0.08, 1.15)
    ax.set_xlim(gas.min() * 0.7, gas.max() * 1.35)
    ax.xaxis.set_major_formatter(KGAS)
    ax.set_title("Security vs. cost; label shows on-time issuance at 10% absence", fontsize=9, loc="left")
    save(fig, "fig_tradeoff")


# ---------------------------------------------------------------------------
# LaTeX tables
# ---------------------------------------------------------------------------
def _tex(name: str, caption: str, label: str, header: list[str], rows: list[list[str]], align: str) -> None:
    TABLES.mkdir(parents=True, exist_ok=True)
    lines = [
        "% Generated by experiments/generate_figures.py -- do not edit by hand.",
        "\\begin{table}[t]", "\\centering", "\\small", f"\\caption{{{caption}}}", f"\\label{{{label}}}",
        f"\\begin{{tabular}}{{{align}}}", "\\hline", " & ".join(header) + " \\\\", "\\hline",
        *(" & ".join(r) + " \\\\" for r in rows), "\\hline", "\\end{tabular}", "\\end{table}", "",
    ]
    (TABLES / f"{name}.tex").write_text("\n".join(lines), encoding="utf-8")
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


def main() -> None:
    print("figures:")
    fig_coalition()
    fig_coalition_sensitivity()
    fig_gas()
    fig_delay()
    fig_availability()
    fig_tradeoff()
    print("tables:")
    tables()


if __name__ == "__main__":
    main()
