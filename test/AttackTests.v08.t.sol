// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {EntryPoint} from "account-abstraction-v0.8/core/EntryPoint.sol";
import {AttackTestsBase} from "./AttackTests.t.sol";

/// @dev Runs attack tests against EntryPoint v0.8.
contract AttackTestsV08 is AttackTestsBase {
    function _deployEntryPoint() internal override {
        EntryPoint ep = new EntryPoint();
        vm.etch(address(entryPoint), address(ep).code);
    }
}
