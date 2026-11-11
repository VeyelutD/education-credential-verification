// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CredentialFixture} from "./utils/CredentialFixture.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {Role} from "../src/Types.sol";

/// @notice Proposal -> approval -> finalization lifecycle, using the primary
///         role-constrained policy (4-of-7, >= 1 per role).
contract IssuanceTest is CredentialFixture {
    bytes32 internal c;

    function setUp() public {
        _deploy(_roleConstrained());
        c = _diplomaCommitment();
    }

    function test_FullIssuance() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit CredentialRegistry.CredentialProposed(c, nu, r1);
        vm.prank(r1);
        registry.propose(c);
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Pending));

        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c);

        (uint256[4] memory counts, uint256 total, uint256 eligibleActive, bool ok) = registry.tally(c);
        assertEq(counts[uint8(Role.Registrar)], 1);
        assertEq(counts[uint8(Role.Dean)], 2);
        assertEq(counts[uint8(Role.ExamOfficer)], 1);
        assertEq(total, 4);
        assertEq(eligibleActive, 7);
        assertTrue(ok);

        vm.expectEmit(true, true, true, true, address(registry));
        emit CredentialRegistry.CredentialIssued(c, nu, e1, 4);
        vm.prank(e1);
        registry.finalize(c);

        CredentialRegistry.VerificationResult memory v = registry.verify(c);
        assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.Valid));
        assertEq(v.universityId, nu);
        assertTrue(v.issuerActive);
        assertEq(v.issuedAt, block.timestamp);
    }

    function test_ProposalCountsAsProposerApproval() public {
        vm.prank(r1);
        registry.propose(c);
        assertTrue(registry.isApprovalValid(c, r1));
        assertEq(registry.getApprovers(c).length, 1);
    }

    function test_CannotFinalizeBelowThreshold() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(d1);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);
    }

    function test_CannotFinalizeWithoutRequiredRole() public {
        // 4 approvals but no Exam Officer.
        vm.prank(r1);
        registry.propose(c);
        vm.prank(r2);
        registry.approve(c);
        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);
    }

    function test_DuplicateProposalReverts() public {
        vm.prank(r1);
        registry.propose(c);
        vm.expectRevert(
            abi.encodeWithSelector(
                CredentialRegistry.CommitmentAlreadyUsed.selector, c, CredentialRegistry.RecordStatus.Pending
            )
        );
        vm.prank(r2);
        registry.propose(c);
    }

    function test_CannotReproposeIssuedCredential() public {
        _issue(c, _validQuorum());
        vm.expectRevert(
            abi.encodeWithSelector(
                CredentialRegistry.CommitmentAlreadyUsed.selector, c, CredentialRegistry.RecordStatus.Issued
            )
        );
        vm.prank(r2);
        registry.propose(c);
    }

    function test_DuplicateApprovalReverts() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(d1);
        registry.approve(c);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.AlreadyApproved.selector, c, d1));
        vm.prank(d1);
        registry.approve(c);
    }

    function test_ProposerCannotApproveAgain() public {
        vm.prank(r1);
        registry.propose(c);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.AlreadyApproved.selector, c, r1));
        vm.prank(r1);
        registry.approve(c);
    }

    function test_CannotFinalizeTwice() public {
        _issue(c, _validQuorum());
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotPending.selector, c));
        vm.prank(r1);
        registry.finalize(c);
    }

    function test_ZeroCommitmentReverts() public {
        vm.expectRevert(CredentialRegistry.InvalidCommitment.selector);
        vm.prank(r1);
        registry.propose(bytes32(0));
    }

    function test_OutsiderCannotProposeApproveOrFinalize() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotActiveApprover.selector, outsider));
        vm.prank(outsider);
        registry.propose(c);

        vm.prank(r1);
        registry.propose(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotActiveApprover.selector, outsider));
        vm.prank(outsider);
        registry.approve(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotActiveApprover.selector, outsider));
        vm.prank(outsider);
        registry.finalize(c);
    }

    /// @dev The governor manages approvers but has no issuance path.
    function test_GovernorCannotIssue() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotActiveApprover.selector, governor));
        vm.prank(governor);
        registry.propose(c);

        vm.prank(r1);
        registry.propose(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotActiveApprover.selector, governor));
        vm.prank(governor);
        registry.approve(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotActiveApprover.selector, governor));
        vm.prank(governor);
        registry.finalize(c);
    }

    function test_OtherUniversityCannotApproveOrFinalize() public {
        vm.prank(r1);
        registry.propose(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.WrongUniversity.selector, otherRegistrar, nu));
        vm.prank(otherRegistrar);
        registry.approve(c);

        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.WrongUniversity.selector, otherRegistrar, nu));
        vm.prank(otherRegistrar);
        registry.finalize(c);
    }

    function test_ApprovalsAreNotReusableAcrossCredentials() public {
        bytes32 c2 = _commitment(DIPLOMA, keccak256("another-salt"));
        // Full quorum on c.
        vm.prank(r1);
        registry.propose(c);
        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c);

        // Only the proposer's approval exists on c2.
        vm.prank(r1);
        registry.propose(c2);
        (,uint256 total,, bool ok) = registry.tally(c2);
        assertEq(total, 1);
        assertFalse(ok);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c2));
        vm.prank(r1);
        registry.finalize(c2);
    }

    function test_DeactivatedUniversityBlocksIssuance() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(governor);
        registry.setUniversityActive(nu, false);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.UniversityInactive.selector, nu));
        vm.prank(d1);
        registry.approve(c);

        // Compute first: _commitment() is an external call and would consume the cheatcodes below.
        bytes32 c2 = _commitment(DIPLOMA, keccak256("x"));
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.UniversityInactive.selector, nu));
        vm.prank(r2);
        registry.propose(c2);
    }

    function test_ProposerCanCancel() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(r1);
        registry.cancelProposal(c);
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.NotFound));
    }

    function test_GovernorCanCancel() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(governor);
        registry.cancelProposal(c);
        assertEq(uint8(registry.getRecord(c).status), uint8(CredentialRegistry.RecordStatus.Cancelled));
    }

    function test_NonProposerApproverCannotCancel() public {
        vm.prank(r1);
        registry.propose(c);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotAuthorizedToCancel.selector, d1));
        vm.prank(d1);
        registry.cancelProposal(c);
    }

    /// @dev Cancelled commitments are burned, so stale approvals can never
    ///      be revived by re-proposing the same commitment.
    function test_CancelledCommitmentCannotBeReproposed() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(r1);
        registry.cancelProposal(c);
        vm.expectRevert(
            abi.encodeWithSelector(
                CredentialRegistry.CommitmentAlreadyUsed.selector, c, CredentialRegistry.RecordStatus.Cancelled
            )
        );
        vm.prank(r1);
        registry.propose(c);
    }

    function test_CannotApproveCancelledProposal() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(r1);
        registry.cancelProposal(c);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotPending.selector, c));
        vm.prank(d1);
        registry.approve(c);
    }
}
