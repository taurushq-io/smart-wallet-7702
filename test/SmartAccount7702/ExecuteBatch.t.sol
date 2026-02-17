// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {MockTarget} from "../mocks/MockTarget.sol";
import "./SmartWalletTestBase.sol";

contract TestExecuteBatch is SmartWalletTestBase {
    function testExecuteBatch() public {
        vm.deal(address(account), 1 ether);

        SmartAccount7702.Call[] memory calls = new SmartAccount7702.Call[](2);
        calls[0].target = address(new MockTarget());
        calls[1].target = address(new MockTarget());
        calls[0].value = 123;
        calls[1].value = 456;
        calls[0].data = abi.encodeWithSignature("setData(bytes)", _randomBytes(111));
        calls[1].data = abi.encodeWithSignature("setData(bytes)", _randomBytes(222));

        vm.prank(address(account));
        account.executeBatch(calls);
        assertEq(MockTarget(calls[0].target).datahash(), keccak256(_randomBytes(111)));
        assertEq(MockTarget(calls[1].target).datahash(), keccak256(_randomBytes(222)));
        assertEq(calls[0].target.balance, 123);
        assertEq(calls[1].target.balance, 456);

        calls[1].data = abi.encodeWithSignature("revertWithTargetError(bytes)", _randomBytes(111));
        vm.prank(address(account));
        vm.expectRevert(abi.encodeWithSignature("TargetError(bytes)", _randomBytes(111)));
        account.executeBatch(calls);
    }

    function testExecuteBatch_viaEntryPoint() public {
        vm.deal(address(account), 1 ether);

        SmartAccount7702.Call[] memory calls = new SmartAccount7702.Call[](2);
        calls[0].target = address(new MockTarget());
        calls[1].target = address(new MockTarget());
        calls[0].value = 123;
        calls[1].value = 456;
        calls[0].data = abi.encodeWithSignature("setData(bytes)", _randomBytes(111));
        calls[1].data = abi.encodeWithSignature("setData(bytes)", _randomBytes(222));

        userOpCalldata = abi.encodeCall(SmartAccount7702.executeBatch, (calls));
        _sendUserOperation(_getUserOpWithSignature());

        assertEq(MockTarget(calls[0].target).datahash(), keccak256(_randomBytes(111)));
        assertEq(MockTarget(calls[1].target).datahash(), keccak256(_randomBytes(222)));
        assertEq(calls[0].target.balance, 123);
        assertEq(calls[1].target.balance, 456);
    }

    function testExecuteBatch_revertsWhenNotAuthorized() public {
        SmartAccount7702.Call[] memory calls = new SmartAccount7702.Call[](1);
        calls[0].target = address(new MockTarget());
        calls[0].data = abi.encodeWithSignature("setData(bytes)", _randomBytes(111));

        vm.prank(makeAddr("random"));
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        account.executeBatch(calls);
    }

    function testExecuteBatch_emptyBatch() public {
        // Empty batch succeeds silently — the loop body never executes
        SmartAccount7702.Call[] memory calls = new SmartAccount7702.Call[](0);
        vm.prank(address(account));
        account.executeBatch(calls);
    }
}
