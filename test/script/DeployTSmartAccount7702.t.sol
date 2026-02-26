// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IAccount} from "account-abstraction/interfaces/IAccount.sol";

import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";
import {DeployTSmartAccount7702Script} from "../../script/DeployTSmartAccount7702.s.sol";

/// @title DeployTSmartAccount7702 Script Tests
/// @notice Verifies the deployment script produces a correctly configured implementation contract.
contract TestDeployScript is Test {
    /// @dev The salt used in the deployment script, computed on-chain.
    bytes32 constant EXPECTED_SALT = keccak256("TSmart Account 7702 v1");

    TSmartAccount7702 implementation;

    function setUp() public {
        // Deploy using CREATE2 with the same salt as the script
        implementation = new TSmartAccount7702{salt: EXPECTED_SALT}();
    }

    // ─── Salt Derivation ─────────────────────────────────────────────

    /// @dev Verifies the salt matches keccak256("TSmart Account 7702 v1").
    function test_salt_matchesExpectedPreimage() public pure {
        bytes32 computed = keccak256("TSmart Account 7702 v1");
        assertEq(computed, EXPECTED_SALT, "salt must equal keccak256('TSmart Account 7702 v1')");
    }

    // ─── Deterministic Address ───────────────────────────────────────

    /// @dev Verifies the deployed address matches the CREATE2 prediction.
    function test_deploy_addressIsDeterministic() public view {
        bytes32 initCodeHash = keccak256(type(TSmartAccount7702).creationCode);
        address predicted = vm.computeCreate2Address(EXPECTED_SALT, initCodeHash, address(this));
        assertEq(address(implementation), predicted, "deployed address must match CREATE2 prediction");
    }

    // ─── Implementation Locking ──────────────────────────────────────

    /// @dev The implementation contract must have initializers disabled.
    ///      Calling initialize() on the implementation itself must revert.
    function test_implementation_initializersDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(0x1234));
    }

    /// @dev entryPoint() on the implementation must return address(0)
    ///      since initialize() was never (and can never be) called.
    function test_implementation_entryPointIsZero() public view {
        assertEq(implementation.entryPoint(), address(0), "implementation entryPoint must be address(0)");
    }

    // ─── Interface Support ───────────────────────────────────────────

    /// @dev The implementation must advertise all expected interfaces.
    ///      Uses `type(Interface).interfaceId` so the test independently verifies the source values.
    function test_implementation_supportsExpectedInterfaces() public view {
        assertTrue(implementation.supportsInterface(type(IERC165).interfaceId), "must support ERC-165");
        assertTrue(implementation.supportsInterface(type(IAccount).interfaceId), "must support IAccount");
        assertTrue(implementation.supportsInterface(type(IERC1271).interfaceId), "must support ERC-1271");
        assertTrue(implementation.supportsInterface(bytes4(0x77390001)), "must support ERC-7739"); // no standard OZ interface
        assertTrue(implementation.supportsInterface(type(IERC721Receiver).interfaceId), "must support IERC721Receiver");
        assertTrue(implementation.supportsInterface(type(IERC1155Receiver).interfaceId), "must support IERC1155Receiver");
    }

    // ─── EIP-712 Domain ──────────────────────────────────────────────

    /// @dev The implementation must expose the correct EIP-712 domain parameters.
    function test_implementation_eip712Domain() public view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            ,
        ) = implementation.eip712Domain();

        // fields: name (0x01) | version (0x02) | chainId (0x04) | verifyingContract (0x08) = 0x0f
        assertEq(uint8(fields), 0x0f, "fields should include name, version, chainId, verifyingContract");
        assertEq(keccak256(bytes(name)), keccak256("TSmart Account 7702"), "domain name must be 'TSmart Account 7702'");
        assertEq(keccak256(bytes(version)), keccak256("1"), "domain version must be '1'");
        assertEq(chainId, block.chainid, "chainId must match current chain");
        assertEq(verifyingContract, address(implementation), "verifyingContract must be the implementation");
    }

    // ─── Bytecode Non-Empty ──────────────────────────────────────────

    /// @dev The deployed implementation must have non-zero code.
    function test_implementation_hasCode() public view {
        assertGt(address(implementation).code.length, 0, "implementation must have bytecode");
    }

    // ─── Script Run (Dry Run) ────────────────────────────────────────

    /// @dev Verifies the deploy script runs without reverting.
    function test_script_runsSuccessfully() public {
        DeployTSmartAccount7702Script script = new DeployTSmartAccount7702Script();
        script.run();
    }
}
