// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CredentialFixture} from "./utils/CredentialFixture.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";

/// @notice One insider must not be able to block a credential for good by
///         proposing its commitment first and then cancelling.
contract ProposalSquattingTest is CredentialFixture {
    bytes32 internal c;

    function setUp() public {
        _deploy(_roleConstrained());
        c = _diplomaCommitment();
    }

    /// @dev The attack: squat (propose first), cancel, hope the commitment is burned.
    function test_SquatAndCancelDoesNotBurnCommitment() public {
        vm.startPrank(e2);
        registry.propose(c);
        registry.cancelProposal(c);
        vm.stopPrank();

        _issue(c, _validQuorum());
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Valid));
    }

    /// @dev Squatting without cancelling: honest staff can approve the open proposal,
    ///      and from then on the squatter can no longer cancel it.
    function test_ProposerCannotCancelAfterAnotherApproval() public {
        vm.prank(e2);
        registry.propose(c);
        vm.prank(r1);
        registry.approve(c);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotAuthorizedToCancel.selector, e2));
        vm.prank(e2);
        registry.cancelProposal(c);

        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(r1);
        registry.finalize(c);
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Valid));
    }

    /// @dev Why re-proposal was blocked originally: old approvals must not count again.
    function test_ApprovalsDoNotCarryOverToNewRound() public {
        vm.prank(r1);
        registry.propose(c);
        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c); // quorum reached in round 0
        vm.prank(governor);
        registry.cancelProposal(c);

        vm.prank(r2);
        registry.propose(c);
        (, uint256 total,, bool ok) = registry.tally(c);
        assertEq(total, 1);
        assertFalse(ok);
        assertFalse(registry.isApprovalValid(c, d1));
        assertEq(registry.getApprovers(c).length, 1);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r2);
        registry.finalize(c);

        // The same people can approve again in the new round.
        vm.prank(d1);
        registry.approve(c);
        assertTrue(registry.isApprovalValid(c, d1));
    }

    function test_RevokedAndIssuedStayFinal() public {
        _issue(c, _validQuorum());
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotPending.selector, c));
        vm.prank(governor);
        registry.cancelProposal(c);
    }
}
