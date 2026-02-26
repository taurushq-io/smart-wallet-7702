// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

/// @title ERC-7201 Storage Location Verification
/// @notice Computes the ERC-7201 namespaced storage slot on-chain and verifies it matches
///         the hardcoded constant in TSmartAccount7702.
///
/// @dev The ERC-7201 formula is:
///      keccak256(abi.encode(uint256(keccak256(id)) - 1)) & ~bytes32(uint256(0xff))
///      where `id` is the namespace string "smartaccount7702.entrypoint".

/// @dev On-chain ERC-7201 slot calculator. Deployed in the test to ensure the computation
///      runs inside the EVM — not just in off-chain tooling.
contract ERC7201Calculator {
    /// @notice Computes the ERC-7201 storage location for a given namespace string.
    /// @param id The namespace string (e.g. "smartaccount7702.entrypoint").
    /// @return slot The ERC-7201 storage slot.
    function computeSlot(string memory id) external pure returns (bytes32 slot) {
        // Step 1: keccak256(id)
        bytes32 idHash = keccak256(bytes(id));

        // Step 2: uint256(idHash) - 1
        uint256 minusOne = uint256(idHash) - 1;

        // Step 3: keccak256(abi.encode(minusOne))
        bytes32 outerHash = keccak256(abi.encode(minusOne));

        // Step 4: mask with ~bytes32(uint256(0xff))  (zero out the last byte)
        slot = outerHash & ~bytes32(uint256(0xff));
    }
}

contract TestStorageLocation is Test {
    /// @dev The hardcoded value from TSmartAccount7702.sol
    bytes32 internal constant EXPECTED_SLOT =
        0x38a124a88e3a590426742b6544792c2b2bc21792f86c1fa1375b57726d827a00;

    /// @dev The namespace string used in TSmartAccount7702
    string internal constant NAMESPACE = "smartaccount7702.entrypoint";

    /// @notice Deploys the calculator contract and verifies the on-chain computation
    ///         matches the hardcoded ENTRY_POINT_STORAGE_LOCATION constant.
    function test_entryPointStorageLocation_matchesOnChainComputation() public {
        ERC7201Calculator calculator = new ERC7201Calculator();
        bytes32 computed = calculator.computeSlot(NAMESPACE);

        assertEq(
            computed,
            EXPECTED_SLOT,
            "On-chain ERC-7201 computation must match hardcoded ENTRY_POINT_STORAGE_LOCATION"
        );
    }

    /// @notice Verifies each step of the ERC-7201 derivation independently.
    function test_entryPointStorageLocation_stepByStep() public {
        // Step 1: keccak256("smartaccount7702.entrypoint")
        bytes32 idHash = keccak256(bytes(NAMESPACE));

        // Step 2: uint256(idHash) - 1
        uint256 minusOne = uint256(idHash) - 1;

        // Step 3: keccak256(abi.encode(minusOne))
        bytes32 outerHash = keccak256(abi.encode(minusOne));

        // Step 4: mask — zero the last byte
        bytes32 masked = outerHash & ~bytes32(uint256(0xff));

        // Verify final result
        assertEq(masked, EXPECTED_SLOT, "Step-by-step computation must match");

        // Verify the last byte is indeed 0x00 (ERC-7201 alignment)
        assertEq(uint8(uint256(masked)), 0, "Last byte must be zero (ERC-7201 alignment)");

        // Cross-check with the on-chain calculator
        ERC7201Calculator calculator = new ERC7201Calculator();
        assertEq(calculator.computeSlot(NAMESPACE), masked, "Calculator must agree with step-by-step");
    }
}
