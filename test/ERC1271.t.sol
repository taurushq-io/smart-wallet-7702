// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";

import {SmartAccount7702} from "../src/SmartAccount7702.sol";

contract ERC1271Test is Test {
    /// @dev Must match OZ's ERC7739Utils.PERSONAL_SIGN_TYPEHASH
    bytes32 internal constant PERSONAL_SIGN_TYPEHASH = keccak256("PersonalSign(bytes prefixed)");

    SmartAccount7702 account;
    uint256 signerPrivateKey;
    address signer;

    function setUp() public {
        (signer, signerPrivateKey) = makeAddrAndKey("alice");

        // Simulate EIP-7702 delegation
        SmartAccount7702 impl = new SmartAccount7702();
        vm.etch(signer, address(impl).code);
        account = SmartAccount7702(payable(signer));
        vm.prank(signer);
        account.initialize(address(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108));
    }

    function test_returnsExpectedDomainValues() public view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = account.eip712Domain();

        assertEq(fields, hex"0f");
        assertEq(name, "TSmart Account 7702");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(account));
        assertEq(salt, bytes32(0));
        assertEq(abi.encode(extensions), abi.encode(new uint256[](0)));
    }

    function test_isValidSignature_erc7739_rejectsReplay() public {
        // Two different accounts should reject each other's signatures (anti-replay via domain binding)
        address otherSigner = makeAddr("bob");
        SmartAccount7702 impl2 = new SmartAccount7702();
        vm.etch(otherSigner, address(impl2).code);
        SmartAccount7702 otherAccount = SmartAccount7702(payable(otherSigner));
        vm.prank(otherSigner);
        otherAccount.initialize(address(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108));

        bytes32 appHash = keccak256("test message");

        // Sign for `account` using the PersonalSign path
        bytes32 toSign = _personalSignHash(address(account), appHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Valid on account
        assertEq(account.isValidSignature(appHash, signature), bytes4(0x1626ba7e));

        // Rejected on otherAccount (different domain separator)
        assertEq(otherAccount.isValidSignature(appHash, signature), bytes4(0xffffffff));
    }

    function test_isValidSignature_erc7739_detection() public view {
        // ERC-7739 detection: magic hash with empty signature returns 0x77390001
        bytes32 magicHash = 0x7739773977397739773977397739773977397739773977397739773977397739;
        bytes4 ret = account.isValidSignature(magicHash, "");
        assertEq(ret, bytes4(0x77390001));
    }

    /// @dev Computes the ERC-7739 PersonalSign nested hash for a given account and app hash.
    function _personalSignHash(address accountAddr, bytes32 appHash) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, appHash));
        bytes32 domainSep = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("TSmart Account 7702"),
                keccak256("1"),
                block.chainid,
                accountAddr
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
    }
}
