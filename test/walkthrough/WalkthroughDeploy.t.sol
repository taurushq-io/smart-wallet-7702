// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {console2} from "forge-std/Test.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";
import {MockPaymaster} from "../mocks/MockPaymaster.sol";
import {WalkthroughBase} from "./WalkthroughBase.sol";

/// @dev A minimal contract that Alice will deploy from her smart wallet.
///      It stores the deployer (msg.sender) and an initial value.
///      This demonstrates that contracts deployed via the wallet have the EOA as their creator.
contract WalkthroughStorage {
    address public immutable DEPLOYER;
    uint256 public value;

    constructor(uint256 initialValue) {
        DEPLOYER = msg.sender;
        value = initialValue;
    }

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

/// @title WalkthroughDeployTest
///
/// @notice Walkthrough demonstrating deterministic contract deployment from TSmartAccount7702 via UserOperations.
///         Shows CREATE2 deployments with a paymaster covering gas.
///
/// @dev The wallet can deploy contracts because it has a native `deployDeterministic()` function that
///      executes the CREATE2 opcode. Since `address(this)` is the EOA under EIP-7702, the EOA is
///      recorded as the deployer (`msg.sender` in the child constructor).
///
///      This is useful for:
///        - Deploying token contracts owned by the wallet
///        - Deploying proxy contracts with deterministic addresses
///        - Factory patterns where the wallet acts as the deployer
///        - Cross-chain deployments at the same address
contract WalkthroughDeployTest is WalkthroughBase {
    MockPaymaster paymaster;

    function test_walkthrough_deployContract_CREATE2() public {
        // -------------------------------------------------------------------
        // STEP 1-3: Deploy infrastructure, delegate, initialize
        // -------------------------------------------------------------------
        _deployInfrastructure();
        _setupPaymaster();
        _delegateVia7702();
        _initializeAccount();

        // -------------------------------------------------------------------
        // STEP 4: Build the UserOp — deploy WalkthroughStorage via CREATE2
        //
        // CREATE2 gives a deterministic address based on:
        //   address = keccak256(0xff ++ deployer ++ salt ++ keccak256(creationCode))[12:]
        //
        // The deployer is address(this) = Alice's EOA.
        // This is useful when you need to know the address before deployment
        // (e.g., for cross-chain deployments at the same address, or for
        // pre-computing addresses in off-chain systems).
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 4: Build UserOp (CREATE2 deployment) ---");

        uint256 initialValue = 100;
        bytes32 salt = bytes32(uint256(0xdeadbeef));

        bytes memory creationCode = abi.encodePacked(
            type(WalkthroughStorage).creationCode,
            abi.encode(initialValue)
        );

        // Pre-compute the deterministic address BEFORE deployment
        // This is one of the key benefits of CREATE2
        address predictedAddr = computeCreate2Address(
            salt,
            keccak256(creationCode),
            alice // deployer = Alice's EOA under EIP-7702
        );
        console2.log("Predicted address:", predictedAddr);
        console2.log("Salt:", vm.toString(salt));
        assertTrue(predictedAddr.code.length == 0, "Address should be empty before deploy");

        // Encode: smartAccount.deployDeterministic(0, creationCode, salt)
        bytes memory deployCall = abi.encodeCall(
            TSmartAccount7702.deployDeterministic,
            (0, creationCode, salt)
        );

        PackedUserOperation memory userOp = _buildPaymasterUserOp(deployCall);

        // -------------------------------------------------------------------
        // STEP 5-6: Sign and submit
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 5: Sign UserOperation ---");
        userOp.signature = _signUserOp(userOp);

        console2.log("");
        console2.log("--- STEP 6: Submit to EntryPoint ---");
        _submitUserOp(userOp);

        // -------------------------------------------------------------------
        // STEP 7: Verify the deterministic deployment
        // -------------------------------------------------------------------
        console2.log("");
        console2.log("--- STEP 7: Verify deterministic deployment ---");

        // The deployed address MUST match our prediction
        assertTrue(predictedAddr.code.length > 0, "Contract should be deployed at predicted address");
        console2.log("Contract deployed at predicted address:", predictedAddr);

        WalkthroughStorage deployed = WalkthroughStorage(predictedAddr);
        assertEq(deployed.DEPLOYER(), alice, "Deployer should be Alice's EOA");
        assertEq(deployed.value(), initialValue, "Initial value should be 100");
        console2.log("DEPLOYER():", deployed.DEPLOYER(), "(= Alice)");
        console2.log("value():", deployed.value());

        console2.log("");
        console2.log("=== CREATE2 deployment walkthrough complete ===");
    }

    function test_walkthrough_deployAndInteract() public {
        // -------------------------------------------------------------------
        // Full flow: deploy a contract, then interact with it — all via UserOps
        //
        // This shows how a wallet can deploy a contract AND call it in
        // separate UserOperations.
        // -------------------------------------------------------------------
        _deployInfrastructure();
        _setupPaymaster();
        _delegateVia7702();
        _initializeAccount();

        // --- UserOp 1: Deploy WalkthroughStorage via CREATE2 ---
        console2.log("");
        console2.log("--- UserOp 1: Deploy contract (CREATE2) ---");

        uint256 initialValue = 1;
        bytes32 salt = bytes32(uint256(0xcafe));
        bytes memory creationCode = abi.encodePacked(
            type(WalkthroughStorage).creationCode,
            abi.encode(initialValue)
        );

        // Pre-compute the deterministic address
        address predicted = computeCreate2Address(salt, keccak256(creationCode), alice);

        bytes memory deployCall = abi.encodeCall(TSmartAccount7702.deployDeterministic, (0, creationCode, salt));
        PackedUserOperation memory userOp1 = _buildPaymasterUserOp(deployCall);
        userOp1.signature = _signUserOp(userOp1);
        _submitUserOp(userOp1);

        address deployed = predicted;
        assertEq(WalkthroughStorage(deployed).value(), 1, "Initial value should be 1");
        console2.log("Deployed at:", deployed, "with value:", WalkthroughStorage(deployed).value());

        // --- UserOp 2: Call setValue on the deployed contract ---
        console2.log("");
        console2.log("--- UserOp 2: Interact with deployed contract ---");

        bytes memory setValueCall = abi.encodeCall(WalkthroughStorage.setValue, (999));
        bytes memory executeCall = abi.encodeCall(
            TSmartAccount7702.execute,
            (deployed, 0, setValueCall)
        );

        // The EntryPoint nonce key stays 0; the sequence number auto-increments
        PackedUserOperation memory userOp2 = _buildPaymasterUserOp(executeCall);
        userOp2.signature = _signUserOp(userOp2);
        _submitUserOp(userOp2);

        assertEq(WalkthroughStorage(deployed).value(), 999, "Value should be updated to 999");
        console2.log("Value after update:", WalkthroughStorage(deployed).value());

        console2.log("");
        console2.log("=== Deploy + interact walkthrough complete ===");
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    function _setupPaymaster() internal {
        console2.log("");
        console2.log("--- Deploy & fund paymaster ---");

        paymaster = new MockPaymaster(entryPoint, address(this));
        paymaster.deposit{value: 10 ether}();
        paymaster.addStake{value: 1 ether}(1);
        console2.log("Paymaster deployed and funded at:", address(paymaster));
    }

    function _buildPaymasterUserOp(bytes memory callData) internal view returns (PackedUserOperation memory) {
        return _buildPaymasterUserOpWithNonce(callData, 0);
    }

    function _buildPaymasterUserOpWithNonce(bytes memory callData, uint192 nonceKey)
        internal
        view
        returns (PackedUserOperation memory)
    {
        bytes memory paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(500_000),  // paymaster verification gas
            uint128(50_000)    // paymaster post-op gas
        );

        return PackedUserOperation({
            sender: alice,
            nonce: entryPoint.getNonce(alice, nonceKey),
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(500_000) << 128 | uint256(2_000_000)),
            preVerificationGas: 50_000,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(10 gwei)),
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }
}
