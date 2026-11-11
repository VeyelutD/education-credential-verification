// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Institutional roles an approver can hold.
/// @dev `None` (0) means "not registered". The numeric values are used as
///      indices into `uint256[4]` role-count arrays, so do not reorder.
enum Role {
    None,
    Registrar,
    Dean,
    ExamOfficer
}

/// @dev Length of role-indexed arrays (including the unused `None` slot).
uint256 constant ROLE_SLOTS = 4;
