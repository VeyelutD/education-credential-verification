// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {IApprovalPolicy} from "../src/interfaces/IApprovalPolicy.sol";
import {SingleIssuerPolicy} from "../src/policies/SingleIssuerPolicy.sol";
import {UnanimousPolicy} from "../src/policies/UnanimousPolicy.sol";
import {MajorityPolicy} from "../src/policies/MajorityPolicy.sol";
import {RoleConstrainedPolicy} from "../src/policies/RoleConstrainedPolicy.sol";

/// @notice Deploys one policy + one registry. The broadcaster becomes governor.
/// @dev Usage (local Anvil):
///   POLICY=ROLE_CONSTRAINED forge script script/Deploy.s.sol \
///     --rpc-url http://127.0.0.1:8545 --broadcast --private-key <anvil key 0>
///   POLICY is one of SINGLE | UNANIMOUS | MAJORITY | ROLE_CONSTRAINED
///   (default ROLE_CONSTRAINED). THRESHOLD defaults to 4.
contract Deploy is Script {
    function run() external returns (CredentialRegistry registry, IApprovalPolicy policy) {
        string memory kind = vm.envOr("POLICY", string("ROLE_CONSTRAINED"));
        uint256 threshold = vm.envOr("THRESHOLD", uint256(4));

        vm.startBroadcast();
        (, address broadcaster,) = vm.readCallers();
        policy = _deployPolicy(kind, threshold);
        registry = new CredentialRegistry(policy, broadcaster);
        vm.stopBroadcast();

        console2.log("Policy   :", policy.policyName(), address(policy));
        console2.log("Registry :", address(registry));
        console2.log("Governor :", broadcaster);
    }

    function _deployPolicy(string memory kind, uint256 threshold) internal returns (IApprovalPolicy) {
        bytes32 k = keccak256(bytes(kind));
        if (k == keccak256("SINGLE")) return new SingleIssuerPolicy();
        if (k == keccak256("UNANIMOUS")) return new UnanimousPolicy();
        if (k == keccak256("MAJORITY")) return new MajorityPolicy(threshold);
        if (k == keccak256("ROLE_CONSTRAINED")) {
            return new RoleConstrainedPolicy(threshold, [uint256(0), 1, 1, 1]);
        }
        revert(string.concat("Unknown POLICY: ", kind));
    }
}
