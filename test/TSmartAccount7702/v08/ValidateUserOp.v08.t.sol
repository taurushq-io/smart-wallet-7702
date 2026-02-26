// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {TestValidateUserOpBase} from "../ValidateUserOp.t.sol";
import {UseEntryPointV08} from "../entrypoint/UseEntryPointV08.sol";

/// @dev Runs validateUserOp tests against EntryPoint v0.8.
contract TestValidateUserOpV08 is TestValidateUserOpBase, UseEntryPointV08 {}
