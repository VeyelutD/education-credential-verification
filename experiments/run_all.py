"""Reproduce every dataset, figure and table from a clean clone.

    python experiments/run_all.py            # everything (~2-3 minutes)
    python experiments/run_all.py --no-gas   # skip the Anvil gas benchmark

Steps:
  1. generate synthetic credentials            -> data/synthetic_credentials.json
  2. forge test (unit tests, hash parity, on-chain coalition export)
                                               -> data/coalition_onchain.csv
  3. Experiment A: coalition analysis          -> data/coalition_*.csv
  4. Experiment B: gas benchmark on Anvil      -> data/gas_*.csv
  5. Experiment C: availability simulation     -> data/availability_results.csv
  6. python tests (pytest)
  7. figures + LaTeX tables                    -> figures/, paper/tables/
"""

from __future__ import annotations

import argparse
import subprocess
import sys

from common import ROOT
from gas_benchmark import tool

PY = sys.executable


def step(title: str, cmd: list[str]) -> None:
    print(f"\n=== {title} ===", flush=True)
    if subprocess.run(cmd, cwd=ROOT).returncode != 0:
        sys.exit(f"step failed: {title}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-gas", action="store_true", help="skip the Anvil gas benchmark")
    args = ap.parse_args()

    step("1. synthetic credentials", [PY, "experiments/credentials.py"])
    step("2. forge test", [tool("forge"), "test"])
    step("3. Experiment A: coalitions", [PY, "experiments/coalition_analysis.py"])
    if not args.no_gas:
        step("4. Experiment B: gas", [PY, "experiments/gas_benchmark.py"])
    step("5. Experiment C: availability", [PY, "experiments/availability_simulation.py"])
    step("6. pytest", [PY, "-m", "pytest", "experiments/tests", "-q"])
    step("7. figures and tables", [PY, "experiments/generate_figures.py"])
    print("\nDone. Outputs: data/, figures/, paper/tables/")


if __name__ == "__main__":
    main()
