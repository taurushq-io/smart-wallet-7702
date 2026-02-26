// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {console2} from "forge-std/Test.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

import {MockPaymaster} from "../mocks/MockPaymaster.sol";
import {WalkthroughBase} from "./WalkthroughBase.sol";

/// @title WalkthroughPaymasterTest
///
/// @notice Production-realistic walkthrough: ERC-20 transfer via ERC-4337 with a paymaster
///         covering all gas costs. This is the intended usage of TSmartAccount7702.
///
/// @dev This test extends the simple walkthrough by adding the paymaster flow:
///
///      1. Deploy infrastructure (EntryPoint, implementation, USDC)
///      2. Deploy and fund a paymaster (deposit ETH + stake in the EntryPoint)
///      3. EOA delegates its code via EIP-7702 and initializes
///      4. Build a UserOperation with realistic gas fees AND paymasterAndData
///      5. Sign and submit — the paymaster pays gas, Alice keeps all her ETH
///      6. Verify the transfer AND that the paymaster's deposit was charged
///
///      The paymasterAndData field is packed as:
///        [0:20]  — paymaster address (20 bytes)
///        [20:36] — paymaster verification gas limit (uint128, 16 bytes)
///        [36:52] — paymaster post-op gas limit (uint128, 16 bytes)
///        [52:]   — paymaster-specific data (empty for our accept-all mock)
contract WalkthroughPaymasterTest is WalkthroughBase {
    MockPaymaster paymaster;

    function test_walkthrough_erc20Transfer_withPaymaster() public {
        // -------------------------------------------------------------------
        // STEP 1: Deploy infrastructure
        // -------------------------------------------------------------------
        _deployInfrastructure();

        // -------------------------------------------------------------------
        // STEP 2: Deploy and fund the paymaster
        //
        // A paymaster is a contract that agrees to pay gas on behalf of users.
        // In production, Circle's USDC Paymaster charges users in USDC and
        // pays ETH gas to the EntryPoint. Our mock accepts all UserOps for free.
        //
        // The paymaster must:
        //   a) Deposit ETH into the EntryPoint (used to pay gas)
        //   b) Stake ETH in the EntryPoint (required by the protocol to prevent
        //      abuse — paymasters can access global state, so they need skin in the game)
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 2: Deploy & fund paymaster ---");

        address paymasterOwner = address(this);
        paymaster = new MockPaymaster(entryPoint, paymasterOwner);
        console2.log("Paymaster deployed at:", address(paymaster));

        // Deposit ETH — this is the balance the EntryPoint draws from to pay gas
        paymaster.deposit{value: 10 ether}();
        uint256 paymasterDeposit = paymaster.getDeposit();
        console2.log("Paymaster deposit:", paymasterDeposit / 1 ether, "ETH");

        // Stake ETH — required by ERC-4337 for entities that access global state.
        // The unstake delay (1 second here, longer in production) prevents instant exit.
        paymaster.addStake{value: 1 ether}(1);
        console2.log("Paymaster staked: 1 ETH (unstake delay: 1s)");

        // -------------------------------------------------------------------
        // STEP 3–4: Delegate via EIP-7702 and initialize
        // -------------------------------------------------------------------
        _delegateVia7702();
        _initializeAccount();

        // -------------------------------------------------------------------
        // STEP 5: Build the UserOperation with paymaster
        //
        // Unlike the simple walkthrough, this UserOp has:
        //   - Realistic gas fees (maxFeePerGas, maxPriorityFeePerGas)
        //   - paymasterAndData pointing to our MockPaymaster
        //
        // The paymasterAndData field tells the EntryPoint:
        //   "This paymaster agreed to sponsor this UserOp. Call its
        //    validatePaymasterUserOp to confirm, then charge its deposit."
        //
        // Because the paymaster pays, missingAccountFunds = 0 for the account.
        // This is exactly what TSmartAccount7702 is designed for.
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 5: Build UserOperation (with paymaster) ---");

        bytes memory executeCall = _encodeTransferCallData();

        // Pack paymasterAndData: address (20) + verificationGasLimit (16) + postOpGasLimit (16)
        uint128 paymasterVerificationGas = 200_000;
        uint128 paymasterPostOpGas = 50_000;
        bytes memory paymasterAndData = abi.encodePacked(
            address(paymaster),       // 20 bytes: paymaster address
            paymasterVerificationGas, // 16 bytes: gas for validatePaymasterUserOp
            paymasterPostOpGas        // 16 bytes: gas for postOp (if context is returned)
        );

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: alice,
            nonce: entryPoint.getNonce(alice, 0),
            initCode: "",
            callData: executeCall,
            accountGasLimits: bytes32(
                uint256(200_000) << 128      // verificationGasLimit
                | uint256(200_000)           // callGasLimit
            ),
            preVerificationGas: 50_000,
            gasFees: bytes32(
                uint256(1 gwei) << 128       // maxPriorityFeePerGas
                | uint256(10 gwei)           // maxFeePerGas
            ),
            paymasterAndData: paymasterAndData,
            signature: ""
        });

        console2.log("UserOp built (with paymaster, realistic gas):");
        console2.log("  sender:", userOp.sender);
        console2.log("  nonce:", userOp.nonce);
        console2.log("  maxFeePerGas: 10 gwei");
        console2.log("  paymaster:", address(paymaster));
        console2.log("  paymasterAndData length:", userOp.paymasterAndData.length);

        // -------------------------------------------------------------------
        // STEP 6: Sign the UserOperation
        //
        // The signature covers the entire UserOp including paymasterAndData.
        // This means Alice explicitly consents to this specific paymaster
        // sponsoring her operation. A different paymaster would change the hash.
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 6: Sign UserOperation ---");
        userOp.signature = _signUserOp(userOp);

        // -------------------------------------------------------------------
        // STEP 7: Submit to the EntryPoint
        //
        // The EntryPoint executes the following sequence:
        //   1. validateUserOp()          — account verifies Alice's signature
        //   2. validatePaymasterUserOp() — paymaster agrees to pay (returns 0)
        //   3. execute()                 — the USDC transfer happens
        //   4. postOp()                  — paymaster post-processing (no-op here)
        //   5. Gas accounting            — EntryPoint deducts gas from paymaster deposit
        //
        // Alice pays ZERO ETH. The paymaster's deposit covers everything.
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 7: Submit to EntryPoint (paymaster pays gas) ---");

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        uint256 aliceEthBefore = alice.balance;
        uint256 paymasterDepositBefore = paymaster.getDeposit();

        console2.log("Before:");
        console2.log("  Alice USDC:", aliceUsdcBefore / 1e6);
        console2.log("  Bob USDC:  ", bobUsdcBefore / 1e6);
        console2.log("  Alice ETH: ", aliceEthBefore);
        console2.log("  Paymaster deposit:", paymasterDepositBefore / 1 ether, "ETH");

        _submitUserOp(userOp);

        // -------------------------------------------------------------------
        // STEP 8: Verify the result
        //
        // Check three things:
        //   a) The USDC transfer succeeded (Alice → Bob)
        //   b) Alice's ETH balance is unchanged (paymaster paid gas)
        //   c) The paymaster's deposit decreased (it paid for the gas)
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 8: Verify result ---");

        uint256 aliceUsdcAfter = usdc.balanceOf(alice);
        uint256 bobUsdcAfter = usdc.balanceOf(bob);
        uint256 aliceEthAfter = alice.balance;
        uint256 paymasterDepositAfter = paymaster.getDeposit();

        console2.log("After:");
        console2.log("  Alice USDC:", aliceUsdcAfter / 1e6);
        console2.log("  Bob USDC:  ", bobUsdcAfter / 1e6);
        console2.log("  Alice ETH: ", aliceEthAfter);
        console2.log("  Paymaster deposit:", paymasterDepositAfter / 1 ether, "ETH");

        // a) USDC transfer succeeded
        assertEq(aliceUsdcAfter, aliceUsdcBefore - 100e6, "Alice should have 100 USDC less");
        assertEq(bobUsdcAfter, bobUsdcBefore + 100e6, "Bob should have 100 USDC more");

        // b) Alice paid ZERO ETH for gas — the paymaster covered it
        assertEq(aliceEthAfter, aliceEthBefore, "Alice ETH should be unchanged (paymaster paid)");
        console2.log("Alice ETH unchanged -- paymaster sponsored the gas!");

        // c) Paymaster deposit decreased (it paid the gas)
        uint256 gasSpent = paymasterDepositBefore - paymasterDepositAfter;
        assertGt(gasSpent, 0, "Paymaster deposit should decrease");
        console2.log("Paymaster gas cost:", gasSpent, "wei");

        // d) Nonce consumed (replay protection)
        uint256 newNonce = entryPoint.getNonce(alice, 0);
        assertEq(newNonce, 1, "Nonce should be incremented to 1");
        console2.log("Nonce after:", newNonce, "(replay-protected)");

        console2.log("");
        console2.log("=== Walkthrough with paymaster complete ===");
    }
}
