// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./SmartWalletTestBase.sol";

/// @dev Simple contract deployed inside tests.
contract SimpleStorage {
    uint256 public value;

    constructor(uint256 _value) payable {
        value = _value;
    }
}

/// @dev Contract whose constructor always reverts.
contract RevertingConstructor {
    constructor() {
        revert("constructor failed");
    }
}

contract TestDeploy is SmartWalletTestBase {
    // -----------------------------------------------------------------------
    //  deploy() — CREATE
    // -----------------------------------------------------------------------

    function test_deploy_succeeds() public {
        vm.deal(address(account), 1 ether);

        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(42)));

        vm.prank(address(account));
        address deployed = account.deploy(0, creationCode);

        assertTrue(deployed != address(0), "deployed address should not be zero");
        assertEq(SimpleStorage(deployed).value(), 42);
    }

    function test_deploy_withValue() public {
        vm.deal(address(account), 1 ether);

        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(7)));

        vm.prank(address(account));
        address deployed = account.deploy(0.5 ether, creationCode);

        assertTrue(deployed != address(0));
        assertEq(deployed.balance, 0.5 ether);
        assertEq(SimpleStorage(deployed).value(), 7);
    }

    function test_deploy_emitsEvent() public {
        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(1)));

        vm.prank(address(account));
        vm.expectEmit(false, false, false, false);
        emit SmartAccount7702.ContractDeployed(address(0)); // address is unknown before deploy
        account.deploy(0, creationCode);
    }

    function test_deploy_revertsOnEmptyBytecode() public {
        vm.prank(address(account));
        vm.expectRevert(SmartAccount7702.EmptyBytecode.selector);
        account.deploy(0, "");
    }

    function test_deploy_revertsOnConstructorRevert() public {
        bytes memory creationCode = type(RevertingConstructor).creationCode;

        vm.prank(address(account));
        vm.expectRevert();
        account.deploy(0, creationCode);
    }

    function test_deploy_revertsWhenNotAuthorized() public {
        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(1)));

        vm.prank(makeAddr("random"));
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        account.deploy(0, creationCode);
    }

    function test_deploy_viaEntryPoint() public {
        vm.deal(address(account), 1 ether);

        bytes memory creationCode = abi.encodePacked(type(SimpleStorage).creationCode, abi.encode(uint256(99)));

        userOpCalldata = abi.encodeCall(SmartAccount7702.deploy, (0, creationCode));
        _sendUserOperation(_getUserOpWithSignature());

        // Verify by checking the nonce advanced (deploy succeeded inside UserOp)
        // The deployed address is returned but we can't capture it from handleOps.
        // Instead, we verify the EVM nonce incremented (CREATE increments it).
        assertGt(vm.getNonce(address(account)), 0);
    }

    // -----------------------------------------------------------------------
    //  deployDeterministic() — CREATE2
    // -----------------------------------------------------------------------

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
