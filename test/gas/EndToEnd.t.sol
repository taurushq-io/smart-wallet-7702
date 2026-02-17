// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {console2} from "forge-std/Test.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

import {SmartAccount7702} from "../../src/SmartAccount7702.sol";
import {MockERC20} from "../../lib/solady/test/utils/mocks/MockERC20.sol";

import {MockTarget} from "../mocks/MockTarget.sol";
import {SmartWalletTestBase} from "../SmartAccount7702/SmartWalletTestBase.sol";

/// @title EndToEndTest
/// @notice Gas comparison tests between ERC-4337 Base Account and EOA transactions
/// @dev Isolated test contract to measure gas consumption for common operations
/// Tests ran using `FOUNDRY_PROFILE=deploy` to simulate real-world gas costs
/// forge-config: default.isolate = true
contract EndToEndTest is SmartWalletTestBase {
    address eoaUser = address(0xe0a);
    MockERC20 usdc;
    MockTarget target;

    function setUp() public override {
        // Deploy EntryPoint at canonical address
        EntryPoint ep = new EntryPoint();
        vm.etch(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108, address(ep).code);

        // Simulate EIP-7702 delegation
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);
        SmartAccount7702 impl = new SmartAccount7702(address(entryPoint));
        vm.etch(signer, address(impl).code);
        account = SmartAccount7702(payable(signer));

        // Fund wallets with ETH
        vm.deal(address(account), 100 ether);
        vm.deal(eoaUser, 100 ether);

        // Deploy and mint USDC tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(address(account), 10000e6);
        usdc.mint(eoaUser, 10000e6);

        target = new MockTarget();
    }

    // Native ETH Transfer - Base Account
    function test_transfer_native_baseAccount() public {
        // Dust recipient to avoid gas changes for first non-zero balance
        vm.deal(address(0x1234), 1 wei);
        uint256 recipientBefore = address(0x1234).balance;

        // Prepare UserOperation for native ETH transfer
        userOpCalldata = abi.encodeCall(SmartAccount7702.execute, (address(0x1234), 1 ether, ""));
        PackedUserOperation memory op = _getUserOpWithSignature();

        // Measure calldata size
        bytes memory handleOpsCalldata = abi.encodeCall(entryPoint.handleOps, (_makeOpsArray(op), payable(bundler)));
        console2.log("test_transfer_native Base Account calldata size:", handleOpsCalldata.length);

        // Execute and measure gas
        vm.startSnapshotGas("e2e_transfer_native_baseAccount");
        _sendUserOperation(op);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("test_transfer_native Base Account gas:", gasUsed);

        assertEq(address(0x1234).balance, recipientBefore + 1 ether);
    }

    // Native ETH Transfer - EOA
    function test_transfer_native_eoa() public {
        // Dust recipient to avoid gas changes for first non-zero balance
        vm.deal(address(0x1234), 1 wei);
        uint256 recipientBefore = address(0x1234).balance;

        console2.log("test_transfer_native EOA calldata size:", uint256(0));

        // Execute and measure gas
        vm.prank(eoaUser);
        vm.startSnapshotGas("e2e_transfer_native_eoa");
        payable(address(0x1234)).transfer(1 ether);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("test_transfer_native EOA gas:", gasUsed);

        assertEq(address(0x1234).balance, recipientBefore + 1 ether);
    }

    // ERC20 Transfer - Base Account
    function test_transfer_erc20_baseAccount() public {
        // Dust recipient to avoid gas changes for first non-zero balance
        vm.deal(address(0x5678), 1 wei);
        usdc.mint(address(0x5678), 1 wei);
        uint256 recipientBefore = usdc.balanceOf(address(0x5678));

        // Prepare UserOperation for ERC20 transfer
        userOpCalldata = abi.encodeCall(
            SmartAccount7702.execute, (address(usdc), 0, abi.encodeCall(usdc.transfer, (address(0x5678), 100e6)))
        );
        PackedUserOperation memory op = _getUserOpWithSignature();

        // Measure calldata size
        bytes memory handleOpsCalldata = abi.encodeCall(entryPoint.handleOps, (_makeOpsArray(op), payable(bundler)));
        console2.log("test_transfer_erc20 Base Account calldata size:", handleOpsCalldata.length);

        // Execute and measure gas
        vm.startSnapshotGas("e2e_transfer_erc20_baseAccount");
        _sendUserOperation(op);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("test_transfer_erc20 Base Account gas:", gasUsed);

        assertEq(usdc.balanceOf(address(0x5678)), recipientBefore + 100e6);
    }

    // ERC20 Transfer - EOA
    function test_transfer_erc20_eoa() public {
        // Dust recipient to avoid gas changes for first non-zero balance
        vm.deal(address(0x5678), 1 wei);
        usdc.mint(address(0x5678), 1 wei);
        uint256 recipientBefore = usdc.balanceOf(address(0x5678));

        // Measure calldata size
        bytes memory eoaCalldata = abi.encodeCall(usdc.transfer, (address(0x5678), 100e6));
        console2.log("test_transfer_erc20 EOA calldata size:", eoaCalldata.length);

        // Execute and measure gas
        vm.prank(eoaUser);
        vm.startSnapshotGas("e2e_transfer_erc20_eoa");
        usdc.transfer(address(0x5678), 100e6);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("test_transfer_erc20 EOA gas:", gasUsed);

        assertEq(usdc.balanceOf(address(0x5678)), recipientBefore + 100e6);
    }

    // Helper Functions
    // Creates an array containing a single PackedUserOperation
    function _makeOpsArray(PackedUserOperation memory op) internal pure returns (PackedUserOperation[] memory) {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        return ops;
    }
}
