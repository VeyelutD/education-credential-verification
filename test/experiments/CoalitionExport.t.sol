// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CredentialFixture} from "../utils/CredentialFixture.sol";
import {IApprovalPolicy} from "../../src/interfaces/IApprovalPolicy.sol";
import {Role} from "../../src/Types.sol";
import {MajorityPolicy} from "../../src/policies/MajorityPolicy.sol";
import {RoleConstrainedPolicy} from "../../src/policies/RoleConstrainedPolicy.sol";

/// @notice Experiment A, on-chain half: every non-empty coalition of the 7
///         employees attempts a fraudulent issuance against the real contracts,
///         for each policy (incl. 3/4/5-of-7 sensitivity variants). Outcomes are
///         written to data/coalition_onchain.csv; experiments/coalition_analysis.py
///         checks its combinatorial results against this file.
contract CoalitionExportTest is CredentialFixture {
    string internal constant OUT = "data/coalition_onchain.csv";
    Role[7] internal roles =
        [Role.Registrar, Role.Registrar, Role.Dean, Role.Dean, Role.Dean, Role.ExamOfficer, Role.ExamOfficer];

    function test_ExportCoalitionOutcomes() public {
        if (vm.exists(OUT)) vm.removeFile(OUT);
        vm.writeLine(OUT, "policy,mask,size,can_issue");

        _run("A_single", _single(), true);
        _run("B_unanimous", _unanimous(), false);
        for (uint256 m = 3; m <= 5; ++m) {
            _run(string.concat("C_majority_", vm.toString(m), "of7"), new MajorityPolicy(m), false);
            _run(
                string.concat("D_role_", vm.toString(m), "of7"),
                new RoleConstrainedPolicy(m, [uint256(0), 1, 1, 1]),
                false
            );
        }
    }

    function _run(string memory key, IApprovalPolicy policy, bool registrarOnly) internal {
        _deploy(policy);
        address[] memory members = _allSeven();
        for (uint256 mask = 1; mask < (uint256(1) << 7); ++mask) {
            bytes32 c = keccak256(abi.encode(key, mask));
            (bool ok, uint256 size) = _attempt(c, mask, members, registrarOnly);
            vm.writeLine(
                OUT, string.concat(key, ",", vm.toString(mask), ",", vm.toString(size), ",", ok ? "1" : "0")
            );
        }
    }

    function _attempt(bytes32 c, uint256 mask, address[] memory members, bool registrarOnly)
        internal
        returns (bool ok, uint256 size)
    {
        address proposer;
        for (uint256 i; i < 7; ++i) {
            if (mask & (uint256(1) << i) == 0) continue;
            ++size;
            if (registrarOnly && roles[i] != Role.Registrar) continue; // no authority under policy A
            vm.prank(members[i]);
            if (proposer == address(0)) {
                proposer = members[i];
                registry.propose(c);
            } else {
                registry.approve(c);
            }
        }
        if (proposer == address(0)) return (false, size);
        vm.prank(proposer);
        try registry.finalize(c) {
            ok = true;
        } catch {
            ok = false;
        }
    }
}
