// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {RoleConstrainedPolicy} from "../src/policies/RoleConstrainedPolicy.sol";
import {Role} from "../src/Types.sol";

/// @notice End-to-end demonstration on a local chain:
///   deploy -> register synthetic NU + 7 employees -> propose diploma ->
///   approvals -> finalize -> employer verifies -> tampering detected ->
///   revocation changes the verification result.
/// @dev Uses Anvil's public *test* mnemonic to derive 9 distinct signers.
///   Dry run (no node needed):  forge script script/Demo.s.sol -vv
///   Against Anvil:             anvil   (in another terminal), then
///                              forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vv
contract Demo is Script {
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    // Synthetic credential, canonical JSON (sorted keys, no whitespace).
    string internal constant DIPLOMA =
        '{"credentialType":"BachelorDiploma","degree":"BSc Computer Science","graduationDate":"2026-06-15","honours":"Cum Laude","issuer":"NU-SYNTHETIC","studentId":"S-000001","studentName":"Aigerim Synthetic"}';
    string internal constant DIPLOMA_TAMPERED =
        '{"credentialType":"BachelorDiploma","degree":"BSc Computer Science","graduationDate":"2026-06-15","honours":"Summa Cum Laude","issuer":"NU-SYNTHETIC","studentId":"S-000001","studentName":"Aigerim Synthetic"}';

    uint256 internal governorKey;
    uint256[7] internal staffKeys; // r1, r2, d1, d2, d3, e1, e2
    CredentialRegistry internal registry;

    function run() external {
        governorKey = vm.deriveKey(TEST_MNEMONIC, 0);
        for (uint32 i; i < 7; ++i) {
            staffKeys[i] = vm.deriveKey(TEST_MNEMONIC, i + 1);
        }
        address governor = vm.addr(governorKey);
        bytes32 salt = keccak256(abi.encodePacked("demo-salt-", block.chainid)); // real use: 32 random bytes

        // 1. Governance setup.
        vm.startBroadcast(governorKey);
        RoleConstrainedPolicy policy = new RoleConstrainedPolicy(4, [uint256(0), 1, 1, 1]);
        registry = new CredentialRegistry(policy, governor);
        uint32 nu = registry.registerUniversity("Nazarbayev University (synthetic)");
        Role[7] memory roles =
            [Role.Registrar, Role.Registrar, Role.Dean, Role.Dean, Role.Dean, Role.ExamOfficer, Role.ExamOfficer];
        for (uint256 i; i < 7; ++i) {
            registry.addApprover(nu, vm.addr(staffKeys[i]), roles[i]);
        }
        vm.stopBroadcast();
        console2.log("1. Registry deployed at", address(registry));
        console2.log("   Policy: ROLE_CONSTRAINED 4-of-7, >=1 Registrar, Dean, Exam Officer");

        // 2. Registrar proposes the diploma commitment.
        bytes32 docHash = keccak256(bytes(DIPLOMA));
        bytes32 commitment = registry.computeCommitment(docHash, salt);
        _as(0);
        registry.propose(commitment);
        vm.stopBroadcast();
        console2.log("2. Registrar proposed commitment:");
        console2.logBytes32(commitment);
        _log("   status after proposal", commitment);

        // 3. Dean, Dean, Exam Officer approve.
        uint8[3] memory approvers = [2, 3, 5];
        for (uint256 i; i < 3; ++i) {
            _as(approvers[i]);
            registry.approve(commitment);
            vm.stopBroadcast();
        }
        (,uint256 total,, bool ok) = registry.tally(commitment);
        console2.log("3. Valid approvals:", total, "policy satisfied:", ok);

        // 4. Finalize.
        _as(0);
        registry.finalize(commitment);
        vm.stopBroadcast();
        _log("4. Issued; status", commitment);

        // 5-6. Employer verifies the disclosed document + salt.
        CredentialRegistry.VerificationResult memory v = registry.verifyDocument(docHash, salt);
        console2.log("5. Employer check: status", _name(v.status), "issuer universityId", uint256(v.universityId));
        console2.log("   issuer name:", registry.getUniversity(v.universityId).name);

        // 7. Tampered diploma.
        v = registry.verifyDocument(keccak256(bytes(DIPLOMA_TAMPERED)), salt);
        console2.log("7. Tampered diploma ('Summa Cum Laude'): status", _name(v.status));

        // 8. Revocation.
        _as(1);
        registry.revoke(commitment, "DEMO_REVOCATION");
        vm.stopBroadcast();
        v = registry.verifyDocument(docHash, salt);
        console2.log("8. After revocation: status", _name(v.status));
    }

    function _as(uint256 staffIndex) internal {
        vm.startBroadcast(staffKeys[staffIndex]);
    }

    function _log(string memory label, bytes32 c) internal view {
        console2.log(label, _name(registry.verify(c).status));
    }

    function _name(CredentialRegistry.VerificationStatus s) internal pure returns (string memory) {
        if (s == CredentialRegistry.VerificationStatus.Valid) return "VALID";
        if (s == CredentialRegistry.VerificationStatus.Pending) return "PENDING";
        if (s == CredentialRegistry.VerificationStatus.Revoked) return "REVOKED";
        return "NOT_FOUND";
    }
}
