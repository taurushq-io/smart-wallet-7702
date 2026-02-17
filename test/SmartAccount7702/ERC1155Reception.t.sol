// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./SmartWalletTestBase.sol";
import "../mocks/MockERC1155.sol";

/// @title ERC-1155 token reception tests
/// @dev Verifies the smart wallet can receive and send ERC-1155 tokens.
///
///      Under EIP-7702 the EOA has code, so ALL ERC-1155 transfer functions invoke
///      acceptance callbacks (`onERC1155Received` / `onERC1155BatchReceived`).
///      The contract implements both callbacks to return the expected magic values.
///
///      Unlike ERC-721 which has a non-safe `transferFrom`, ERC-1155 ONLY has safe transfers.
///      Without the callbacks, the wallet could NOT receive ANY ERC-1155 tokens.
contract TestERC1155Reception is SmartWalletTestBase {
    MockERC1155 token;
    address alice = address(uint160(uint256(keccak256("alice"))));

    function setUp() public override {
        super.setUp();
        token = new MockERC1155();
    }

    // ─── Receiving via _update (no callback, internal only) ──────────

    /// @dev `_update` does NOT call acceptance callbacks, so minting via it works.
    function test_receive_mintUnsafe() public {
        token.mintUnsafe(address(account), 1, 100);
        assertEq(token.balanceOf(address(account), 1), 100);
    }

    // ─── Receiving via mint (safe, with callback) ────────────────────

    /// @dev `_mint` calls `_updateWithAcceptanceCheck` → `onERC1155Received`.
    ///      The wallet returns the magic value `0xf23a6e61`.
    function test_receive_safeMint() public {
        token.mint(address(account), 1, 100, "");
        assertEq(token.balanceOf(address(account), 1), 100);
    }

    // ─── Receiving via safeTransferFrom (with callback) ──────────────

    /// @dev `safeTransferFrom` calls `onERC1155Received`. The wallet returns the magic value.
    function test_receive_safeTransferFrom() public {
        token.mintUnsafe(alice, 1, 100);

        vm.prank(alice);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(alice, address(account), 1, 50, "");
        assertEq(token.balanceOf(address(account), 1), 50);
        assertEq(token.balanceOf(alice, 1), 50);
    }

    // ─── Receiving via safeBatchTransferFrom (with callback) ─────────

    /// @dev `safeBatchTransferFrom` calls `onERC1155BatchReceived`.
    ///      The wallet returns the magic value `0xbc197c81`.
    function test_receive_safeBatchTransferFrom() public {
        token.mintUnsafe(alice, 1, 100);
        token.mintUnsafe(alice, 2, 200);

        vm.prank(alice);
        token.setApprovalForAll(address(this), true);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50;
        amounts[1] = 100;

        token.safeBatchTransferFrom(alice, address(account), ids, amounts, "");
        assertEq(token.balanceOf(address(account), 1), 50);
        assertEq(token.balanceOf(address(account), 2), 100);
        assertEq(token.balanceOf(alice, 1), 50);
        assertEq(token.balanceOf(alice, 2), 100);
    }

    // ─── Receiving via batch mint (safe, with callback) ──────────────

    /// @dev `_mintBatch` triggers `onERC1155BatchReceived`. The wallet returns the magic value.
    function test_receive_safeMintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        token.mintBatch(address(account), ids, amounts, "");
        assertEq(token.balanceOf(address(account), 1), 100);
        assertEq(token.balanceOf(address(account), 2), 200);
    }

    // ─── Sending via execute() ───────────────────────────────────────

    /// @dev The wallet can send ERC-1155 tokens via `execute()` through the EntryPoint.
    function test_send_safeTransferFrom_toEOA_viaExecute() public {
        token.mintUnsafe(address(account), 1, 100);

        userOpCalldata = abi.encodeCall(
            SmartAccount7702.execute,
            (
                address(token),
                0,
                abi.encodeCall(token.safeTransferFrom, (address(account), alice, 1, 50, ""))
            )
        );
        _sendUserOperation(_getUserOpWithSignature());

        assertEq(token.balanceOf(alice, 1), 50);
        assertEq(token.balanceOf(address(account), 1), 50);
    }

    /// @dev The wallet can batch-send ERC-1155 tokens via `execute()`.
    function test_send_safeBatchTransferFrom_toEOA_viaExecute() public {
        token.mintUnsafe(address(account), 1, 100);
        token.mintUnsafe(address(account), 2, 200);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50;
        amounts[1] = 100;

        userOpCalldata = abi.encodeCall(
            SmartAccount7702.execute,
            (
                address(token),
                0,
                abi.encodeCall(token.safeBatchTransferFrom, (address(account), alice, ids, amounts, ""))
            )
        );
        _sendUserOperation(_getUserOpWithSignature());

        assertEq(token.balanceOf(alice, 1), 50);
        assertEq(token.balanceOf(alice, 2), 100);
        assertEq(token.balanceOf(address(account), 1), 50);
        assertEq(token.balanceOf(address(account), 2), 100);
    }
}
