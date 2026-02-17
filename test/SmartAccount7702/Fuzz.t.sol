// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {MockEntryPoint} from "../mocks/MockEntryPoint.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import "./SmartWalletTestBase.sol";

/// @title TestFuzz
///
/// @notice Fuzz tests for SmartAccount7702's core signing and execution paths.
///
/// @dev Covers:
///      - validateUserOp: valid signatures, wrong signers, random garbage signatures, prefund amounts
///      - isValidSignature (PersonalSign): valid signatures, wrong signers, garbage data
///      - execute: ETH transfers with fuzzed amounts
///      - supportsInterface: known vs unknown interface IDs
contract TestFuzz is SmartWalletTestBase {
    MockEntryPoint mockEp;

    /// @dev Must match OZ's ERC7739Utils.PERSONAL_SIGN_TYPEHASH
    bytes32 internal constant PERSONAL_SIGN_TYPEHASH = keccak256("PersonalSign(bytes prefixed)");

    function setUp() public override {
        super.setUp();
        // Deploy MockEntryPoint and etch it at the canonical address so we can call
        // validateUserOp directly with arbitrary parameters.
        mockEp = new MockEntryPoint();
        vm.etch(account.entryPoint(), address(mockEp).code);
        mockEp = MockEntryPoint(payable(account.entryPoint()));
    }

    // =====================================================================
    //  validateUserOp — signature validation
    // =====================================================================

    /// @dev For any userOpHash, signing with the correct key must return 0 (valid).
    function testFuzz_validateUserOp_validSignature(bytes32 userOpHash) public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, userOpHash);

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(r, s, v);

        uint256 result = mockEp.validateUserOp(address(account), userOp, userOpHash, 0);
        assertEq(result, 0, "valid signature should return 0");
    }

    /// @dev For any userOpHash, signing with a different key must return 1 (invalid).
    function testFuzz_validateUserOp_wrongSigner(bytes32 userOpHash, uint256 wrongKey) public {
        // Bound to valid secp256k1 private key range, excluding the owner's key
        wrongKey = bound(wrongKey, 1, type(uint128).max);
        vm.assume(wrongKey != signerPrivateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, userOpHash);

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(r, s, v);

        uint256 result = mockEp.validateUserOp(address(account), userOp, userOpHash, 0);
        assertEq(result, 1, "wrong signer should return 1");
    }

    /// @dev Random bytes as signature should never validate (return 0).
    function testFuzz_validateUserOp_garbageSignature(bytes32 userOpHash, bytes memory garbageSig) public {
        PackedUserOperation memory userOp;
        userOp.signature = garbageSig;

        uint256 result = mockEp.validateUserOp(address(account), userOp, userOpHash, 0);

        // Result is either 0 (valid) or 1 (invalid). Random garbage should almost never
        // produce a valid ECDSA signature that recovers to address(account).
        // If it does, the fuzzer found a collision — extremely unlikely but not impossible.
        // We only assert != 0 if the signature length is not exactly 65 bytes (guaranteed invalid).
        if (garbageSig.length != 65) {
            assertEq(result, 1, "non-65-byte signature must return 1");
        }
    }

    // =====================================================================
    //  validateUserOp — prefund payment
    // =====================================================================

    /// @dev For any prefund amount <= account balance, the account sends it to the EntryPoint.
    function testFuzz_validateUserOp_prefund(bytes32 userOpHash, uint256 prefund) public {
        prefund = bound(prefund, 1, 100 ether);
        vm.deal(address(account), prefund);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, userOpHash);

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(r, s, v);

        uint256 epBalanceBefore = address(mockEp).balance;

        uint256 result = mockEp.validateUserOp(address(account), userOp, userOpHash, prefund);

        assertEq(result, 0, "signature should be valid");
        assertEq(address(mockEp).balance, epBalanceBefore + prefund, "EntryPoint should receive prefund");
        assertEq(address(account).balance, 0, "account should have zero balance after full prefund");
    }

    /// @dev When prefund is 0 (paymaster present), no ETH moves regardless of account balance.
    function testFuzz_validateUserOp_zeroPrefund(bytes32 userOpHash, uint256 accountBalance) public {
        accountBalance = bound(accountBalance, 0, 100 ether);
        vm.deal(address(account), accountBalance);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, userOpHash);

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(r, s, v);

        uint256 epBalanceBefore = address(mockEp).balance;

        mockEp.validateUserOp(address(account), userOp, userOpHash, 0);

        assertEq(address(mockEp).balance, epBalanceBefore, "EntryPoint balance unchanged with zero prefund");
        assertEq(address(account).balance, accountBalance, "account balance unchanged with zero prefund");
    }

    // =====================================================================
    //  isValidSignature — PersonalSign path
    // =====================================================================

    /// @dev For any hash, signing the PersonalSign nested hash with the correct key must validate.
    function testFuzz_isValidSignature_personalSign_valid(bytes32 hash) public view {
        bytes32 toSign = _personalSignHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = account.isValidSignature(hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "valid PersonalSign signature should return magic value");
    }

    /// @dev For any hash, signing with a different key must be rejected.
    function testFuzz_isValidSignature_personalSign_wrongSigner(bytes32 hash, uint256 wrongKey) public view {
        wrongKey = bound(wrongKey, 1, type(uint128).max);
        vm.assume(wrongKey != signerPrivateKey);

        bytes32 toSign = _personalSignHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = account.isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff), "wrong signer should be rejected");
    }

    /// @dev Random garbage bytes should never return the ERC-1271 magic value.
    function testFuzz_isValidSignature_garbageSignature(bytes32 hash, bytes memory garbageSig) public view {
        // Skip 65-byte garbage — it could theoretically produce a valid ecrecover
        // if it happens to be a valid (r, s, v) that recovers to address(account).
        vm.assume(garbageSig.length != 65);

        bytes4 result = account.isValidSignature(hash, garbageSig);
        assertEq(result, bytes4(0xffffffff), "garbage signature must be rejected");
    }

    // =====================================================================
    //  execute — ETH transfers
    // =====================================================================

    /// @dev For any amount <= account balance, execute should transfer ETH correctly.
    function testFuzz_execute_ethTransfer(uint256 amount, address recipient) public {
        amount = bound(amount, 0, 100 ether);
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(account));
        // Exclude precompiles (1-9) and the EntryPoint to avoid side effects
        vm.assume(uint160(recipient) > 9);
        vm.assume(recipient != account.entryPoint());
        vm.assume(recipient.code.length == 0);

        vm.deal(address(account), amount);
        uint256 recipientBefore = recipient.balance;

        vm.prank(address(account));
        account.execute(recipient, amount, "");

        assertEq(recipient.balance, recipientBefore + amount, "recipient should receive exact ETH amount");
        assertEq(address(account).balance, 0, "account should be emptied");
    }

    /// @dev For any ERC-20 amount, execute should transfer tokens correctly.
    function testFuzz_execute_erc20Transfer(uint256 amount, address recipient) public {
        amount = bound(amount, 1, type(uint128).max);
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(account));

        MockERC20 token = new MockERC20("FuzzToken", "FZZ", 18);
        token.mint(address(account), amount);

        uint256 recipientBefore = token.balanceOf(recipient);

        bytes memory transferCall = abi.encodeCall(token.transfer, (recipient, amount));
        vm.prank(address(account));
        account.execute(address(token), 0, transferCall);

        assertEq(token.balanceOf(recipient), recipientBefore + amount, "recipient should receive tokens");
        assertEq(token.balanceOf(address(account)), 0, "account should have zero token balance");
    }

    // =====================================================================
    //  supportsInterface
    // =====================================================================

    /// @dev Known supported interface IDs must return true.
    function test_supportsInterface_knownIds() public view {
        bytes4[6] memory supported = [
            type(IAccount).interfaceId, // 0x3a871cdd
            bytes4(0x1626ba7e), // ERC-1271
            bytes4(0x77390001), // ERC-7739
            bytes4(0x150b7a02), // IERC721Receiver
            bytes4(0x4e2312e0), // IERC1155Receiver
            bytes4(0x01ffc9a7) // ERC-165
        ];
        for (uint256 i; i < supported.length; i++) {
            assertTrue(account.supportsInterface(supported[i]), "known interface should be supported");
        }
    }

    /// @dev Random interface IDs (excluding known ones) must return false.
    function testFuzz_supportsInterface_unknownId(bytes4 interfaceId) public view {
        // Exclude all known supported interfaces
        vm.assume(interfaceId != type(IAccount).interfaceId);
        vm.assume(interfaceId != bytes4(0x1626ba7e)); // ERC-1271
        vm.assume(interfaceId != bytes4(0x77390001)); // ERC-7739
        vm.assume(interfaceId != bytes4(0x150b7a02)); // IERC721Receiver
        vm.assume(interfaceId != bytes4(0x4e2312e0)); // IERC1155Receiver
        vm.assume(interfaceId != bytes4(0x01ffc9a7)); // ERC-165

        assertFalse(account.supportsInterface(interfaceId), "unknown interface should not be supported");
    }

    // =====================================================================
    //  Helpers
    // =====================================================================

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
