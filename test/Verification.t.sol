// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CredentialFixture} from "./utils/CredentialFixture.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";

/// @notice What an employer (verifier) learns from the registry.
contract VerificationTest is CredentialFixture {
    bytes32 internal c;

    function setUp() public {
        _deploy(_roleConstrained());
        c = _diplomaCommitment();
    }

    function test_CommitmentMatchesDocumentedFormula() public view {
        bytes32 expected = keccak256(
            abi.encode(keccak256("KZ-ACADEMIC-CREDENTIAL-v1"), keccak256(bytes(DIPLOMA)), SALT)
        );
        assertEq(c, expected);
    }

    function test_NotFound() public view {
        CredentialRegistry.VerificationResult memory v = registry.verify(c);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.NotFound));
        assertEq(v.universityId, 0);
    }

    function test_PendingIsNotValid() public {
        vm.prank(r1);
        registry.propose(c);
        CredentialRegistry.VerificationResult memory v = registry.verify(c);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.Pending));
        assertEq(v.universityId, nu);
        assertEq(v.issuedAt, 0);
    }

    function test_ValidAfterIssuance() public {
        vm.warp(1_750_000_000);
        _issue(c, _validQuorum());
        vm.prank(employer);
        CredentialRegistry.VerificationResult memory v = registry.verifyDocument(keccak256(bytes(DIPLOMA)), SALT);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.Valid));
        assertEq(v.universityId, nu);
        assertTrue(v.issuerActive);
        assertEq(v.issuedAt, 1_750_000_000);
        assertEq(v.revokedAt, 0);
    }

    function test_TamperedDocumentFails() public {
        _issue(c, _validQuorum());
        CredentialRegistry.VerificationResult memory v =
            registry.verifyDocument(keccak256(bytes(DIPLOMA_TAMPERED)), SALT);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.NotFound));
    }

    function test_WrongSaltFails() public {
        _issue(c, _validQuorum());
        CredentialRegistry.VerificationResult memory v =
            registry.verifyDocument(keccak256(bytes(DIPLOMA)), keccak256("guessed-salt"));
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.NotFound));
    }

    function test_RevokedStatus() public {
        _issue(c, _validQuorum());
        vm.warp(block.timestamp + 30 days);
        vm.prank(r2);
        registry.revoke(c, "ACADEMIC_MISCONDUCT");
        CredentialRegistry.VerificationResult memory v = registry.verify(c);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.Revoked));
        assertEq(v.revokedAt, block.timestamp);
        assertEq(v.revocationReason, bytes32("ACADEMIC_MISCONDUCT"));
    }

    function test_IssuerDeactivationIsVisibleButKeepsStatus() public {
        _issue(c, _validQuorum());
        vm.prank(governor);
        registry.setUniversityActive(nu, false);
        CredentialRegistry.VerificationResult memory v = registry.verify(c);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.Valid));
        assertFalse(v.issuerActive);
    }

    function test_CancelledReadsAsNotFound() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(r1);
        registry.cancelProposal(c);
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.NotFound));
    }

    /// @dev Any single-byte change to the document must change the commitment.
    function testFuzz_AnyDocumentChangeBreaksVerification(bytes memory doc, uint256 pos, bytes1 delta) public {
        vm.assume(doc.length > 0 && delta != 0x00);
        bytes32 salt = keccak256(doc);
        bytes32 original = _commitment(string(doc), salt);
        vm.prank(r1);
        registry.propose(original);
        vm.prank(d1);
        registry.approve(original);
        vm.prank(d2);
        registry.approve(original);
        vm.prank(e1);
        registry.approve(original);
        vm.prank(r1);
        registry.finalize(original);

        bytes memory changed = bytes.concat(doc); // copy
        pos = bound(pos, 0, doc.length - 1);
        changed[pos] = changed[pos] ^ delta;
        CredentialRegistry.VerificationResult memory v = registry.verifyDocument(keccak256(changed), salt);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.NotFound));
    }
}
