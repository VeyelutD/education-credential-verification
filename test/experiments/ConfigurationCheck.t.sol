// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CredentialRegistry} from "../../src/CredentialRegistry.sol";
import {IApprovalPolicy} from "../../src/interfaces/IApprovalPolicy.sol";
import {Role} from "../../src/Types.sol";
import {MajorityPolicy} from "../../src/policies/MajorityPolicy.sol";
import {RoleConstrainedPolicy} from "../../src/policies/RoleConstrainedPolicy.sol";

/// @notice Experiment D check: all 511 coalitions of a 3-3-3 university, at
///         thresholds 4 and 5, must behave on-chain as configuration_study.py assumes.
contract ConfigurationCheckTest is Test {
    string internal constant OUT = "data/configuration_onchain.csv";
    CredentialRegistry internal registry;
    address[9] internal staff;

    function test_ThreeThreeThree() public {
        if (vm.exists(OUT)) vm.removeFile(OUT);
        vm.writeLine(OUT, "threshold,policy,size,capable");
        for (uint256 m = 4; m <= 5; ++m) {
            _run(m, "C", new MajorityPolicy(m));
            _run(m, "D", new RoleConstrainedPolicy(m, [uint256(0), 1, 1, 1]));
        }
    }

    function _run(uint256 m, string memory key, IApprovalPolicy policy) internal {
        address governor = makeAddr("governor");
        registry = new CredentialRegistry(policy, governor);
        vm.startPrank(governor);
        uint32 uni = registry.registerUniversity("3-3-3 (synthetic)");
        for (uint256 i; i < 9; ++i) {
            staff[i] = address(uint160(0xA000 + i));
            registry.addApprover(uni, staff[i], Role(i / 3 + 1));
        }
        vm.stopPrank();

        uint256[10] memory capable;
        for (uint256 mask = 1; mask < 512; ++mask) {
            (bool ok, uint256 size) = _attempt(keccak256(abi.encode(key, m, mask)), mask);
            if (ok) capable[size] += 1;
        }
        for (uint256 size = 1; size <= 9; ++size) {
            vm.writeLine(
                OUT,
                string.concat(vm.toString(m), ",", key, ",", vm.toString(size), ",", vm.toString(capable[size]))
            );
        }
    }

    function _attempt(bytes32 c, uint256 mask) internal returns (bool, uint256 size) {
        address proposer;
        for (uint256 i; i < 9; ++i) {
            if (mask & (uint256(1) << i) == 0) continue;
            ++size;
            vm.prank(staff[i]);
            if (proposer == address(0)) {
                proposer = staff[i];
                registry.propose(c);
            } else {
                registry.approve(c);
            }
        }
        vm.prank(proposer);
        try registry.finalize(c) {
            return (true, size);
        } catch {
            return (false, size);
        }
    }
}
