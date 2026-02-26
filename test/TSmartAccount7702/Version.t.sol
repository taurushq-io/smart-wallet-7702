// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {UseEntryPointV09} from "./entrypoint/UseEntryPointV09.sol";
import {SmartWalletTestBase} from "./SmartWalletTestBase.sol";

abstract contract TestVersionBase is SmartWalletTestBase {
    function test_version() public view {
        assertEq(account.version(), "0.3.0");
    }
}

contract TestVersion is TestVersionBase, UseEntryPointV09 {}
