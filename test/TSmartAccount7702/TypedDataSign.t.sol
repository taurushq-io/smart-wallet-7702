// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {UseEntryPointV09} from "./entrypoint/UseEntryPointV09.sol";
import {SmartWalletTestBase} from "./SmartWalletTestBase.sol";
import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";

/// @title TestTypedDataSign
/// @notice Tests the ERC-7739 TypedDataSign nested signature path for `isValidSignature`.
///
/// @dev ERC-7739 supports two nested flows:
///   1. PersonalSign — tested in IsValidSignature.t.sol and ERC1271.t.sol
///   2. TypedDataSign — tested here
///
/// The TypedDataSign flow wraps an application's EIP-712 typed data into a nested struct
/// that includes the account's domain separator fields, binding the signature to this
/// specific account.
///
/// Encoded signature format:
///   signature || APP_DOMAIN_SEPARATOR || contentsHash || contentsDescr || uint16(contentsDescr.length)
contract TestTypedDataSign is SmartWalletTestBase, UseEntryPointV09 {
    // -----------------------------------------------------------------------
    //  Application-level EIP-712 types (simulated dApp)
    // -----------------------------------------------------------------------

    /// @dev Example application type: a token permit.
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev The application's EIP-712 domain (e.g., a token contract).
    string internal constant APP_NAME = "MyToken";
    string internal constant APP_VERSION = "1";

    function test_typedDataSign_validSignature() public view {
        // --- Build the application-level typed data ---
        address appContract = address(0xAABB); // simulated app contract
        bytes32 appDomainSeparator = _appDomainSeparator(appContract);

        // Application-level struct hash (a permit)
        bytes32 contentsHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                address(account), // owner
                address(0xdead), // spender
                uint256(100e18), // value
                uint256(0), // nonce
                uint256(block.timestamp + 1 hours) // deadline
            )
        );

        // The hash that the app would pass to isValidSignature:
        // keccak256("\x19\x01" || appDomainSeparator || contentsHash)
        bytes32 appHash = keccak256(abi.encodePacked("\x19\x01", appDomainSeparator, contentsHash));

        // --- Build the ERC-7739 TypedDataSign nested hash ---
        // contentsDescr is the EIP-712 type string of the application struct (implicit mode).
        string memory contentsDescr =
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";

        // Account domain bytes (name, version, chainId, verifyingContract, salt)
        bytes memory domainBytes = abi.encode(
            keccak256("TSmart Account 7702"),
            keccak256("1"),
            block.chainid,
            address(account),
            bytes32(0)
        );

        // TypedDataSign typehash
        bytes32 typedDataSignTypehash = keccak256(
            abi.encodePacked(
                "TypedDataSign("
                "Permit"
                " contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
            )
        );

        // TypedDataSign struct hash
        bytes32 structHash = keccak256(abi.encodePacked(typedDataSignTypehash, contentsHash, domainBytes));

        // Final hash to sign: keccak256("\x19\x01" || appDomainSeparator || structHash)
        bytes32 toSign = keccak256(abi.encodePacked("\x19\x01", appDomainSeparator, structHash));

        // --- Sign ---
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        bytes memory rawSig = abi.encodePacked(r, s, v);

        // --- Encode the nested signature ---
        // Format: signature || APP_DOMAIN_SEPARATOR || contentsHash || contentsDescr || uint16(contentsDescr.length)
        bytes memory encodedSig = abi.encodePacked(
            rawSig, appDomainSeparator, contentsHash, contentsDescr, uint16(bytes(contentsDescr).length)
        );

        // --- Verify ---
        bytes4 result = account.isValidSignature(appHash, encodedSig);
        assertEq(result, bytes4(0x1626ba7e), "TypedDataSign signature should be valid");
    }

    function test_typedDataSign_rejectsWrongSigner() public view {
        address appContract = address(0xAABB);
        bytes32 appDomainSeparator = _appDomainSeparator(appContract);

        bytes32 contentsHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, address(account), address(0xdead), uint256(100e18), uint256(0), uint256(999))
        );

        bytes32 appHash = keccak256(abi.encodePacked("\x19\x01", appDomainSeparator, contentsHash));

        string memory contentsDescr =
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";

        bytes memory domainBytes = abi.encode(
            keccak256("TSmart Account 7702"),
            keccak256("1"),
            block.chainid,
            address(account),
            bytes32(0)
        );

        bytes32 typedDataSignTypehash = keccak256(
            abi.encodePacked(
                "TypedDataSign("
                "Permit"
                " contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
            )
        );

        bytes32 structHash = keccak256(abi.encodePacked(typedDataSignTypehash, contentsHash, domainBytes));
        bytes32 toSign = keccak256(abi.encodePacked("\x19\x01", appDomainSeparator, structHash));

        // Sign with WRONG key
        uint256 wrongKey = uint256(keccak256(abi.encodePacked("wrong signer")));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, toSign);
        bytes memory rawSig = abi.encodePacked(r, s, v);

        bytes memory encodedSig = abi.encodePacked(
            rawSig, appDomainSeparator, contentsHash, contentsDescr, uint16(bytes(contentsDescr).length)
        );

        bytes4 result = account.isValidSignature(appHash, encodedSig);
        assertEq(result, bytes4(0xffffffff), "TypedDataSign with wrong signer should be rejected");
    }

    function test_typedDataSign_rejectsCrossAccountReplay() public {
        // Setup a second account (Bob)
        address bob = makeAddr("bob");
        TSmartAccount7702 impl2 = new TSmartAccount7702();
        vm.etch(bob, address(impl2).code);
        TSmartAccount7702 bobAccount = TSmartAccount7702(payable(bob));
        vm.prank(bob);
        bobAccount.initialize(address(entryPoint));

        // Build signature for Alice's account
        address appContract = address(0xAABB);
        bytes32 appDomainSeparator = _appDomainSeparator(appContract);

        bytes32 contentsHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, address(account), address(0xdead), uint256(50e18), uint256(0), uint256(999))
        );

        bytes32 appHash = keccak256(abi.encodePacked("\x19\x01", appDomainSeparator, contentsHash));

        string memory contentsDescr =
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";

        // Domain bytes for ALICE's account
        bytes memory domainBytes = abi.encode(
            keccak256("TSmart Account 7702"),
            keccak256("1"),
            block.chainid,
            address(account), // Alice
            bytes32(0)
        );

        bytes32 typedDataSignTypehash = keccak256(
            abi.encodePacked(
                "TypedDataSign("
                "Permit"
                " contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
            )
        );

        bytes32 structHash = keccak256(abi.encodePacked(typedDataSignTypehash, contentsHash, domainBytes));
        bytes32 toSign = keccak256(abi.encodePacked("\x19\x01", appDomainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        bytes memory rawSig = abi.encodePacked(r, s, v);

        bytes memory encodedSig = abi.encodePacked(
            rawSig, appDomainSeparator, contentsHash, contentsDescr, uint16(bytes(contentsDescr).length)
        );

        // Valid on Alice's account
        assertEq(account.isValidSignature(appHash, encodedSig), bytes4(0x1626ba7e));

        // REJECTED on Bob's account — domain bytes include Alice's address, not Bob's
        assertEq(bobAccount.isValidSignature(appHash, encodedSig), bytes4(0xffffffff));
    }

    // -----------------------------------------------------------------------
    //  Helpers
    // -----------------------------------------------------------------------

    function _appDomainSeparator(address appContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(APP_NAME)),
                keccak256(bytes(APP_VERSION)),
                block.chainid,
                appContract
            )
        );
    }
}
