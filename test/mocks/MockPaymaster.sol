// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BasePaymaster} from "account-abstraction/core/BasePaymaster.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

/// @title MockPaymaster
///
/// @notice A test-only paymaster that sponsors gas for every UserOperation unconditionally.
///
/// @dev In production, paymasters enforce policies (e.g., Circle's USDC Paymaster only sponsors
///      if the user pays gas in USDC). This mock accepts everything to demonstrate the ERC-4337
///      paymaster flow without policy complexity.
///
///      The paymaster lifecycle:
///        1. Owner deploys the paymaster and deposits ETH into the EntryPoint
///        2. Owner stakes ETH in the EntryPoint (required for paymasters)
///        3. When a UserOp references this paymaster, the EntryPoint calls validatePaymasterUserOp
///        4. If validation succeeds, the EntryPoint deducts gas from the paymaster's deposit
///        5. After execution, postOp is called (only if context was returned — we return empty)
contract MockPaymaster is BasePaymaster {
    constructor(IEntryPoint entryPoint_, address owner_) BasePaymaster(entryPoint_, owner_) {}

    /// @dev Accepts every UserOperation. Returns empty context (no postOp needed)
    ///      and SIG_VALIDATION_SUCCESS (0) to indicate the paymaster agrees to pay.
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal pure override returns (bytes memory context, uint256 validationData) {
        (userOp, userOpHash, maxCost);
        return ("", SIG_VALIDATION_SUCCESS);
    }
}
