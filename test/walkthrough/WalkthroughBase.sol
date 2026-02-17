// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console2} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

import {SmartAccount7702} from "../../src/SmartAccount7702.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title WalkthroughBase
///
/// @notice Abstract base contract for walkthrough tests. Provides shared actors, contracts,
///         and helpers so the two walkthrough tests (with and without paymaster) stay DRY.
///
/// @dev Subclasses override `_buildUserOp` to customize gas parameters and paymaster usage,
///      then call the shared helpers to execute and verify the standard ERC-20 transfer flow.
abstract contract WalkthroughBase is Test {
    // -----------------------------------------------------------------------
    // Actors
    // -----------------------------------------------------------------------

    /// @dev The EOA's private key. In production, this lives in a hardware wallet
    ///      or browser extension. The key never leaves the signer's device.
    uint256 alicePrivateKey;

    /// @dev The EOA address derived from the private key.
    ///      After EIP-7702 delegation, this address has SmartAccount7702 code
    ///      but retains its own storage and ETH balance.
    address alice;

    /// @dev The recipient of the ERC-20 transfer.
    address bob = makeAddr("bob");

    /// @dev The bundler that submits UserOperations to the EntryPoint.
    ///      In production, this is an off-chain service (e.g., Pimlico, Alchemy).
    address bundler = makeAddr("bundler");

    // -----------------------------------------------------------------------
    // Contracts
    // -----------------------------------------------------------------------

    /// @dev The ERC-4337 EntryPoint singleton. Validates and executes UserOperations.
    ///      Deployed at the canonical address used by all ERC-4337 accounts.
    IEntryPoint entryPoint = IEntryPoint(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);

    /// @dev Alice's smart account — same address as `alice`, just cast to SmartAccount7702.
    SmartAccount7702 smartAccount;

    /// @dev A mock USDC token (6 decimals) used for the transfer demo.
    MockERC20 usdc;

    /// @dev The SmartAccount7702 implementation contract deployed once and shared.
    SmartAccount7702 implementation;

    // -----------------------------------------------------------------------
    // Shared setup helpers
    // -----------------------------------------------------------------------

    /// @dev Deploys the EntryPoint at its canonical address and the SmartAccount7702 implementation.
    function _deployInfrastructure() internal {
        (alice, alicePrivateKey) = makeAddrAndKey("alice");

        console2.log("--- STEP 1: Deploy infrastructure ---");

        EntryPoint ep = new EntryPoint();
        vm.etch(address(entryPoint), address(ep).code);
        console2.log("EntryPoint deployed at:", address(entryPoint));

        implementation = new SmartAccount7702();
        console2.log("Implementation deployed at:", address(implementation));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(alice, 1000e6);
        console2.log("USDC deployed at:", address(usdc));
        console2.log("Alice USDC balance:", usdc.balanceOf(alice));
    }

    /// @dev Simulates EIP-7702 delegation by copying the implementation bytecode onto Alice's EOA.
    function _delegateVia7702() internal {
        console2.log("");
        console2.log("--- STEP 2: EIP-7702 delegation ---");

        vm.etch(alice, address(implementation).code);
        smartAccount = SmartAccount7702(payable(alice));
        console2.log("Alice's EOA now has SmartAccount7702 code");
        console2.log("Alice's address:", alice);
        console2.log("Has code:", alice.code.length > 0);
    }

    /// @dev Calls initialize(entryPoint) to configure the account's trusted EntryPoint.
    ///      Pure setup — does not assert re-initialization behavior (see AttackTests for that).
    function _initializeAccount() internal {
        console2.log("");
        console2.log("--- STEP 3: Initialize ---");

        vm.prank(alice);
        smartAccount.initialize(address(entryPoint));
        console2.log("EntryPoint set to:", smartAccount.entryPoint());
    }

    /// @dev Encodes the callData for an ERC-20 transfer: execute(usdc.transfer(bob, 100 USDC)).
    function _encodeTransferCallData() internal view returns (bytes memory) {
        bytes memory transferCall = abi.encodeCall(usdc.transfer, (bob, 100e6));
        return abi.encodeCall(SmartAccount7702.execute, (address(usdc), 0, transferCall));
    }

    /// @dev Signs a UserOperation with Alice's private key. Returns the 65-byte ECDSA signature.
    function _signUserOp(PackedUserOperation memory userOp) internal view returns (bytes memory) {
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        console2.log("UserOp hash:", vm.toString(userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        console2.log("Signature length:", signature.length, "(expected: 65)");
        return signature;
    }

    /// @dev Submits a signed UserOperation to the EntryPoint via the bundler.
    function _submitUserOp(PackedUserOperation memory userOp) internal {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.prank(bundler, bundler);
        entryPoint.handleOps(ops, payable(bundler));
    }

    /// @dev Asserts that Alice sent 100 USDC to Bob and the nonce was consumed.
    function _verifyTransfer(uint256 aliceUsdcBefore, uint256 bobUsdcBefore) internal view {
        console2.log("");
        console2.log("--- Verify result ---");

        uint256 aliceUsdcAfter = usdc.balanceOf(alice);
        uint256 bobUsdcAfter = usdc.balanceOf(bob);

        console2.log("After transfer:");
        console2.log("  Alice USDC:", aliceUsdcAfter / 1e6);
        console2.log("  Bob USDC:  ", bobUsdcAfter / 1e6);

        assertEq(aliceUsdcAfter, aliceUsdcBefore - 100e6, "Alice should have 100 USDC less");
        assertEq(bobUsdcAfter, bobUsdcBefore + 100e6, "Bob should have 100 USDC more");

        uint256 newNonce = entryPoint.getNonce(alice, 0);
        assertEq(newNonce, 1, "Nonce should be incremented to 1");
        console2.log("Nonce after:", newNonce, "(replay-protected)");

        console2.log("");
        console2.log("=== Walkthrough complete ===");
    }
}
