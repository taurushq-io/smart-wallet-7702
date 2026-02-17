// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./SmartWalletTestBase.sol";

contract TestEthReception is SmartWalletTestBase {
    /// @dev Plain ETH transfer triggers `receive()`.
    function test_receiveEth_plainTransfer() public {
        vm.deal(address(this), 2 ether);

        uint256 balanceBefore = address(account).balance;

        (bool success,) = address(account).call{value: 1 ether}("");
        assertTrue(success, "plain ETH transfer should succeed");

        assertEq(address(account).balance, balanceBefore + 1 ether);
    }

    /// @dev ETH transfer with arbitrary calldata triggers `fallback()`.
    function test_fallback_ethWithData() public {
        vm.deal(address(this), 2 ether);

        uint256 balanceBefore = address(account).balance;

        (bool success,) = address(account).call{value: 1 ether}(hex"deadbeef");
        assertTrue(success, "ETH transfer with data should succeed via fallback");

        assertEq(address(account).balance, balanceBefore + 1 ether);
    }

    /// @dev Call with non-matching selector and no value triggers `fallback()`.
    function test_fallback_noValueArbitraryData() public {
        (bool success,) = address(account).call(hex"cafebabe");
        assertTrue(success, "call with arbitrary data should succeed via fallback");
    }

    /// @dev Zero-value plain call triggers `receive()`.
    function test_receiveEth_zeroValue() public {
        (bool success,) = address(account).call{value: 0}("");
        assertTrue(success, "zero-value plain call should succeed");
    }
}
