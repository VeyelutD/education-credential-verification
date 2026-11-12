// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {IApprovalPolicy} from "../src/interfaces/IApprovalPolicy.sol";
import {Role} from "../src/Types.sol";
import {SingleIssuerPolicy} from "../src/policies/SingleIssuerPolicy.sol";
import {UnanimousPolicy} from "../src/policies/UnanimousPolicy.sol";
import {MajorityPolicy} from "../src/policies/MajorityPolicy.sol";
import {RoleConstrainedPolicy} from "../src/policies/RoleConstrainedPolicy.sol";

/// @notice Experiment B workload. Broadcasts a fixed sequence of real
///         transactions so gas can be read from Anvil receipts:
///         deployment, university/approver management, REPS complete issuances
///         (propose -> approvals -> finalize), one revocation.
/// @dev Driven by experiments/gas_benchmark.py. Env: POLICY (SINGLE | UNANIMOUS |
///      MAJORITY | ROLE_CONSTRAINED), REPS (default 10). Commitments are taken from
///      data/synthetic_credentials.json. Signers come from Anvil's public test mnemonic.
///      Approver sets per issuance are the minimal ones each policy needs; Majority and
///      Role-constrained use the *same* four signers (R1, D1, D2, E1).
contract GasBenchmark is Script {
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    uint256 internal governorKey;
    uint256[7] internal staff; // R1, R2, D1, D2, D3, E1, E2

    function run() external {
        string memory kind = vm.envString("POLICY");
        uint256 reps = vm.envOr("REPS", uint256(10));
        governorKey = vm.deriveKey(TEST_MNEMONIC, 0);
        for (uint32 i; i < 7; ++i) {
            staff[i] = vm.deriveKey(TEST_MNEMONIC, i + 1);
        }

        // --- deployment + management ---
        vm.startBroadcast(governorKey);
        IApprovalPolicy policy = _deployPolicy(kind);
        CredentialRegistry registry = new CredentialRegistry(policy, vm.addr(governorKey));
        uint32 nu = registry.registerUniversity("Nazarbayev University (synthetic)");
        Role[7] memory roles =
            [Role.Registrar, Role.Registrar, Role.Dean, Role.Dean, Role.Dean, Role.ExamOfficer, Role.ExamOfficer];
        for (uint256 i; i < 7; ++i) {
            registry.addApprover(nu, vm.addr(staff[i]), roles[i]);
        }
        vm.stopBroadcast();

        // --- issuances ---
        uint256[] memory signers = _signers(kind);
        string memory json = vm.readFile("data/synthetic_credentials.json");
        bytes32 first;
        for (uint256 rep; rep < reps; ++rep) {
            bytes32 c = vm.parseJsonBytes32(json, string.concat(".credentials[", vm.toString(rep), "].commitment"));
            if (rep == 0) first = c;
            _send(signers[0]);
            registry.propose(c);
            vm.stopBroadcast();
            for (uint256 j = 1; j < signers.length; ++j) {
                _send(signers[j]);
                registry.approve(c);
                vm.stopBroadcast();
            }
            _send(signers[0]);
            registry.finalize(c);
            vm.stopBroadcast();
        }

        // --- more management + revocation ---
        vm.startBroadcast(governorKey);
        registry.changeApproverRole(vm.addr(staff[4]), Role.ExamOfficer);
        registry.setApproverActive(vm.addr(staff[6]), false);
        registry.setApproverActive(vm.addr(staff[6]), true);
        vm.stopBroadcast();

        _send(1); // R2
        registry.revoke(first, "BENCHMARK");
        vm.stopBroadcast();
    }

    function _send(uint256 staffIndex) internal {
        vm.startBroadcast(staff[staffIndex]);
    }

    function _deployPolicy(string memory kind) internal returns (IApprovalPolicy) {
        bytes32 k = keccak256(bytes(kind));
        if (k == keccak256("SINGLE")) return new SingleIssuerPolicy();
        if (k == keccak256("UNANIMOUS")) return new UnanimousPolicy();
        if (k == keccak256("MAJORITY")) return new MajorityPolicy(4);
        if (k == keccak256("ROLE_CONSTRAINED")) return new RoleConstrainedPolicy(4, [uint256(0), 1, 1, 1]);
        revert(string.concat("Unknown POLICY: ", kind));
    }

    /// @dev Staff indices. First entry proposes and finalizes.
    function _signers(string memory kind) internal pure returns (uint256[] memory s) {
        bytes32 k = keccak256(bytes(kind));
        if (k == keccak256("SINGLE")) {
            s = new uint256[](1);
            s[0] = 0;
        } else if (k == keccak256("UNANIMOUS")) {
            s = new uint256[](7);
            for (uint256 i; i < 7; ++i) {
                s[i] = i;
            }
        } else {
            s = new uint256[](4);
            (s[0], s[1], s[2], s[3]) = (0, 2, 3, 5); // R1, D1, D2, E1
        }
    }
}
