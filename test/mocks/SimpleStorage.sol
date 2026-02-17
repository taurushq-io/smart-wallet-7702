// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @dev Minimal storage contract used in deploy and fuzz tests.
contract SimpleStorage {
    uint256 public value;

    constructor(uint256 _value) payable {
        value = _value;
    }
}
