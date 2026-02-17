// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./SmartWalletTestBase.sol";

contract TestIsValidSignature is SmartWalletTestBase {
    function testValidateSignatureWithEOASigner() public {
        bytes32 hash = 0x15fa6f8c855db1dccbb8a42eef3a7b83f11d29758e84aed37312527165d5eec5;
        bytes32 toSign = account.replaySafeHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes4 ret = account.isValidSignature(hash, signature);
        assertEq(ret, bytes4(0x1626ba7e));
    }

    function testValidateSignatureWithEOASignerFailsWithWrongSigner() public {
        bytes32 hash = 0x15fa6f8c855db1dccbb8a42eef3a7b83f11d29758e84aed37312527165d5eec5;
        bytes32 toSign = account.replaySafeHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xa12ce, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes4 ret = account.isValidSignature(hash, signature);
        assertEq(ret, bytes4(0xffffffff));
    }

    function testValidateSignatureWithInvalidSignatureLength() public {
        bytes32 hash = 0x15fa6f8c855db1dccbb8a42eef3a7b83f11d29758e84aed37312527165d5eec5;
        // Invalid signature (too short) — should return failure, not revert
        bytes memory signature = hex"deadbeef";
        bytes4 ret = account.isValidSignature(hash, signature);
        assertEq(ret, bytes4(0xffffffff));
    }
}
