// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {console2} from "forge-std/Test.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

import {SmartAccount7702} from "../../src/SmartAccount7702.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPaymaster} from "../mocks/MockPaymaster.sol";
import {MockTarget} from "../mocks/MockTarget.sol";
import {SmartWalletTestBase} from "../SmartAccount7702/SmartWalletTestBase.sol";

/// @title EndToEndPaymasterTest
/// @notice Gas profiling with a paymaster — reflects production costs more accurately
///         than EndToEnd.t.sol (which uses gasFees=0 and no paymaster).
/// @dev forge-config: default.isolate = true
contract EndToEndPaymasterTest is SmartWalletTestBase {
    address eoaUser = address(0xe0a);
    MockERC20 usdc;
    MockTarget target;
    MockPaymaster paymaster;

    address paymasterOwner = address(uint160(uint256(keccak256("paymasterOwner"))));

    function setUp() public override {
        // Deploy EntryPoint at canonical address
        EntryPoint ep = new EntryPoint();
        vm.etch(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108, address(ep).code);

        // Simulate EIP-7702 delegation
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);
        SmartAccount7702 impl = new SmartAccount7702();
        vm.etch(signer, address(impl).code);
        account = SmartAccount7702(payable(signer));
        vm.prank(signer);
        account.initialize(address(entryPoint));

        // Fund wallets with ETH
        vm.deal(address(account), 100 ether);
        vm.deal(eoaUser, 100 ether);
        vm.deal(paymasterOwner, 100 ether);

        // Deploy and mint USDC tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(address(account), 10000e6);
        usdc.mint(eoaUser, 10000e6);

        target = new MockTarget();

        // Deploy and fund the paymaster
        paymaster = new MockPaymaster(IEntryPoint(address(entryPoint)), paymasterOwner);
        vm.startPrank(paymasterOwner);
        entryPoint.depositTo{value: 10 ether}(address(paymaster));
        paymaster.addStake{value: 1 ether}(1);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    //  Native ETH Transfer — with paymaster
    // -----------------------------------------------------------------------

    function test_transfer_native_withPaymaster() public {
        vm.deal(address(0x1234), 1 wei);
        uint256 recipientBefore = address(0x1234).balance;

        PackedUserOperation memory op = _buildPaymasterOp(
            abi.encodeCall(SmartAccount7702.execute, (address(0x1234), 1 ether, ""))
        );

        bytes memory handleOpsCalldata = abi.encodeCall(entryPoint.handleOps, (_makeOpsArray(op), payable(bundler)));
        console2.log("test_transfer_native Paymaster calldata size:", handleOpsCalldata.length);

        vm.startSnapshotGas("e2e_transfer_native_paymaster");
        _sendUserOperation(op);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("test_transfer_native Paymaster gas:", gasUsed);

        assertEq(address(0x1234).balance, recipientBefore + 1 ether);
    }

    // -----------------------------------------------------------------------
    //  ERC-20 Transfer — with paymaster
    // -----------------------------------------------------------------------

    function test_transfer_erc20_withPaymaster() public {
        vm.deal(address(0x5678), 1 wei);
        usdc.mint(address(0x5678), 1 wei);
        uint256 recipientBefore = usdc.balanceOf(address(0x5678));

        PackedUserOperation memory op = _buildPaymasterOp(
            abi.encodeCall(
                SmartAccount7702.execute, (address(usdc), 0, abi.encodeCall(usdc.transfer, (address(0x5678), 100e6)))
            )
        );

        bytes memory handleOpsCalldata = abi.encodeCall(entryPoint.handleOps, (_makeOpsArray(op), payable(bundler)));
        console2.log("test_transfer_erc20 Paymaster calldata size:", handleOpsCalldata.length);

        vm.startSnapshotGas("e2e_transfer_erc20_paymaster");
        _sendUserOperation(op);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("test_transfer_erc20 Paymaster gas:", gasUsed);

        assertEq(usdc.balanceOf(address(0x5678)), recipientBefore + 100e6);
    }

    // -----------------------------------------------------------------------
    //  Helpers
    // -----------------------------------------------------------------------

    /// @dev Builds a UserOp with paymaster, realistic gas limits, and a valid signature.
    function _buildPaymasterOp(bytes memory callData_) internal view returns (PackedUserOperation memory op) {
        // Realistic gas limits
        uint128 verificationGasLimit = 500_000;
        uint128 callGasLimit = 500_000;
        uint128 paymasterVerificationGasLimit = 100_000;
        uint128 paymasterPostOpGasLimit = 50_000;

        // paymasterAndData = paymaster address (20 bytes) + verificationGasLimit (16 bytes) + postOpGasLimit (16 bytes)
        bytes memory paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(paymasterVerificationGasLimit),
            uint128(paymasterPostOpGasLimit)
        );

        op = PackedUserOperation({
            sender: address(account),
            nonce: entryPoint.getNonce(address(account), 0),
            initCode: "",
            callData: callData_,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit)),
            preVerificationGas: 50_000,
            gasFees: bytes32(uint256(uint128(1 gwei)) << 128 | uint256(uint128(30 gwei))),
            paymasterAndData: paymasterAndData,
            signature: ""
        });

        // Sign
        bytes32 userOpHash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, userOpHash);
        op.signature = abi.encodePacked(r, s, v);
    }

    function _makeOpsArray(PackedUserOperation memory op) internal pure returns (PackedUserOperation[] memory) {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        return ops;
    }
}
