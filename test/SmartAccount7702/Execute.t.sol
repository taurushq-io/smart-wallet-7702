// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {MockTarget} from "../mocks/MockTarget.sol";
import {UseEntryPointV09} from "./entrypoint/UseEntryPointV09.sol";
import {SmartWalletTestBase} from "./SmartWalletTestBase.sol";
import {SmartAccount7702} from "../../src/SmartAccount7702.sol";

/// @dev Abstract test logic for execute(). Concrete classes provide the EntryPoint version.
abstract contract TestExecuteBase is SmartWalletTestBase {
    // from Solady tests
    // https://github.com/Vectorized/solady/blob/21009ce09f02c0e20ce4750b63577e8c0cc7ced8/test/ERC4337.t.sol#L122
    function testExecute() public {
        vm.deal(address(account), 1 ether);

        address target = address(new MockTarget());
        bytes memory data = _randomBytes(111);

        // Direct call from the account itself (simulating EOA calling its own delegated code)
        vm.prank(address(account));
        account.execute(target, 123, abi.encodeWithSignature("setData(bytes)", data));
        assertEq(MockTarget(target).datahash(), keccak256(data));
        assertEq(target.balance, 123);

        // Random address should be rejected
        vm.prank(makeAddr("random"));
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        account.execute(target, 123, abi.encodeWithSignature("setData(bytes)", data));

        // Reverts from target should bubble up
        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSignature("TargetError(bytes)", data));
        account.execute(target, 123, abi.encodeWithSignature("revertWithTargetError(bytes)", data));
    }

    function testExecute_viaEntryPoint() public {
        vm.deal(address(account), 1 ether);

        address target = address(new MockTarget());
        bytes memory data = _randomBytes(111);

        // Execute through EntryPoint via UserOp
        userOpCalldata =
            abi.encodeCall(SmartAccount7702.execute, (target, 123, abi.encodeWithSignature("setData(bytes)", data)));
        _sendUserOperation(_getUserOpWithSignature());

        assertEq(MockTarget(target).datahash(), keccak256(data));
        assertEq(target.balance, 123);
    }
}

/// @dev Runs execute tests against EntryPoint v0.9.
contract TestExecute is TestExecuteBase, UseEntryPointV09 {}
