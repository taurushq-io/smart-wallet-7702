// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @dev Simple ERC1155 mock with public mint for testing.
contract MockERC1155 is ERC1155 {
    constructor() ERC1155("https://example.com/{id}.json") {}

    /// @dev Mints without the safe acceptance check, so it always works regardless of receiver.
    function mintUnsafe(address to, uint256 id, uint256 amount) public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        _update(address(0), to, ids, amounts);
    }

    /// @dev Mints with the safe acceptance check (calls onERC1155Received).
    function mint(address to, uint256 id, uint256 amount, bytes memory data) public {
        _mint(to, id, amount, data);
    }

    /// @dev Batch mint without acceptance check.
    function mintBatchUnsafe(address to, uint256[] memory ids, uint256[] memory amounts) public {
        _update(address(0), to, ids, amounts);
    }

    /// @dev Batch mint with acceptance check.
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public {
        _mintBatch(to, ids, amounts, data);
    }
}
