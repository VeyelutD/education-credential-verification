// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {CredentialFixture} from "./utils/CredentialFixture.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {IApprovalPolicy} from "../src/interfaces/IApprovalPolicy.sol";
import {Role} from "../src/Types.sol";

/// @notice University and approver management, governance boundaries.
contract RegistryTest is CredentialFixture {
    function setUp() public {
        _deploy(_roleConstrained());
    }

    function test_ConstructorRejectsZeroAddresses() public {
        IApprovalPolicy p = _majority();
        vm.expectRevert(CredentialRegistry.ZeroAddress.selector);
        new CredentialRegistry(IApprovalPolicy(address(0)), governor);
        vm.expectRevert(CredentialRegistry.ZeroAddress.selector);
        new CredentialRegistry(p, address(0));
    }

    function test_UniversityRegistered() public view {
        CredentialRegistry.University memory u = registry.getUniversity(nu);
        assertTrue(u.exists);
        assertTrue(u.active);
        assertEq(u.approverCount, 7);
        assertEq(u.name, "Nazarbayev University (synthetic)");
        assertEq(registry.universityCount(), 2);
    }

    function test_RoleCounts() public view {
        assertEq(registry.activeRoleCount(nu, Role.Registrar), 2);
        assertEq(registry.activeRoleCount(nu, Role.Dean), 3);
        assertEq(registry.activeRoleCount(nu, Role.ExamOfficer), 2);
    }

    function test_OnlyGovernorCanRegisterUniversity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, r1, registry.GOVERNOR_ROLE()
            )
        );
        vm.prank(r1);
        registry.registerUniversity("Rogue University");
    }

    function test_OnlyGovernorCanAddApprover() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, r1, registry.GOVERNOR_ROLE()
            )
        );
        vm.prank(r1);
        registry.addApprover(nu, outsider, Role.Dean);
    }

    function test_CannotAddApproverToUnknownUniversity() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.UnknownUniversity.selector, uint32(99)));
        vm.prank(governor);
        registry.addApprover(99, outsider, Role.Dean);
    }

    function test_CannotAddRoleNone() public {
        vm.expectRevert(CredentialRegistry.InvalidRole.selector);
        vm.prank(governor);
        registry.addApprover(nu, outsider, Role.None);
    }

    function test_CannotRegisterApproverTwice() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.ApproverAlreadyRegistered.selector, d1));
        vm.prank(governor);
        registry.addApprover(other, d1, Role.Registrar);
    }

    function test_GovernorCannotBecomeApprover() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.GovernorCannotBeApprover.selector, governor));
        vm.prank(governor);
        registry.addApprover(nu, governor, Role.Registrar);
    }

    function test_ApproverCannotBeGrantedGovernorRole() public {
        bytes32 gov = registry.GOVERNOR_ROLE();
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.GovernorCannotBeApprover.selector, r1));
        vm.prank(governor);
        registry.grantRole(gov, r1);
    }

    function test_ApproverCannotBeGrantedAdminRole() public {
        bytes32 admin = registry.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.GovernorCannotBeApprover.selector, r1));
        vm.prank(governor);
        registry.grantRole(admin, r1);
    }

    function test_MaxApproversPerUniversity() public {
        uint256 maxN = registry.MAX_APPROVERS_PER_UNIVERSITY();
        vm.startPrank(governor);
        for (uint256 i = 7; i < maxN; ++i) {
            registry.addApprover(nu, address(uint160(0x1000 + i)), Role.Dean);
        }
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.TooManyApprovers.selector, nu));
        registry.addApprover(nu, address(uint160(0x9999)), Role.Dean);
        vm.stopPrank();
    }

    function test_ChangeRoleUpdatesCountsAndNonce() public {
        uint64 nonceBefore = registry.getApprover(d1).nonce;
        vm.prank(governor);
        registry.changeApproverRole(d1, Role.ExamOfficer);

        CredentialRegistry.Approver memory ap = registry.getApprover(d1);
        assertEq(uint8(ap.role), uint8(Role.ExamOfficer));
        assertEq(ap.nonce, nonceBefore + 1);
        assertEq(registry.activeRoleCount(nu, Role.Dean), 2);
        assertEq(registry.activeRoleCount(nu, Role.ExamOfficer), 3);
    }

    function test_ChangeRoleToSameRoleReverts() public {
        vm.expectRevert(CredentialRegistry.NoStateChange.selector);
        vm.prank(governor);
        registry.changeApproverRole(d1, Role.Dean);
    }

    function test_ChangeRoleOfUnknownReverts() public {
        vm.expectRevert(abi.encodeWithSelector(CredentialRegistry.ApproverNotRegistered.selector, outsider));
        vm.prank(governor);
        registry.changeApproverRole(outsider, Role.Dean);
    }

    function test_DeactivateAndReactivateApprover() public {
        vm.prank(governor);
        registry.setApproverActive(e1, false);
        assertFalse(registry.getApprover(e1).active);
        assertEq(registry.activeRoleCount(nu, Role.ExamOfficer), 1);

        vm.prank(governor);
        registry.setApproverActive(e1, true);
        CredentialRegistry.Approver memory ap = registry.getApprover(e1);
        assertTrue(ap.active);
        assertEq(ap.nonce, 3); // 1 at registration, +1 per status change
        assertEq(registry.activeRoleCount(nu, Role.ExamOfficer), 2);
    }

    function test_RoleChangeWhileInactiveKeepsCountsConsistent() public {
        vm.startPrank(governor);
        registry.setApproverActive(d1, false);
        registry.changeApproverRole(d1, Role.Registrar);
        vm.stopPrank();
        assertEq(registry.activeRoleCount(nu, Role.Dean), 2);
        assertEq(registry.activeRoleCount(nu, Role.Registrar), 2);

        vm.prank(governor);
        registry.setApproverActive(d1, true);
        assertEq(registry.activeRoleCount(nu, Role.Registrar), 3);
    }

    function test_DeactivateUniversity() public {
        vm.prank(governor);
        registry.setUniversityActive(nu, false);
        assertFalse(registry.getUniversity(nu).active);

        vm.expectRevert(CredentialRegistry.NoStateChange.selector);
        vm.prank(governor);
        registry.setUniversityActive(nu, false);
    }
}
