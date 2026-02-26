// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {UseEntryPointV09} from "./entrypoint/UseEntryPointV09.sol";
import {SmartWalletTestBase} from "./SmartWalletTestBase.sol";
import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";
import {MockERC721} from "../mocks/MockERC721.sol";

/// @title ERC-721 token reception tests
/// @dev Verifies the smart wallet can receive and send ERC-721 NFTs.
///
///      Under EIP-7702 the EOA has code, so `safeTransferFrom` and `safeMint` invoke
///      `onERC721Received` on the wallet. The contract implements this callback to return
///      the magic value `0x150b7a02`, allowing all safe transfer paths to succeed.
/// @dev Abstract test logic for ERC-721 reception. Concrete classes provide the EntryPoint version.
abstract contract TestERC721ReceptionBase is SmartWalletTestBase {
    MockERC721 nft;
    address alice = address(uint160(uint256(keccak256("alice"))));

    function setUp() public virtual override {
        super.setUp();
        nft = new MockERC721();
    }

    // ─── Receiving via _mint (no callback) ───────────────────────────

    /// @dev `_mint` does NOT call `onERC721Received`, so it should always work.
    function test_receive_mint() public {
        nft.mint(address(account), 1);
        assertEq(nft.ownerOf(1), address(account));
        assertEq(nft.balanceOf(address(account)), 1);
    }

    // ─── Receiving via transferFrom (no callback) ────────────────────

    /// @dev `transferFrom` does NOT call `onERC721Received`, so it should work.
    function test_receive_transferFrom() public {
        nft.mint(alice, 1);

        vm.prank(alice);
        nft.approve(address(this), 1);

        nft.transferFrom(alice, address(account), 1);
        assertEq(nft.ownerOf(1), address(account));
    }

    // ─── Receiving via safeTransferFrom (with callback) ──────────────

    /// @dev `safeTransferFrom` calls `onERC721Received`. The wallet returns the magic value.
    function test_receive_safeTransferFrom() public {
        nft.mint(alice, 1);

        vm.prank(alice);
        nft.approve(address(this), 1);

        nft.safeTransferFrom(alice, address(account), 1);
        assertEq(nft.ownerOf(1), address(account));
    }

    /// @dev `safeTransferFrom` with extra data also works.
    function test_receive_safeTransferFromWithData() public {
        nft.mint(alice, 1);

        vm.prank(alice);
        nft.approve(address(this), 1);

        nft.safeTransferFrom(alice, address(account), 1, "some data");
        assertEq(nft.ownerOf(1), address(account));
    }

    // ─── Receiving via safeMint (with callback) ──────────────────────

    /// @dev `_safeMint` calls `onERC721Received`. The wallet returns the magic value.
    function test_receive_safeMint() public {
        nft.safeMint(address(account), 1);
        assertEq(nft.ownerOf(1), address(account));
    }

    // ─── Sending via execute() ───────────────────────────────────────

    /// @dev The wallet can send ERC-721 tokens via `execute()` through the EntryPoint.
    function test_send_transferFrom_viaExecute() public {
        nft.mint(address(account), 1);

        userOpCalldata = abi.encodeCall(
            TSmartAccount7702.execute,
            (address(nft), 0, abi.encodeCall(nft.transferFrom, (address(account), alice, 1)))
        );
        _sendUserOperation(_getUserOpWithSignature());

        assertEq(nft.ownerOf(1), alice);
    }

    /// @dev The wallet can send ERC-721 tokens via `safeTransferFrom` to an EOA.
    function test_send_safeTransferFrom_toEOA_viaExecute() public {
        nft.mint(address(account), 1);

        userOpCalldata = abi.encodeCall(
            TSmartAccount7702.execute,
            (
                address(nft),
                0,
                abi.encodeWithSignature(
                    "safeTransferFrom(address,address,uint256)", address(account), alice, 1
                )
            )
        );
        _sendUserOperation(_getUserOpWithSignature());

        assertEq(nft.ownerOf(1), alice);
    }
}

/// @dev Runs ERC-721 reception tests against EntryPoint v0.9.
contract TestERC721Reception is TestERC721ReceptionBase, UseEntryPointV09 {
    function setUp() public override(TestERC721ReceptionBase, SmartWalletTestBase) {
        TestERC721ReceptionBase.setUp();
    }
}
