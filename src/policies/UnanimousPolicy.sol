// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IApprovalPolicy} from "../interfaces/IApprovalPolicy.sol";
import {Role} from "../Types.sol";

/// @title Policy B - Unanimous (N-of-N)
/// @notice Every currently active approver of the university, of any role,
///         must have a valid approval at finalization time.
/// @dev N is evaluated at finalization: if the governor deactivates an
///      approver, N shrinks; if it adds one, the newcomer must also approve.
contract UnanimousPolicy is IApprovalPolicy {
    function policyName() external pure returns (string memory) {
        return "UNANIMOUS";
    }

    function isEligible(Role role) external pure returns (bool) {
        return role != Role.None;
    }

    function isSatisfied(uint256[4] calldata, uint256 totalValid, uint256 eligibleActive)
        external
        pure
        returns (bool)
    {
        return eligibleActive > 0 && totalValid == eligibleActive;
    }
}
