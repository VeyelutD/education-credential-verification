// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CredentialFixture} from "./utils/CredentialFixture.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";

/// @notice Revocation rules (identical under every policy).
contract RevocationTest is CredentialFixture {
    bytes32 internal c;

    function setUp() public {
        _deploy(_roleConstrained());
        c = _diplomaCommitment();
        _issue(c, _validQuorum());
    }

    function test_RegistrarCanRevoke() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit CredentialRegistry.CredentialRevoked(c, nu, r1, "DATA_ENTRY_ERROR");
        vm.prank(r1);
        registry.revoke(c, "DATA_ENTRY_ERROR");
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Revoked));
    }

    function test_GovernorCanRevoke() public {
        vm.prank(governor);
        registry.revoke(c, "COURT_ORDER");
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Revoked));
    }

    function test_DeanCannotRevoke() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotAuthorizedToRevoke.selector, d1));
        vm.prank(d1);
        registry.revoke(c, "x");
    }

    function test_OutsiderCannotRevoke() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotAuthorizedToRevoke.selector, outsider));
        vm.prank(outsider);
        registry.revoke(c, "x");
    }

    function test_OtherUniversityRegistrarCannotRevoke() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotAuthorizedToRevoke.selector, otherRegistrar));
        vm.prank(otherRegistrar);
        registry.revoke(c, "x");
    }

    function test_DeactivatedRegistrarCannotRevoke() public {
        vm.prank(governor);
        registry.setApproverActive(r1, false);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotAuthorizedToRevoke.selector, r1));
        vm.prank(r1);
        registry.revoke(c, "x");
    }

    function test_RegistrarCanRevokeAfterUniversityDeactivated() public {
        vm.prank(governor);
        registry.setUniversityActive(nu, false);
        vm.prank(r1);
        registry.revoke(c, "INSTITUTION_CLOSED");
        assertEq(uint8(_status(c)), uint8(CredentialRegistry.VerificationStatus.Revoked));
    }

    function test_CannotRevokeTwice() public {
        vm.prank(r1);
        registry.revoke(c, "x");
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotIssued.selector, c));
        vm.prank(r2);
        registry.revoke(c, "y");
    }

    function test_CannotRevokePendingOrUnknown() public {
        bytes32 pending = _commitment(DIPLOMA, keccak256("pending-salt"));
        vm.prank(r1);
        registry.propose(pending);
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotIssued.selector, pending));
        vm.prank(r1);
        registry.revoke(pending, "x");

        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.NotIssued.selector, unknown));
        vm.prank(r1);
        registry.revoke(unknown, "x");
    }

    function test_RevokedCommitmentCannotBeReissued() public {
        vm.prank(r1);
        registry.revoke(c, "x");
        vm.expectRevert(
            abi.encodeWithSelector(
                CredentialRegistry.CommitmentAlreadyUsed.selector, c, CredentialRegistry.RecordStatus.Revoked
            )
        );
        vm.prank(r1);
        registry.propose(c);
    }
}
