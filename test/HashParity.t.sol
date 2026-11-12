// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CredentialFixture} from "./utils/CredentialFixture.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";

/// @notice Cross-language check: commitments computed off-chain by
///         experiments/credentials.py must equal CredentialRegistry.computeCommitment,
///         and every synthetic credential must issue and verify end to end.
contract HashParityTest is CredentialFixture {
    string internal constant DATASET = "data/synthetic_credentials.json";

    function setUp() public {
        _deploy(_roleConstrained());
    }

    function test_PythonCommitmentsMatchSolidity() public {
        string memory json = vm.readFile(DATASET);
        uint256 n;
        for (; vm.keyExistsJson(json, _key(n, "")); ++n) {
            string memory docJson = vm.parseJsonString(json, _key(n, ".documentJson"));
            bytes32 salt = vm.parseJsonBytes32(json, _key(n, ".salt"));
            bytes32 docHash = vm.parseJsonBytes32(json, _key(n, ".documentHash"));
            bytes32 expected = vm.parseJsonBytes32(json, _key(n, ".commitment"));

            assertEq(keccak256(bytes(docJson)), docHash, "document hash mismatch");
            bytes32 c = registry.computeCommitment(docHash, salt);
            assertEq(c, expected, "commitment mismatch");

            _issue(c, _validQuorum());
            CredentialRegistry.VerificationResult memory v = registry.verifyDocument(docHash, salt);
            assertEq(uint8(v.status), uint8(CredentialRegistry.VerificationStatus.Valid));
        }
        assertGt(n, 0, "dataset empty: run python experiments/credentials.py");
    }

    function _key(uint256 i, string memory field) internal pure returns (string memory) {
        return string.concat(".credentials[", vm.toString(i), "]", field);
    }
}
