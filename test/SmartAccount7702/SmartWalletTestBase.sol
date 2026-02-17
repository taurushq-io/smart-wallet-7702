// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Test, console2, stdError} from "forge-std/Test.sol";

import "../../src/SmartAccount7702.sol";

/// @dev Abstract test base for SmartAccount7702 tests.
///      Subclasses must provide the EntryPoint bytecode via `_deployEntryPoint()`.
///      This allows running the same tests against different EntryPoint versions.
abstract contract SmartWalletTestBase is Test {
    SmartAccount7702 public account;
    uint256 signerPrivateKey;
    address signer;
    IEntryPoint entryPoint = IEntryPoint(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);
    address bundler = makeAddr("bundler");

    // userOp values
    uint256 userOpNonce;
    bytes userOpCalldata;

    /// @dev Override to deploy the EntryPoint implementation at the canonical address.
    function _deployEntryPoint() internal virtual;

    function setUp() public virtual {
        (signer, signerPrivateKey) = makeAddrAndKey("alice");

        // Deploy EntryPoint at canonical address (version determined by subclass)
        _deployEntryPoint();

        // Simulate EIP-7702 delegation: deploy SmartAccount7702, then etch its runtime
        // bytecode (including immutables) onto the signer's EOA. This makes
        // address(this) == signer when the contract code runs, which is exactly what
        // happens with a real 7702 authorization tuple.
        SmartAccount7702 impl = new SmartAccount7702();
        vm.etch(signer, address(impl).code);
        account = SmartAccount7702(payable(signer));
        vm.prank(signer);
        account.initialize(address(entryPoint));
    }

    function _sendUserOperation(PackedUserOperation memory userOp) internal {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.prank(bundler, bundler);
        entryPoint.handleOps(ops, payable(bundler));
    }

    function _getUserOp() internal view returns (PackedUserOperation memory userOp) {
        userOp = PackedUserOperation({
            sender: address(account),
            nonce: userOpNonce,
            initCode: "",
            callData: userOpCalldata,
            accountGasLimits: bytes32(uint256(1_000_000) << 128 | uint256(1_000_000)),
            preVerificationGas: uint256(0),
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: ""
        });
    }

    function _getUserOpWithSignature() internal view returns (PackedUserOperation memory userOp) {
        userOp = _getUserOp();
        userOp.signature = _sign(userOp);
    }

    /// @dev Signs a UserOp with the signer's private key. Raw ECDSA signature (no SignatureWrapper).
    function _sign(PackedUserOperation memory userOp) internal view virtual returns (bytes memory signature) {
        bytes32 toSign = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, toSign);
        signature = abi.encodePacked(r, s, v);
    }

    function _randomBytes(uint256 seed) internal pure returns (bytes memory result) {
        assembly ("memory-safe") {
            mstore(0x00, seed)
            let r := keccak256(0x00, 0x20)
            if lt(byte(2, r), 0x20) {
                result := mload(0x40)
                let n := and(r, 0x7f)
                mstore(result, n)
                codecopy(add(result, 0x20), byte(1, r), add(n, 0x40))
                mstore(0x40, add(add(result, 0x40), n))
            }
        }
    }
}
