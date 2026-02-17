// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console2} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

import "../src/SmartAccount7702.sol";
import "../src/ERC1271.sol";

contract ERC1271Test is Test {
    SmartAccount7702 account;
    uint256 signerPrivateKey = 0xa11ce;
    address signer = vm.addr(signerPrivateKey);

    function setUp() public {
        // Simulate EIP-7702 delegation
        SmartAccount7702 impl = new SmartAccount7702(address(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108));
        vm.etch(signer, address(impl).code);
        account = SmartAccount7702(payable(signer));
    }

    function test_returnsExpectedDomainHash() public view {
        (
            ,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = account.eip712Domain();
        assertEq(verifyingContract, address(account));
        assertEq(abi.encode(extensions), abi.encode(new uint256[](0)));
        assertEq(salt, bytes32(0));
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
        assertEq(expected, account.domainSeparator());
    }

    function test_replaySafeHashIncludesAddress() public {
        // Two different accounts should produce different replay-safe hashes for the same input
        uint256 otherKey = 0xb0b;
        address otherSigner = vm.addr(otherKey);
        SmartAccount7702 impl2 = new SmartAccount7702(address(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108));
        vm.etch(otherSigner, address(impl2).code);
        SmartAccount7702 otherAccount = SmartAccount7702(payable(otherSigner));

        bytes32 hash = keccak256("test message");
        bytes32 safeHash1 = account.replaySafeHash(hash);
        bytes32 safeHash2 = otherAccount.replaySafeHash(hash);

        assertTrue(safeHash1 != safeHash2);
    }
}
