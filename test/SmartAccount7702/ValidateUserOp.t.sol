// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {MockEntryPoint} from "../mocks/MockEntryPoint.sol";
import "./SmartWalletTestBase.sol";

contract TestValidateUserOp is SmartWalletTestBase {
    struct _TestTemps {
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
        _TestTemps memory t;
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
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        account.validateUserOp(userOp, keccak256("123"), 0);
    }

    function test_returnsOneForWrongSigner() public {
        // Sign with a different private key (not the EOA)
        uint256 wrongKey = 0xbad;
        bytes32 userOpHash = keccak256("123");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, userOpHash);

        vm.etch(account.entryPoint(), address(new MockEntryPoint()).code);
        MockEntryPoint ep = MockEntryPoint(payable(account.entryPoint()));

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(r, s, v);
        assertEq(ep.validateUserOp(address(account), userOp, userOpHash, 0), 1);
    }
}
