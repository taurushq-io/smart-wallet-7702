// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {SignerEIP7702} from "@openzeppelin/contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title SmartAccount7702
///
/// @notice Minimal ERC-4337 smart account designed for EIP-7702 delegation.
///
/// @dev With EIP-7702, an EOA delegates its code to this contract. `address(this)` is the EOA
///      itself, so owner management is unnecessary — the EOA's private key is the sole authority.
///
///      This account is designed to be used exclusively with a paymaster (e.g. Circle USDC Paymaster)
///      for gas sponsorship. The account does not hold ETH for gas and does not implement prefund
///      logic. The `missingAccountFunds` parameter in `validateUserOp` is ignored because the
///      paymaster covers all gas costs (missingAccountFunds == 0 when a paymaster is present).
///
///      Upgradeability is handled natively by EIP-7702: the EOA can re-delegate to a new
///      implementation at any time by signing a new authorization tuple. No UUPS proxy is needed.
///
///      This contract provides `receive()` and `fallback()` functions. This is essential:
///      with EIP-7702, the EOA has code, so plain ETH transfers require a `receive()` function
///      to succeed. Without it, the delegating EOA would be unable to receive ETH.
contract SmartAccount7702 is ERC7739, SignerEIP7702, IAccount, Initializable {
    /// @notice Represents a call to make.
    struct Call {
        /// @dev The address to call.
        address target;
        /// @dev The value to send when making the call.
        uint256 value;
        /// @dev The data of the call.
        bytes data;
    }

    /// @notice Thrown when the caller is not authorized.
    error Unauthorized();

    /// @notice The EntryPoint address this account trusts for UserOp validation.
    /// @dev Set via `initialize()`, stored in the delegating EOA's storage.
    ///      Each EOA can configure its own EntryPoint after delegating to this implementation.
    address private _entryPoint;

    /// @notice Deploys the implementation and disables initialization on it.
    /// @dev `EIP712` sets immutables (name/version hashes) in bytecode — these are shared by all
    ///      delegating EOAs and work correctly under EIP-7702.
    ///      `_disableInitializers()` prevents `initialize()` from being called on the implementation
    ///      contract itself. Each delegating EOA has clean storage and can call `initialize()` once.
    constructor() EIP712("TSmart Account 7702", "1") {
        _disableInitializers();
    }

    /// @notice Initializes the account with the trusted EntryPoint address.
    /// @dev Must be called once after EIP-7702 delegation. The `initializer` modifier ensures
    ///      this can only be called once per storage context (i.e., once per delegating EOA).
    /// @param entryPoint_ The EntryPoint address this account will trust.
    function initialize(address entryPoint_) external initializer {
        _entryPoint = entryPoint_;
    }

    /// @notice Reverts if the caller is not the EntryPoint.
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint()) revert Unauthorized();
        _;
    }

    /// @notice Reverts if the caller is neither the EntryPoint nor the account itself.
    ///
    /// @dev With EIP-7702, `address(this)` is the EOA. When the EOA sends a normal transaction
    ///      to itself, `msg.sender == address(this)`, allowing direct execution without the EntryPoint.
    modifier onlyEntryPointOrSelf() {
        if (msg.sender != entryPoint() && msg.sender != address(this)) {
            revert Unauthorized();
        }
        _;
    }

    /// @inheritdoc IAccount
    ///
    /// @notice Validates the UserOperation signature.
    ///
    /// @dev Recovers the ECDSA signer from `userOp.signature` and verifies it matches
    ///      `address(this)` (the EOA that delegated to this contract via EIP-7702).
    ///      Returns 1 on signature failure to allow simulation calls without a valid signature.
    ///
    /// @dev This account is paymaster-only: it does not hold ETH for gas and does not pay
    ///      `missingAccountFunds` to the EntryPoint. When a paymaster is used,
    ///      `missingAccountFunds` is always 0. If a bundler submits a UserOp without a paymaster,
    ///      the EntryPoint will revert during its own balance check — the account intentionally
    ///      does not pay prefund.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        onlyEntryPoint
        returns (uint256 validationData)
    {
        // Paymaster-only: this account never pays prefund. If no paymaster is attached,
        // missingAccountFunds > 0 and the EntryPoint will revert during its balance check.
        // This is intentional — the account is designed exclusively for paymaster-sponsored flows.
        (missingAccountFunds);

        // Recover signer and verify it's the EOA itself.
        // _rawSignatureValidation (from SignerEIP7702) returns false on invalid signatures
        // instead of reverting, which lets us return 1 (SIG_VALIDATION_FAILED) for bundler
        // simulation support.
        if (!_rawSignatureValidation(userOpHash, userOp.signature)) {
            return 1;
        }

        return 0;
    }

    /// @notice Executes a call from this account.
    ///
    /// @dev Can only be called by the EntryPoint or the account itself (direct EOA transaction).
    ///
    /// @param target The address to call.
    /// @param value  The value to send with the call.
    /// @param data   The data of the call.
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        virtual
        onlyEntryPointOrSelf
    {
        _call(target, value, data);
    }

    /// @notice Executes a batch of calls from this account.
    ///
    /// @dev Can only be called by the EntryPoint or the account itself (direct EOA transaction).
    ///
    /// @param calls The list of `Call`s to execute.
    function executeBatch(Call[] calldata calls) external payable virtual onlyEntryPointOrSelf {
        for (uint256 i; i < calls.length; i++) {
            _call(calls[i].target, calls[i].value, calls[i].data);
        }
    }

    /// @notice Returns the address of the trusted EntryPoint.
    function entryPoint() public view virtual returns (address) {
        return _entryPoint;
    }

    /// @notice ERC-165 interface detection.
    ///
    /// @dev Supports IAccount (ERC-4337), ERC-1271, and ERC-165 itself.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAccount).interfaceId // 0x3a871cdd
            || interfaceId == bytes4(0x1626ba7e) // ERC-1271
            || interfaceId == bytes4(0x77390001) // ERC-7739
            || interfaceId == bytes4(0x01ffc9a7); // ERC-165
    }

    /// @dev Executes a call and bubbles up revert data on failure.
    ///      Uses assembly to forward calldata directly without copying to memory,
    ///      saving gas on large payloads.
    function _call(address target, uint256 value, bytes calldata data) internal {
        assembly ("memory-safe") {
            let m := mload(0x40)
            calldatacopy(m, data.offset, data.length)
            let success := call(gas(), target, value, m, data.length, codesize(), 0x00)
            if iszero(success) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
        }
    }

    /// @dev Allows the account to receive ETH.
    receive() external payable {}

    /// @dev Allows the account to receive ETH with data and handle unknown function calls.
    fallback() external payable {}
}
