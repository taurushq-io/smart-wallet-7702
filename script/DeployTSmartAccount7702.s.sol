// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console2} from "forge-std/Script.sol";

import {TSmartAccount7702} from "../src/TSmartAccount7702.sol";

/// @title DeployTSmartAccount7702
/// @notice Deploys the TSmartAccount7702 implementation contract.
///         No factory is needed — each EOA delegates to this implementation via EIP-7702.
contract DeployTSmartAccount7702Script is Script {
    function run() public {
        console2.log("Deploying on chain ID", block.chainid);

        // keccak256("TSmart Account 7702 v1") — deterministic CREATE2 salt.
        // Using a fixed salt ensures the implementation deploys to the same address
        // across all chains (given the same deployer and bytecode).
        bytes32 salt = 0x386bb1ea9970b4bc4d4f7d711ed0c7f4675a489f20743a2fd3aee6e46438263c;

        vm.startBroadcast();
        TSmartAccount7702 implementation = new TSmartAccount7702{salt: salt}();
        vm.stopBroadcast();

        console2.log("implementation", address(implementation));
        console2.log("Each delegating EOA must call initialize(entryPoint) after EIP-7702 delegation");
    }
}
