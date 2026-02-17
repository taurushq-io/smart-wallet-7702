// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";

import {SmartAccount7702} from "../src/SmartAccount7702.sol";

/// @title DeploySmartAccount7702
/// @notice Deploys the SmartAccount7702 implementation contract.
///         No factory is needed — each EOA delegates to this implementation via EIP-7702.
contract DeploySmartAccount7702Script is Script {
    function run() public {
        console2.log("Deploying on chain ID", block.chainid);

        bytes32 salt = 0x3771220e68256b8d5aa359fe953bf594dad1a5473239d1251256f0e5e7473b16;

        vm.startBroadcast();
        SmartAccount7702 implementation = new SmartAccount7702{salt: salt}();
        vm.stopBroadcast();

        console2.log("implementation", address(implementation));
        console2.log("Each delegating EOA must call initialize(entryPoint) after EIP-7702 delegation");
    }
}
