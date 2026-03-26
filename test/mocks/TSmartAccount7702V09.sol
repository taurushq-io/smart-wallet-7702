// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";

/// @dev Test mock that targets EntryPoint v0.9.0 at its canonical address.
///
///      The base `TSmartAccount7702` hardcodes the v0.8.0 EntryPoint address as a constant.
///      This subclass overrides `entryPoint()` to return the v0.9.0 canonical address instead,
///      allowing the full test suite to run against both EntryPoint versions at their respective
///      canonical deployments.
///
///      Usage: deploy this contract's bytecode onto an EOA (via `vm.etch`) in tests that use
///      `UseEntryPointV09`, which deploys v0.9.0 bytecode at the v0.9.0 canonical address.
contract TSmartAccount7702V09 is TSmartAccount7702 {
    /// @notice The canonical ERC-4337 EntryPoint v0.9.0 address.
    address public constant ENTRY_POINT_V09 = 0x433709009B8330FDa32311DF1C2AFA402eD8D009;

    /// @inheritdoc TSmartAccount7702
    function entryPoint() public view virtual override returns (address) {
        return ENTRY_POINT_V09;
    }
}
