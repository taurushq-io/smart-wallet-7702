// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {TestExecuteBatchBase} from "../ExecuteBatch.t.sol";
import {UseEntryPointV08} from "../entrypoint/UseEntryPointV08.sol";

/// @dev Runs executeBatch tests against EntryPoint v0.8.
contract TestExecuteBatchV08 is TestExecuteBatchBase, UseEntryPointV08 {}
