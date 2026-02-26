// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {SmartWalletTestBase} from "../SmartWalletTestBase.sol";

/// @dev Mixin that deploys EntryPoint v0.9.0 at the canonical address.
abstract contract UseEntryPointV09 is SmartWalletTestBase {
    function _deployEntryPoint() internal override {
        EntryPoint ep = new EntryPoint();
        vm.etch(address(entryPoint), address(ep).code);
    }
}
