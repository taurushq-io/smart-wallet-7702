// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SmartWalletTestBase} from "../SmartWalletTestBase.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

/// @dev Mixin that deploys EntryPoint v0.9.0 at the canonical address.
///
/// @dev The canonical EntryPoint address used here is the v0.8.0 address (0x4337084D...).
///      EntryPoint v0.9.0 bytecode is deployed at that address to allow the same test suite
///      to run against both v0.8.0 and v0.9.0 without changing the account's hardcoded constant.
///
///      To test with the actual v0.9.0 canonical address (0x433709...),
///      use TSmartAccount7702V09 (which overrides entryPoint()) together with deploying
///      the v0.9.0 EntryPoint at 0x433709009B8330FDa32311DF1C2AFA402eD8D009.
abstract contract UseEntryPointV09 is SmartWalletTestBase {
    function _deployEntryPoint() internal override {
        EntryPoint ep = new EntryPoint();
        vm.etch(address(entryPoint), address(ep).code);
    }
}
