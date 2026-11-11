// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IApprovalPolicy} from "../interfaces/IApprovalPolicy.sol";
import {Role} from "../Types.sol";

/// @title Policy A - Single Issuer
/// @notice Any one active Registrar can issue on their own. Other roles have
///         no issuance authority. This models the conventional "one
///         authorized university account" design.
contract SingleIssuerPolicy is IApprovalPolicy {
    function policyName() external pure returns (string memory) {
        return "SINGLE_ISSUER";
    }

    function isEligible(Role role) external pure returns (bool) {
        return role == Role.Registrar;
    }

    function isSatisfied(uint256[4] calldata, uint256 totalValid, uint256) external pure returns (bool) {
        return totalValid >= 1;
    }
}
