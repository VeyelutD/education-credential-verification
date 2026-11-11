// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Role} from "../Types.sol";

/// @title IApprovalPolicy
/// @notice Issuance-authorization rule plugged into a CredentialRegistry.
/// @dev Policies are stateless judges: the registry owns all approver,
///      proposal and approval state and only asks the policy two questions.
///      This keeps the credential format, storage and lifecycle identical
///      across policies so that only the authorization rule varies.
interface IApprovalPolicy {
    /// @notice Short human-readable identifier, e.g. "ROLE_CONSTRAINED_4of7".
    function policyName() external view returns (string memory);

    /// @notice Whether an approver holding `role` may propose, approve or
    ///         finalize under this policy.
    function isEligible(Role role) external view returns (bool);

    /// @notice Whether a set of *valid* approvals authorizes issuance.
    /// @param roleCounts      Valid approvals per role, indexed by `uint8(Role)`.
    /// @param totalValid      Sum of `roleCounts` (passed to save recomputation).
    /// @param eligibleActive  Number of currently active, eligible approvers at
    ///                        the issuing university (the "N" in M-of-N).
    function isSatisfied(uint256[4] calldata roleCounts, uint256 totalValid, uint256 eligibleActive)
        external
        view
        returns (bool);
}
