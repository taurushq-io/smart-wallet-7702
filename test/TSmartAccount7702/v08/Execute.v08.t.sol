// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {TestExecuteBase} from "../Execute.t.sol";
import {UseEntryPointV08} from "../entrypoint/UseEntryPointV08.sol";

/// @dev Runs execute tests against EntryPoint v0.8.
contract TestExecuteV08 is TestExecuteBase, UseEntryPointV08 {}
