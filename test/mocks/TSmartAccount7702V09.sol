// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {TSmartAccount7702} from "../../src/TSmartAccount7702.sol";

/// @dev Convenience deployment of TSmartAccount7702 targeting the EntryPoint v0.9.0
///      canonical address (0x433709009B8330FDa32311DF1C2AFA402eD8D009).
///
///      Use this in tests that deploy EntryPoint v0.9.0 at its own canonical address
///      rather than at the v0.8.0 address. The v0.9.0 address is baked into the bytecode
///      as an immutable, so etching this contract's code onto an EOA gives an account
///      that trusts the v0.9.0 EntryPoint.
contract TSmartAccount7702V09 is TSmartAccount7702 {
    constructor() TSmartAccount7702(0x433709009B8330FDa32311DF1C2AFA402eD8D009) {}
}
