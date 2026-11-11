// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CredentialRegistry} from "../../src/CredentialRegistry.sol";
import {IApprovalPolicy} from "../../src/interfaces/IApprovalPolicy.sol";
import {Role} from "../../src/Types.sol";
import {SingleIssuerPolicy} from "../../src/policies/SingleIssuerPolicy.sol";
import {UnanimousPolicy} from "../../src/policies/UnanimousPolicy.sol";
import {MajorityPolicy} from "../../src/policies/MajorityPolicy.sol";
import {RoleConstrainedPolicy} from "../../src/policies/RoleConstrainedPolicy.sol";

/// @notice Shared setup: one synthetic university with the primary
///         experiment configuration (2 Registrars, 3 Deans, 2 Exam Officers).
abstract contract CredentialFixture is Test {
    CredentialRegistry internal registry;

    address internal governor = makeAddr("governor");
    address internal outsider = makeAddr("outsider");
    address internal employer = makeAddr("employer");

    address internal r1 = makeAddr("registrar1");
    address internal r2 = makeAddr("registrar2");
    address internal d1 = makeAddr("dean1");
    address internal d2 = makeAddr("dean2");
    address internal d3 = makeAddr("dean3");
    address internal e1 = makeAddr("examOfficer1");
    address internal e2 = makeAddr("examOfficer2");

    /// @dev Second university, used for cross-institution checks.
    address internal otherRegistrar = makeAddr("otherRegistrar");

    uint32 internal nu;
    uint32 internal other;

    // Synthetic diploma (canonical JSON, see docs/ARCHITECTURE.md).
    string internal constant DIPLOMA =
        '{"credentialType":"BachelorDiploma","degree":"BSc Computer Science","graduationDate":"2026-06-15","honours":"Cum Laude","issuer":"NU-SYNTHETIC","studentId":"S-000001","studentName":"Aigerim Synthetic"}';
    string internal constant DIPLOMA_TAMPERED =
        '{"credentialType":"BachelorDiploma","degree":"BSc Computer Science","graduationDate":"2026-06-15","honours":"Summa Cum Laude","issuer":"NU-SYNTHETIC","studentId":"S-000001","studentName":"Aigerim Synthetic"}';
    bytes32 internal constant SALT = keccak256("synthetic-salt-0001");

    // ---- policy factories (primary experiment parameters) ----

    function _single() internal returns (IApprovalPolicy) {
        return new SingleIssuerPolicy();
    }

    function _unanimous() internal returns (IApprovalPolicy) {
        return new UnanimousPolicy();
    }

    function _majority() internal returns (IApprovalPolicy) {
        return new MajorityPolicy(4);
    }

    function _roleConstrained() internal returns (IApprovalPolicy) {
        return new RoleConstrainedPolicy(4, [uint256(0), 1, 1, 1]);
    }

    // ---- setup ----

    function _deploy(IApprovalPolicy policy) internal {
        registry = new CredentialRegistry(policy, governor);
        vm.startPrank(governor);
        nu = registry.registerUniversity("Nazarbayev University (synthetic)");
        registry.addApprover(nu, r1, Role.Registrar);
        registry.addApprover(nu, r2, Role.Registrar);
        registry.addApprover(nu, d1, Role.Dean);
        registry.addApprover(nu, d2, Role.Dean);
        registry.addApprover(nu, d3, Role.Dean);
        registry.addApprover(nu, e1, Role.ExamOfficer);
        registry.addApprover(nu, e2, Role.ExamOfficer);
        other = registry.registerUniversity("Other University (synthetic)");
        registry.addApprover(other, otherRegistrar, Role.Registrar);
        vm.stopPrank();
    }

    // ---- helpers ----

    function _commitment(string memory doc, bytes32 salt) internal view returns (bytes32) {
        return registry.computeCommitment(keccak256(bytes(doc)), salt);
    }

    function _diplomaCommitment() internal view returns (bytes32) {
        return _commitment(DIPLOMA, SALT);
    }

    /// @dev signers[0] proposes, the rest approve, signers[0] finalizes.
    function _issue(bytes32 c, address[] memory signers) internal {
        vm.prank(signers[0]);
        registry.propose(c);
        for (uint256 i = 1; i < signers.length; ++i) {
            vm.prank(signers[i]);
            registry.approve(c);
        }
        vm.prank(signers[0]);
        registry.finalize(c);
    }

    function _list(address a) internal pure returns (address[] memory l) {
        l = new address[](1);
        l[0] = a;
    }

    function _list(address a, address b, address c, address d) internal pure returns (address[] memory l) {
        l = new address[](4);
        (l[0], l[1], l[2], l[3]) = (a, b, c, d);
    }

    /// @dev A valid role-constrained quorum: 1 Registrar, 2 Deans, 1 Exam Officer.
    function _validQuorum() internal view returns (address[] memory) {
        return _list(r1, d1, d2, e1);
    }

    function _allSeven() internal view returns (address[] memory l) {
        l = new address[](7);
        (l[0], l[1], l[2], l[3], l[4], l[5], l[6]) = (r1, r2, d1, d2, d3, e1, e2);
    }

    function _status(bytes32 c) internal view returns (CredentialRegistry.VerificationStatus) {
        return registry.verify(c).status;
    }
}
