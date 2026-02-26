// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {UseEntryPointV09} from "./entrypoint/UseEntryPointV09.sol";
import {SmartWalletTestBase} from "./SmartWalletTestBase.sol";

contract TestIsValidSignature is SmartWalletTestBase, UseEntryPointV09 {
    /// @dev Must match OZ's ERC7739Utils.PERSONAL_SIGN_TYPEHASH
    bytes32 internal constant PERSONAL_SIGN_TYPEHASH = keccak256("PersonalSign(bytes prefixed)");

    function testValidateSignatureWithEOASigner() public view {
        bytes32 hash = keccak256("test message");
        bytes32 toSign = _personalSignHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes4 ret = account.isValidSignature(hash, signature);
        assertEq(ret, bytes4(0x1626ba7e));
    }

    function testValidateSignatureWithEOASignerFailsWithWrongSigner() public view {
        bytes32 hash = keccak256("test message");
        bytes32 toSign = _personalSignHash(hash);
        uint256 wrongKey = uint256(keccak256(abi.encodePacked("wrong signer")));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes4 ret = account.isValidSignature(hash, signature);
        assertEq(ret, bytes4(0xffffffff));
    }

    function testValidateSignatureWithInvalidSignatureLength() public view {
        bytes32 hash = keccak256("test message");
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
