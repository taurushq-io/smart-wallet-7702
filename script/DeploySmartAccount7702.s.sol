// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {SafeSingletonDeployer} from "safe-singleton-deployer-sol/src/SafeSingletonDeployer.sol";

import {SmartAccount7702} from "../src/SmartAccount7702.sol";

/// @title DeploySmartAccount7702
/// @notice Deploys the SmartAccount7702 implementation contract.
///         No factory is needed — each EOA delegates to this implementation via EIP-7702.
contract DeploySmartAccount7702Script is Script {
    function run() public {
        console2.log("Deploying on chain ID", block.chainid);

        address entryPoint = vm.envAddress("ENTRY_POINT");
        console2.log("EntryPoint", entryPoint);

        address implementation = SafeSingletonDeployer.broadcastDeploy({
            creationCode: abi.encodePacked(type(SmartAccount7702).creationCode, abi.encode(entryPoint)),
            salt: 0x3771220e68256b8d5aa359fe953bf594dad1a5473239d1251256f0e5e7473b16
        });
        console2.log("implementation", implementation);
    }
}
