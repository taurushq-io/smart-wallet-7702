// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./SmartWalletTestBase.sol";

contract TestIsValidSignature is SmartWalletTestBase {
    /// @dev Must match OZ's ERC7739Utils.PERSONAL_SIGN_TYPEHASH
    bytes32 internal constant PERSONAL_SIGN_TYPEHASH = keccak256("PersonalSign(bytes prefixed)");

    function testValidateSignatureWithEOASigner() public {
        bytes32 hash = 0x15fa6f8c855db1dccbb8a42eef3a7b83f11d29758e84aed37312527165d5eec5;
        bytes32 toSign = _personalSignHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes4 ret = account.isValidSignature(hash, signature);
        assertEq(ret, bytes4(0x1626ba7e));
    }

    function testValidateSignatureWithEOASignerFailsWithWrongSigner() public {
        bytes32 hash = 0x15fa6f8c855db1dccbb8a42eef3a7b83f11d29758e84aed37312527165d5eec5;
        bytes32 toSign = _personalSignHash(hash);
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

    /// @dev Computes the ERC-7739 PersonalSign nested hash for the test account.
    function _personalSignHash(bytes32 appHash) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, appHash));
        bytes32 domainSep = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("TSmart Account 7702"),
                keccak256("1"),
                block.chainid,
                address(account)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
    }
}
