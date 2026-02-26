// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {TestERC721ReceptionBase} from "../ERC721Reception.t.sol";
import {SmartWalletTestBase} from "../SmartWalletTestBase.sol";
import {UseEntryPointV08} from "../entrypoint/UseEntryPointV08.sol";

/// @dev Runs ERC-721 reception tests against EntryPoint v0.8.
contract TestERC721ReceptionV08 is TestERC721ReceptionBase, UseEntryPointV08 {
    function setUp() public override(TestERC721ReceptionBase, SmartWalletTestBase) {
        TestERC721ReceptionBase.setUp();
    }
}
