// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {UseEntryPointV09} from "./entrypoint/UseEntryPointV09.sol";
import {SimpleStorage} from "../mocks/SimpleStorage.sol";
import {SmartWalletTestBase} from "./SmartWalletTestBase.sol";
import {SmartAccount7702} from "../../src/SmartAccount7702.sol";

/// @dev Contract whose constructor always reverts.
contract RevertingConstructor {
    constructor() {
        revert("constructor failed");
    }
}

/// @dev Abstract test logic for deployDeterministic(). Concrete classes provide the EntryPoint version.
abstract contract TestDeployBase is SmartWalletTestBase {

    function test_deployDeterministic_succeeds() public {
        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(42)));
        bytes32 salt = bytes32(uint256(0x1234));

        vm.prank(address(account));
        address deployed = account.deployDeterministic(0, creationCode, salt);

        assertTrue(deployed != address(0));
        assertEq(SimpleStorage(deployed).value(), 42);

        // Verify address matches CREATE2 prediction
        address predicted = computeCreate2Address(salt, keccak256(creationCode), address(account));
        assertEq(deployed, predicted);
    }

    function test_deployDeterministic_withValue() public {
        vm.deal(address(account), 1 ether);

        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(7)));
        bytes32 salt = bytes32(uint256(0xabcd));

        vm.prank(address(account));
        address deployed = account.deployDeterministic(0.25 ether, creationCode, salt);

        assertTrue(deployed != address(0));
        assertEq(deployed.balance, 0.25 ether);
    }

    function test_deployDeterministic_emitsEvent() public {
        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(1)));
        bytes32 salt = bytes32(uint256(0x5678));

        // Pre-compute the deterministic address to verify topic[1]
        address predicted = computeCreate2Address(salt, keccak256(creationCode), address(account));

        vm.prank(address(account));
        vm.expectEmit(true, false, false, false);
        emit SmartAccount7702.ContractDeployed(predicted);
        account.deployDeterministic(0, creationCode, salt);
    }

    function test_deployDeterministic_revertsOnEmptyBytecode() public {
        vm.prank(address(account));
        vm.expectRevert(SmartAccount7702.EmptyBytecode.selector);
        account.deployDeterministic(0, "", bytes32(0));
    }

    function test_deployDeterministic_revertsOnSaltCollision() public {
        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(1)));
        bytes32 salt = bytes32(uint256(0x9999));

        // First deployment succeeds
        vm.prank(address(account));
        account.deployDeterministic(0, creationCode, salt);

        // Second deployment with same salt + bytecode reverts
        vm.prank(address(account));
        vm.expectRevert();
        account.deployDeterministic(0, creationCode, salt);
    }

    function test_deployDeterministic_revertsOnConstructorRevert() public {
        bytes memory creationCode = type(RevertingConstructor).creationCode;
        bytes32 salt = bytes32(uint256(0xdead));

        vm.prank(address(account));
        vm.expectRevert();
        account.deployDeterministic(0, creationCode, salt);
    }

    function test_deployDeterministic_revertsWhenNotAuthorized() public {
        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(1)));

        vm.prank(makeAddr("random"));
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        account.deployDeterministic(0, creationCode, bytes32(0));
    }

    function test_deployDeterministic_viaEntryPoint() public {
        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(55)));
        bytes32 salt = bytes32(uint256(0xbeef));

        // Predict address before deployment
        address predicted = computeCreate2Address(salt, keccak256(creationCode), address(account));

        userOpCalldata = abi.encodeCall(SmartAccount7702.deployDeterministic, (0, creationCode, salt));
        _sendUserOperation(_getUserOpWithSignature());

        // Verify the contract was deployed at the predicted address
        assertEq(SimpleStorage(predicted).value(), 55);
    }
}

/// @dev Runs deploy tests against EntryPoint v0.9.
contract TestDeploy is TestDeployBase, UseEntryPointV09 {}
