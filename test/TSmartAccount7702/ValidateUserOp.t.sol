// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MockEntryPoint} from "../mocks/MockEntryPoint.sol";
import {UseEntryPointV09} from "./entrypoint/UseEntryPointV09.sol";
import {SmartWalletTestBase} from "./SmartWalletTestBase.sol";
import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @dev Abstract test logic for validateUserOp(). Concrete classes provide the EntryPoint version.
abstract contract TestValidateUserOpBase is SmartWalletTestBase {
    struct TestTemps {
        bytes32 userOpHash;
        address signer;
        uint256 privateKey;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 missingAccountFunds;
    }

    // test adapted from Solady
    function test_succeedsWithEOASigner() public {
        TestTemps memory t;
        t.userOpHash = keccak256("123");
        t.signer = signer;
        t.privateKey = signerPrivateKey;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 0; // paymaster covers gas

        vm.etch(account.entryPoint(), address(new MockEntryPoint()).code);
        MockEntryPoint ep = MockEntryPoint(payable(account.entryPoint()));

        PackedUserOperation memory userOp;

        // Success returns 0 — valid signature from the EOA itself
        userOp.signature = abi.encodePacked(t.r, t.s, t.v);
        assertEq(ep.validateUserOp(address(account), userOp, t.userOpHash, t.missingAccountFunds), 0);

        // Failure returns 1 — tampered signature
        userOp.signature = abi.encodePacked(t.r, bytes32(uint256(t.s) ^ 1), t.v);
        assertEq(ep.validateUserOp(address(account), userOp, t.userOpHash, t.missingAccountFunds), 1);
    }

    function test_revertsWhenNotEntryPoint() public {
        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(bytes32(0), bytes32(0), uint8(27));

        // Calling directly (not from EntryPoint) should revert
        vm.expectRevert(TSmartAccount7702.Unauthorized.selector);
        account.validateUserOp(userOp, keccak256("123"), 0);
    }

    function test_returnsOneForWrongSigner() public {
        // Sign with a different private key (not the EOA)
        (, uint256 wrongKey) = makeAddrAndKey("wrong signer");
        bytes32 userOpHash = keccak256("123");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, userOpHash);

        vm.etch(account.entryPoint(), address(new MockEntryPoint()).code);
        MockEntryPoint ep = MockEntryPoint(payable(account.entryPoint()));

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(r, s, v);
        assertEq(ep.validateUserOp(address(account), userOp, userOpHash, 0), 1);
    }

    // ─── Self-funded (no paymaster) tests ────────────────────────────

    /// @dev When missingAccountFunds > 0, the account pays the EntryPoint from its ETH balance.
    function test_paysPrefund_whenNoPaymaster() public {
        uint256 prefund = 0.01 ether;
        vm.deal(address(account), 1 ether);

        vm.etch(account.entryPoint(), address(new MockEntryPoint()).code);
        MockEntryPoint ep = MockEntryPoint(payable(account.entryPoint()));

        uint256 epBalanceBefore = address(ep).balance;
        uint256 accountBalanceBefore = address(account).balance;

        TestTemps memory t;
        t.userOpHash = keccak256("self-funded");
        (t.v, t.r, t.s) = vm.sign(signerPrivateKey, t.userOpHash);

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(t.r, t.s, t.v);

        uint256 result = ep.validateUserOp(address(account), userOp, t.userOpHash, prefund);

        assertEq(result, 0, "signature validation should succeed");
        assertEq(address(ep).balance, epBalanceBefore + prefund, "EntryPoint should receive prefund");
        assertEq(address(account).balance, accountBalanceBefore - prefund, "account balance should decrease");
    }

    /// @dev When missingAccountFunds is 0 (paymaster present), no ETH is transferred.
    function test_noPrefund_whenPaymasterPresent() public {
        vm.deal(address(account), 1 ether);

        vm.etch(account.entryPoint(), address(new MockEntryPoint()).code);
        MockEntryPoint ep = MockEntryPoint(payable(account.entryPoint()));

        uint256 epBalanceBefore = address(ep).balance;
        uint256 accountBalanceBefore = address(account).balance;

        TestTemps memory t;
        t.userOpHash = keccak256("with-paymaster");
        (t.v, t.r, t.s) = vm.sign(signerPrivateKey, t.userOpHash);

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(t.r, t.s, t.v);

        ep.validateUserOp(address(account), userOp, t.userOpHash, 0);

        assertEq(address(ep).balance, epBalanceBefore, "EntryPoint balance should not change");
        assertEq(address(account).balance, accountBalanceBefore, "account balance should not change");
    }

    /// @dev Self-funded flow through the real EntryPoint with non-zero gas fees.
    function test_selfFunded_e2e_nativeTransfer() public {
        vm.deal(address(account), 10 ether);
        address recipient = address(0xbeef);
        vm.deal(recipient, 1 wei);

        uint256 recipientBefore = recipient.balance;

        userOpCalldata = abi.encodeCall(TSmartAccount7702.execute, (recipient, 1 ether, ""));

        // Build UserOp with non-zero gas fees and no paymaster
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(account),
            nonce: userOpNonce,
            initCode: "",
            callData: userOpCalldata,
            accountGasLimits: bytes32(uint256(200_000) << 128 | uint256(200_000)),
            preVerificationGas: 50_000,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(1 gwei)),
            paymasterAndData: "",
            signature: ""
        });
        userOp.signature = _sign(userOp);

        _sendUserOperation(userOp);

        assertEq(recipient.balance, recipientBefore + 1 ether, "recipient should receive 1 ETH");
        assertLt(address(account).balance, 10 ether - 1 ether, "account should pay gas on top of transfer");
    }
}

/// @dev Runs validateUserOp tests against EntryPoint v0.9.
contract TestValidateUserOp is TestValidateUserOpBase, UseEntryPointV09 {}
