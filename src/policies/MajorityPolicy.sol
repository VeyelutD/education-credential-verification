// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IApprovalPolicy} from "../interfaces/IApprovalPolicy.sol";
import {Role} from "../Types.sol";

/// @title Policy C - Threshold / Majority (M-of-N, role-agnostic)
/// @notice At least `threshold` valid approvals from approvers of any role.
/// @dev The threshold is fixed at deployment (e.g. 4 for a 7-member
///      university) so it can be matched exactly by RoleConstrainedPolicy.
contract MajorityPolicy is IApprovalPolicy {
    uint256 public immutable threshold;

    error ZeroThreshold();

    constructor(uint256 threshold_) {
        if (threshold_ == 0) revert ZeroThreshold();
        threshold = threshold_;
    }

    function policyName() external pure returns (string memory) {
        return "MAJORITY";
    }

    function isEligible(Role role) external pure returns (bool) {
        return role != Role.None;
    }

    function isSatisfied(uint256[4] calldata, uint256 totalValid, uint256) external view returns (bool) {
        return totalValid >= threshold;
    }
}
