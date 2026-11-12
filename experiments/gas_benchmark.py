"""Experiment B: gas consumption measured from real transaction receipts.

For each policy we start a fresh local Anvil node (hardfork pinned to the
compiler's EVM target), broadcast script/GasBenchmark.s.sol, and read
`gasUsed` from every receipt. Verification is a free read (eth_call); we
report its eth_estimateGas value for completeness, labelled as such.

Requires `forge`, `anvil` and `cast` on PATH (or in ~/.foundry/bin).

Outputs (data/):
    gas_raw.csv            one row per transaction
    gas_summary.csv        per policy and operation: n, median, min, max
    gas_per_issuance.csv   propose + approvals + finalize = total per credential
    gas_cost_eth.csv       total per issuance converted at ASSUMED gas prices
    gas_metadata.json      tool versions, settings, date
"""

from __future__ import annotations

import csv
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

from common import DATA, ROOT

POLICIES = {  # CSV key -> script POLICY value
    "A_single": "SINGLE",
    "B_unanimous": "UNANIMOUS",
    "C_majority_4of7": "MAJORITY",
    "D_role_4of7": "ROLE_CONSTRAINED",
}
REPS = 10
PORT = 8545
RPC = f"http://127.0.0.1:{PORT}"
HARDFORK = "cancun"  # matches evm_version in foundry.toml
# Gas prices are ASSUMPTIONS for illustration, not measurements. Edit as needed and cite a source.
ASSUMED_GAS_PRICES_GWEI = (0.5, 2, 10, 30)

OPERATION = {
    "propose(bytes32)": "propose",
    "approve(bytes32)": "approve",
    "finalize(bytes32)": "finalize",
    "revoke(bytes32,bytes32)": "revoke",
    "registerUniversity(string)": "register_university",
    "addApprover(uint32,address,uint8)": "add_approver",
    "changeApproverRole(address,uint8)": "change_role",
    "setApproverActive(address,bool)": "set_approver_active",
}


def tool(name: str) -> str:
    found = shutil.which(name) or shutil.which(str(Path.home() / ".foundry" / "bin" / name))
    if not found:
        sys.exit(f"'{name}' not found. Install Foundry (foundryup) and make sure it is on PATH.")
    return found


def run(cmd: list[str], **kw) -> str:
    res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)
    if res.returncode != 0:
        sys.exit(f"command failed: {' '.join(cmd)}\n{res.stdout}\n{res.stderr}")
    return res.stdout.strip()


def start_anvil() -> subprocess.Popen:
    proc = subprocess.Popen(
        [tool("anvil"), "--port", str(PORT), "--hardfork", HARDFORK, "--silent"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(50):
        if subprocess.run([tool("cast"), "block-number", "--rpc-url", RPC], capture_output=True).returncode == 0:
            return proc
        time.sleep(0.2)
    proc.kill()
    sys.exit("anvil did not start")


def classify(tx: dict) -> str:
    if tx.get("transactionType") == "CREATE":
        return "deploy_registry" if tx.get("contractName") == "CredentialRegistry" else "deploy_policy"
    return OPERATION.get(tx.get("function") or "", tx.get("function") or "unknown")


def benchmark(key: str, script_policy: str) -> tuple[list[list], int]:
    anvil = start_anvil()
    try:
        env = {**os.environ, "POLICY": script_policy, "REPS": str(REPS)}
        run([tool("forge"), "script", "script/GasBenchmark.s.sol", "--rpc-url", RPC, "--broadcast", "--slow"], env=env)
        log = json.loads((ROOT / "broadcast" / "GasBenchmark.s.sol" / "31337" / "run-latest.json").read_text())
        gas_by_hash = {r["transactionHash"]: int(r["gasUsed"], 16) for r in log["receipts"]}

        rows, rep, registry = [], -1, None
        for tx in log["transactions"]:
            op = classify(tx)
            if op == "deploy_registry":
                registry = tx["contractAddress"]
            if op == "propose":
                rep += 1
            rows.append([key, rep if op in ("propose", "approve", "finalize") else "", op, tx["hash"], gas_by_hash[tx["hash"]]])

        # Verification is a view call; report eth_estimateGas of verify() on an issued credential.
        creds = json.loads((DATA / "synthetic_credentials.json").read_text(encoding="utf-8"))["credentials"]
        c_valid = creds[1]["commitment"]  # credential 0 is revoked at the end of the workload
        verify_gas = int(run([tool("cast"), "estimate", registry, "verify(bytes32)", c_valid, "--rpc-url", RPC]))
        rows.append([key, "", "verify_view_estimate", "", verify_gas])
        return rows, verify_gas
    finally:
        anvil.kill()
        anvil.wait()


def main() -> None:
    run([tool("forge"), "build"])
    raw: list[list] = []
    for key, script_policy in POLICIES.items():
        print(f"benchmarking {key} ...")
        rows, _ = benchmark(key, script_policy)
        raw += rows

    _write("gas_raw.csv", ["policy", "issuance", "operation", "tx_hash", "gas_used"], raw)

    summary = []
    for key in POLICIES:
        ops = sorted({r[2] for r in raw if r[0] == key})
        for op in ops:
            vals = [r[4] for r in raw if r[0] == key and r[2] == op]
            summary.append([key, op, len(vals), int(statistics.median(vals)), min(vals), max(vals)])
    _write("gas_summary.csv", ["policy", "operation", "n", "median", "min", "max"], summary)

    per_issuance = []
    for key in POLICIES:
        for i in range(REPS):
            rs = [r for r in raw if r[0] == key and r[1] == i]
            prop = sum(r[4] for r in rs if r[2] == "propose")
            appr = [r[4] for r in rs if r[2] == "approve"]
            fin = sum(r[4] for r in rs if r[2] == "finalize")
            per_issuance.append([key, i, prop, len(appr), sum(appr), fin, prop + sum(appr) + fin, 2 + len(appr)])
    _write(
        "gas_per_issuance.csv",
        ["policy", "issuance", "propose", "approve_txs", "approve_total", "finalize", "total", "transactions"],
        per_issuance,
    )

    cost = []
    for key in POLICIES:
        total = statistics.median(r[6] for r in per_issuance if r[0] == key)
        for gwei in ASSUMED_GAS_PRICES_GWEI:
            cost.append([key, int(total), gwei, round(total * gwei * 1e-9, 8)])
    _write("gas_cost_eth.csv", ["policy", "median_total_gas", "assumed_gas_price_gwei", "eth_per_issuance"], cost)

    meta = {
        "date": date.today().isoformat(),
        "forge": run([tool("forge"), "--version"]).splitlines()[0],
        "anvil": run([tool("anvil"), "--version"]).splitlines()[0],
        "solc": "0.8.24",
        "optimizer_runs": 200,
        "evm_version / anvil hardfork": HARDFORK,
        "reps_per_policy": REPS,
        "network": "local Anvil (chain id 31337), fresh node per policy",
        "gas_prices_gwei_are_assumptions": list(ASSUMED_GAS_PRICES_GWEI),
    }
    (DATA / "gas_metadata.json").write_text(json.dumps(meta, indent=2) + "\n")

    print("\nmedian gas per completed issuance (propose + approvals + finalize):")
    for key in POLICIES:
        vals = [r[6] for r in per_issuance if r[0] == key]
        print(f"  {key:<18} {int(statistics.median(vals)):>9,}  ({per_issuance[[r[0] for r in per_issuance].index(key)][7]} txs)")


def _write(name: str, header: list[str], rows: list[list]) -> None:
    with (DATA / name).open("w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


if __name__ == "__main__":
    main()
