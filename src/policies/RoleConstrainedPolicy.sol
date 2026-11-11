// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IApprovalPolicy} from "../interfaces/IApprovalPolicy.sol";
import {Role, ROLE_SLOTS} from "../Types.sol";

/// @title Policy D - Role-Constrained Threshold
/// @notice At least `threshold` valid approvals in total AND at least
///         `minPerRole[r]` valid approvals from each role r.
/// @dev Example primary configuration: threshold = 4,
///      minPerRole = [0, 1, 1, 1] (Registrar, Dean, ExamOfficer >= 1 each).
contract RoleConstrainedPolicy is IApprovalPolicy {
    uint256 public immutable threshold;
    uint256 public immutable minRegistrar;
    uint256 public immutable minDean;
    uint256 public immutable minExamOfficer;

    error ZeroThreshold();
    error MinimumsExceedThreshold();

    /// @param minPerRole indexed by uint8(Role); index 0 (None) is ignored.
    constructor(uint256 threshold_, uint256[4] memory minPerRole) {
        if (threshold_ == 0) revert ZeroThreshold();
        uint256 sum = minPerRole[1] + minPerRole[2] + minPerRole[3];
        if (sum > threshold_) revert MinimumsExceedThreshold();
        threshold = threshold_;
        minRegistrar = minPerRole[uint8(Role.Registrar)];
        minDean = minPerRole[uint8(Role.Dean)];
        minExamOfficer = minPerRole[uint8(Role.ExamOfficer)];
    }

    function policyName() external pure returns (string memory) {
        return "ROLE_CONSTRAINED";
    }

    function isEligible(Role role) external pure returns (bool) {
        return role != Role.None;
    }

    function minimumFor(Role role) public view returns (uint256) {
        if (role == Role.Registrar) return minRegistrar;
        if (role == Role.Dean) return minDean;
        if (role == Role.ExamOfficer) return minExamOfficer;
        return 0;
    }

    function isSatisfied(uint256[4] calldata roleCounts, uint256 totalValid, uint256)
        external
        view
        returns (bool)
    {
        if (totalValid < threshold) return false;
        for (uint256 r = 1; r < ROLE_SLOTS; ++r) {
            if (roleCounts[r] < minimumFor(Role(r))) return false;
        }
        return true;
    }
}
