// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {TestERC1155ReceptionBase} from "../ERC1155Reception.t.sol";
import {SmartWalletTestBase} from "../SmartWalletTestBase.sol";
import {UseEntryPointV08} from "../entrypoint/UseEntryPointV08.sol";

/// @dev Runs ERC-1155 reception tests against EntryPoint v0.8.
contract TestERC1155ReceptionV08 is TestERC1155ReceptionBase, UseEntryPointV08 {
    function setUp() public override(TestERC1155ReceptionBase, SmartWalletTestBase) {
        TestERC1155ReceptionBase.setUp();
    }
}
