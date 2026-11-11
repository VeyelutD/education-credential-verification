// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CredentialFixture} from "./utils/CredentialFixture.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {IApprovalPolicy} from "../src/interfaces/IApprovalPolicy.sol";
import {Role} from "../src/Types.sol";
import {RoleConstrainedPolicy} from "../src/policies/RoleConstrainedPolicy.sol";
import {MajorityPolicy} from "../src/policies/MajorityPolicy.sol";

/// @notice Policy-specific authorization rules, pending-proposal semantics
///         under approver changes, and an exhaustive on-chain check of every
///         possible insider coalition (cross-checks experiments/coalition_analysis.py).
contract PolicySecurityTest is CredentialFixture {
    enum Kind {
        Single,
        Unanimous,
        Majority,
        RoleConstrained
    }

    function _policy(Kind k) internal returns (IApprovalPolicy) {
        if (k == Kind.Single) return _single();
        if (k == Kind.Unanimous) return _unanimous();
        if (k == Kind.Majority) return _majority();
        return _roleConstrained();
    }

    // ------------------------------------------------------------------
    // Policy A: Single issuer
    // ------------------------------------------------------------------

    function test_Single_OneRegistrarIssuesAlone() public {
        _deploy(_single());
        bytes32 c = _diplomaCommitment();
        _issue(c, _list(r1));
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Valid));
    }

    function test_Single_NonRegistrarsHaveNoAuthority() public {
        _deploy(_single());
        bytes32 c = _diplomaCommitment();
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotEligible.selector, d1, Role.Dean));
        vm.prank(d1);
        registry.propose(c);

        vm.prank(r1);
        registry.propose(c);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotEligible.selector, e1, Role.ExamOfficer));
        vm.prank(e1);
        registry.approve(c);
    }

    // ------------------------------------------------------------------
    // Policy B: Unanimous
    // ------------------------------------------------------------------

    function test_Unanimous_SixOfSevenFails_SevenSucceeds() public {
        _deploy(_unanimous());
        bytes32 c = _diplomaCommitment();
        address[] memory all = _allSeven();
        vm.prank(all[0]);
        registry.propose(c);
        for (uint256 i = 1; i < 6; ++i) {
            vm.prank(all[i]);
            registry.approve(c);
        }
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);

        vm.prank(all[6]);
        registry.approve(c);
        vm.prank(r1);
        registry.finalize(c);
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Valid));
    }

    /// @dev Documented behaviour: N is evaluated at finalization, so the
    ///      governor deactivating an absent approver shrinks N. This is a
    ///      governance (not insider) power and is listed in the threat model.
    function test_Unanimous_NIsEvaluatedAtFinalization() public {
        _deploy(_unanimous());
        bytes32 c = _diplomaCommitment();
        address[] memory all = _allSeven();
        vm.prank(all[0]);
        registry.propose(c);
        for (uint256 i = 1; i < 6; ++i) {
            vm.prank(all[i]);
            registry.approve(c);
        }
        vm.prank(governor);
        registry.setApproverActive(all[6], false);
        vm.prank(r1);
        registry.finalize(c);
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Valid));
    }

    function test_Unanimous_NewApproverMustAlsoApprove() public {
        _deploy(_unanimous());
        bytes32 c = _diplomaCommitment();
        address[] memory all = _allSeven();
        vm.prank(all[0]);
        registry.propose(c);
        for (uint256 i = 1; i < 7; ++i) {
            vm.prank(all[i]);
            registry.approve(c);
        }
        address newcomer = makeAddr("newDean");
        vm.prank(governor);
        registry.addApprover(nu, newcomer, Role.Dean);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);
    }

    // ------------------------------------------------------------------
    // Policy C vs D: same threshold, role constraint is the only difference
    // ------------------------------------------------------------------

    function test_Majority_FourDeansAndExamOfficersSucceed() public {
        _deploy(_majority());
        bytes32 c = _diplomaCommitment();
        _issue(c, _list(d1, d2, d3, e1)); // no registrar involved
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Valid));
    }

    function test_RoleConstrained_SameCoalitionFails() public {
        _deploy(_roleConstrained());
        bytes32 c = _diplomaCommitment();
        vm.prank(d1);
        registry.propose(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(d3);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(d1);
        registry.finalize(c);
    }

    function test_Majority_ThreeFails() public {
        _deploy(_majority());
        bytes32 c = _diplomaCommitment();
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

    function test_RoleConstrained_RejectsImpossibleConfig() public {
        vm.expectRevert(RoleConstrainedPolicy.MinimumsExceedThreshold.selector);
        new RoleConstrainedPolicy(2, [uint256(0), 1, 1, 1]);
        vm.expectRevert(RoleConstrainedPolicy.ZeroThreshold.selector);
        new RoleConstrainedPolicy(0, [uint256(0), 0, 0, 0]);
        vm.expectRevert(MajorityPolicy.ZeroThreshold.selector);
        new MajorityPolicy(0);
    }

    function test_RoleConstrained_UnavailableRoleBlocksIssuance() public {
        _deploy(_roleConstrained());
        vm.startPrank(governor);
        registry.setApproverActive(e1, false);
        registry.setApproverActive(e2, false);
        vm.stopPrank();
        bytes32 c = _diplomaCommitment();
        vm.prank(r1);
        registry.propose(c);
        vm.prank(r2);
        registry.approve(c);
        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(d3);
        registry.approve(c);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);
    }

    // ------------------------------------------------------------------
    // Pending proposals when approvers change (all policies share this)
    // ------------------------------------------------------------------

    function test_RoleChangeInvalidatesPendingApproval() public {
        _deploy(_roleConstrained());
        bytes32 c = _diplomaCommitment();
        vm.prank(r1);
        registry.propose(c);
        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c);

        // e1 is reassigned; their Exam Officer approval no longer counts.
        vm.prank(governor);
        registry.changeApproverRole(e1, Role.Dean);
        assertFalse(registry.isApprovalValid(c, e1));
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);

        // e1 re-approves as a Dean: 4 valid approvals, but still no Exam Officer.
        vm.prank(e1);
        registry.approve(c);
        assertTrue(registry.isApprovalValid(c, e1));
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);

        // A real Exam Officer approves; now satisfiable.
        vm.prank(e2);
        registry.approve(c);
        vm.prank(r1);
        registry.finalize(c);
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Valid));
        assertEq(registry.getApprovers(c).length, 5); // e1 listed once
    }

    function test_DeactivatedApproverCannotActAndApprovalStopsCounting() public {
        _deploy(_majority());
        bytes32 c = _diplomaCommitment();
        vm.prank(r1);
        registry.propose(c);
        vm.prank(d1);
        registry.approve(c);
        vm.prank(d2);
        registry.approve(c);
        vm.prank(e1);
        registry.approve(c);

        vm.prank(governor);
        registry.setApproverActive(d2, false);

        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotActiveApprover.selector, d2));
        vm.prank(d2);
        registry.approve(c);

        (, uint256 total,,) = registry.tally(c);
        assertEq(total, 3);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.PolicyNotSatisfied.selector, c));
        vm.prank(r1);
        registry.finalize(c);
    }

    function test_ReactivationDoesNotReviveOldApproval() public {
        _deploy(_majority());
        bytes32 c = _diplomaCommitment();
        vm.prank(r1);
        registry.propose(c);
        vm.prank(d1);
        registry.approve(c);
        vm.startPrank(governor);
        registry.setApproverActive(d1, false);
        registry.setApproverActive(d1, true);
        vm.stopPrank();
        assertFalse(registry.isApprovalValid(c, d1));
    }

    // ------------------------------------------------------------------
    // Exhaustive coalition enumeration on-chain (2^7 - 1 coalitions/policy)
    // ------------------------------------------------------------------

    function test_Coalitions_Single() public {
        _checkAllCoalitions(Kind.Single);
    }

    function test_Coalitions_Unanimous() public {
        _checkAllCoalitions(Kind.Unanimous);
    }

    function test_Coalitions_Majority() public {
        _checkAllCoalitions(Kind.Majority);
    }

    function test_Coalitions_RoleConstrained() public {
        _checkAllCoalitions(Kind.RoleConstrained);
    }

    /// @dev For every non-empty subset of the 7 employees, the coalition
    ///      tries to issue a fraudulent credential using only its members.
    ///      The on-chain outcome must match the policy's written rule.
    function _checkAllCoalitions(Kind k) internal {
        _deploy(_policy(k));
        address[] memory members = _allSeven();
        Role[7] memory roles =
            [Role.Registrar, Role.Registrar, Role.Dean, Role.Dean, Role.Dean, Role.ExamOfficer, Role.ExamOfficer];

        for (uint256 mask = 1; mask < (uint256(1) << 7); ++mask) {
            bytes32 c = keccak256(abi.encode("fraud", k, mask));
            bool succeeded = _attempt(c, mask, members, roles, k);
            assertEq(succeeded, _expected(mask, roles, k), "coalition outcome mismatch");
        }
    }

    function _attempt(bytes32 c, uint256 mask, address[] memory members, Role[7] memory roles, Kind k)
        internal
        returns (bool)
    {
        address proposer;
        for (uint256 i; i < 7; ++i) {
            if (mask & (uint256(1) << i) == 0) continue;
            if (k == Kind.Single && roles[i] != Role.Registrar) continue; // ineligible under A
            if (proposer == address(0)) {
                proposer = members[i];
                vm.prank(proposer);
                registry.propose(c);
            } else {
                vm.prank(members[i]);
                registry.approve(c);
            }
        }
        if (proposer == address(0)) return false;
        vm.prank(proposer);
        try registry.finalize(c) {
            return true;
        } catch {
            return false;
        }
    }

    function _expected(uint256 mask, Role[7] memory roles, Kind k) internal pure returns (bool) {
        uint256[4] memory perRole;
        uint256 size;
        for (uint256 i; i < 7; ++i) {
            if (mask & (uint256(1) << i) != 0) {
                perRole[uint8(roles[i])] += 1;
                size += 1;
            }
        }
        if (k == Kind.Single) return perRole[uint8(Role.Registrar)] >= 1;
        if (k == Kind.Unanimous) return size == 7;
        if (k == Kind.Majority) return size >= 4;
        return size >= 4 && perRole[1] >= 1 && perRole[2] >= 1 && perRole[3] >= 1;
    }
}
