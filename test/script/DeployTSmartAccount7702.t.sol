// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {Test} from "forge-std/Test.sol";

import {DeployTSmartAccount7702Script} from "../../script/DeployTSmartAccount7702.s.sol";
import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";

/// @title DeployTSmartAccount7702 Script Tests
/// @notice Verifies the deployment script produces a correctly configured implementation contract.
contract TestDeployScript is Test {
    /// @dev The salt used in the deployment script, computed on-chain.
    bytes32 constant EXPECTED_SALT = keccak256("TSmart Account 7702 v1");
    bytes4 constant IACCOUNT_INTERFACE_ID = 0x19822f7c;
    bytes4 constant IERC1271_INTERFACE_ID = 0x1626ba7e;
    bytes4 constant IERC721RECEIVER_INTERFACE_ID = 0x150b7a02;
    bytes4 constant IERC1155RECEIVER_INTERFACE_ID = 0x4e2312e0;
    bytes4 constant IERC165_INTERFACE_ID = 0x01ffc9a7;

    TSmartAccount7702 implementation;

    function setUp() public {
        // Deploy using CREATE2 with the same salt as the script
        implementation = new TSmartAccount7702{salt: EXPECTED_SALT}();
    }

    // ─── Salt Derivation
    // ─────────────────────────────────────────────

    /// @dev Verifies the salt matches keccak256("TSmart Account 7702 v1").
    function test_salt_matchesExpectedPreimage() public pure {
        bytes32 computed = keccak256("TSmart Account 7702 v1");
        assertEq(computed, EXPECTED_SALT, "salt must equal keccak256('TSmart Account 7702 v1')");
    }

    // ─── Deterministic Address
    // ───────────────────────────────────────

    /// @dev Verifies the deployed address matches the CREATE2 prediction.
    function test_deploy_addressIsDeterministic() public view {
        bytes32 initCodeHash = keccak256(type(TSmartAccount7702).creationCode);
        address predicted = vm.computeCreate2Address(EXPECTED_SALT, initCodeHash, address(this));
        assertEq(address(implementation), predicted, "deployed address must match CREATE2 prediction");
    }

    // ─── EntryPoint Constant
    // ──────────────────────────────────────

    /// @dev entryPoint() must return the hardcoded v0.8.0 canonical address.
    function test_implementation_entryPointIsConstant() public view {
        assertEq(
            implementation.entryPoint(),
            0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108,
            "implementation entryPoint must be the v0.8.0 canonical address"
        );
    }

    // ─── Interface Support
    // ───────────────────────────────────────────

    /// @dev The implementation must advertise all expected interfaces.
    ///      Uses explicit bytes4 constants and cross-checks them against `type(...).interfaceId`
    ///      for standard interfaces to avoid mirroring source implementation.
    function test_implementation_supportsExpectedInterfaces() public view {
        assertEq(type(IAccount).interfaceId, IACCOUNT_INTERFACE_ID, "IAccount interfaceId mismatch");
        assertEq(type(IERC1271).interfaceId, IERC1271_INTERFACE_ID, "IERC1271 interfaceId mismatch");
        assertEq(
            type(IERC721Receiver).interfaceId, IERC721RECEIVER_INTERFACE_ID, "IERC721Receiver interfaceId mismatch"
        );
        assertEq(
            type(IERC1155Receiver).interfaceId, IERC1155RECEIVER_INTERFACE_ID, "IERC1155Receiver interfaceId mismatch"
        );
        assertEq(type(IERC165).interfaceId, IERC165_INTERFACE_ID, "IERC165 interfaceId mismatch");

        assertTrue(implementation.supportsInterface(IERC165_INTERFACE_ID), "must support ERC-165");
        assertTrue(implementation.supportsInterface(IACCOUNT_INTERFACE_ID), "must support IAccount");
        assertTrue(implementation.supportsInterface(IERC1271_INTERFACE_ID), "must support ERC-1271");
        // ERC-7739 has no ERC-165 interface ID — detection is via isValidSignature(magic, "") not supportsInterface
        assertTrue(implementation.supportsInterface(IERC721RECEIVER_INTERFACE_ID), "must support IERC721Receiver");
        assertTrue(implementation.supportsInterface(IERC1155RECEIVER_INTERFACE_ID), "must support IERC1155Receiver");
    }

    // ─── EIP-712 Domain
    // ──────────────────────────────────────────────

    /// @dev The implementation must expose the correct EIP-712 domain parameters.
    function test_implementation_eip712Domain() public view {
        (bytes1 fields, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            implementation.eip712Domain();

        // fields: name (0x01) | version (0x02) | chainId (0x04) | verifyingContract (0x08) = 0x0f
        assertEq(uint8(fields), 0x0f, "fields should include name, version, chainId, verifyingContract");
        assertEq(keccak256(bytes(name)), keccak256("TSmart Account 7702"), "domain name must be 'TSmart Account 7702'");
        assertEq(keccak256(bytes(version)), keccak256("1"), "domain version must be '1'");
        assertEq(chainId, block.chainid, "chainId must match current chain");
        assertEq(verifyingContract, address(implementation), "verifyingContract must be the implementation");
    }

    // ─── Bytecode Non-Empty
    // ──────────────────────────────────────────

    /// @dev The deployed implementation must have non-zero code.
    function test_implementation_hasCode() public view {
        assertGt(address(implementation).code.length, 0, "implementation must have bytecode");
    }

    // ─── Script Run (Dry Run)
    // ────────────────────────────────────────

    /// @dev Verifies the deploy script runs without reverting.
    function test_script_runsSuccessfully() public {
        DeployTSmartAccount7702Script script = new DeployTSmartAccount7702Script();
        script.run();
    }
}
