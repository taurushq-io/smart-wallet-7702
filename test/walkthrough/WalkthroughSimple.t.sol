// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {console2} from "forge-std/Test.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

import {WalkthroughBase} from "./WalkthroughBase.sol";

/// @title WalkthroughSimpleTest
///
/// @notice Step-by-step walkthrough of the SmartAccount7702 lifecycle — simplified version.
///         Demonstrates wallet creation and an ERC-20 transfer via ERC-4337 UserOperations
///         WITHOUT a paymaster. Gas fees are set to 0 to bypass prefund requirements.
///
/// @dev The flow demonstrated here:
///
///      1. Deploy the EntryPoint singleton and the SmartAccount7702 implementation
///      2. An EOA delegates its code to SmartAccount7702 via EIP-7702
///      3. The EOA calls initialize(entryPoint) to configure its trusted EntryPoint
///      4. A dApp builds a UserOperation for an ERC-20 transfer (gasFees = 0)
///      5. The EOA's private key signs the UserOperation hash
///      6. A bundler submits the UserOperation to the EntryPoint
///      7. The EntryPoint validates the signature and executes the transfer
///
///      Gas fees are set to 0 in this simplified walkthrough to bypass prefund requirements.
///      The account supports both self-funded and paymaster-sponsored UserOperations.
///      See WalkthroughPaymasterTest for the production-realistic version with a paymaster.
contract WalkthroughSimpleTest is WalkthroughBase {
    function test_walkthrough_erc20Transfer_simple() public {
        // -------------------------------------------------------------------
        // STEP 1–3: Deploy, delegate, initialize
        // -------------------------------------------------------------------
        _deployInfrastructure();
        _delegateVia7702();
        _initializeAccount();

        // -------------------------------------------------------------------
        // STEP 4: Build the UserOperation
        //
        // A dApp constructs a UserOperation encoding: execute(usdc.transfer(bob, 100 USDC)).
        //
        // Gas fees are 0 in this simplified walkthrough to avoid prefund requirements.
        // Setting gasFees = 0 means requiredPrefund = gasLimits * maxFeePerGas = 0,
        // so the EntryPoint won't require the account to pay for gas.
        // In production, either a paymaster covers gas or the account self-funds.
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 4: Build UserOperation (no paymaster) ---");

        bytes memory executeCall = _encodeTransferCallData();

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: alice,
            nonce: entryPoint.getNonce(alice, 0),
            initCode: "",
            callData: executeCall,
            accountGasLimits: bytes32(uint256(1_000_000) << 128 | uint256(1_000_000)),
            preVerificationGas: 0,
            gasFees: bytes32(0),             // No gas fees — simplified walkthrough
            paymasterAndData: "",            // No paymaster in this simplified version
            signature: ""
        });

        console2.log("UserOp built (gasFees = 0, no paymaster):");
        console2.log("  sender:", userOp.sender);
        console2.log("  nonce:", userOp.nonce);

        // -------------------------------------------------------------------
        // STEP 5: Sign the UserOperation
        //
        // The EntryPoint computes a hash of the UserOperation (including the
        // EntryPoint address and chain ID for replay protection). Alice signs
        // this hash with her private key — a raw 65-byte ECDSA signature (r, s, v).
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 5: Sign UserOperation ---");
        userOp.signature = _signUserOp(userOp);

        // -------------------------------------------------------------------
        // STEP 6: Submit to the EntryPoint
        //
        // The bundler submits the signed UserOp. The EntryPoint:
        //   a) Calls validateUserOp() — verifies ECDSA signature matches address(this)
        //   b) Calls execute() with the encoded usdc.transfer callData
        //   c) No gas charge (gasFees = 0)
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 6: Submit to EntryPoint ---");

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        console2.log("Before: Alice USDC:", aliceUsdcBefore / 1e6);
        console2.log("Before: Bob USDC:  ", bobUsdcBefore / 1e6);

        _submitUserOp(userOp);

        // -------------------------------------------------------------------
        // STEP 7: Verify the result
        // -------------------------------------------------------------------
        _verifyTransfer(aliceUsdcBefore, bobUsdcBefore);
    }
}
