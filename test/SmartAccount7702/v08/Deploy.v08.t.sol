// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {TestDeployBase, RevertingConstructor} from "../Deploy.t.sol";
import {UseEntryPointV08} from "../entrypoint/UseEntryPointV08.sol";

/// @dev Runs deploy tests against EntryPoint v0.8.
contract TestDeployV08 is TestDeployBase, UseEntryPointV08 {}
