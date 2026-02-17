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
///      The account supports both paymaster-sponsored and self-funded UserOperations.
///      When a paymaster is present, `missingAccountFunds` is 0 and no ETH is needed.
///      When no paymaster is used, the account pays the required prefund from its ETH balance.
///
///      Upgradeability is handled natively by EIP-7702: the EOA can re-delegate to a new
///      implementation at any time by signing a new authorization tuple. No UUPS proxy is needed.
///
///      This contract provides `receive()` and `fallback()` functions. This is essential:
///      with EIP-7702, the EOA has code, so plain ETH transfers require a `receive()` function
///      to succeed. Without it, the delegating EOA would be unable to receive ETH.
contract SmartAccount7702 is ERC7739, SignerEIP7702, IAccount, Initializable {
    /// @notice Thrown when the caller is not authorized.
    error Unauthorized();

    /// @notice Thrown when `deployDeterministic` is called with empty creation code.
    error EmptyBytecode();

    /// @notice Emitted when the account is initialized with an EntryPoint.
    /// @dev Named `EntryPointSet` (not `Initialized`) to avoid shadowing OZ's
    ///      `Initializable.Initialized(uint64 version)` which is also emitted during `initialize()`.
    event EntryPointSet(address indexed entryPoint);

    /// @notice Emitted when a contract is deployed via CREATE2.
    event ContractDeployed(address indexed deployed);

    /// @custom:storage-location erc7201:smartaccount7702.entrypoint
    struct EntryPointStorage {
        address entryPoint;
    }

    /// @dev ERC-7201 namespaced storage slot for `EntryPointStorage`.
    ///      keccak256(abi.encode(uint256(keccak256("smartaccount7702.entrypoint")) - 1)) & ~bytes32(uint256(0xff))
    ///
    ///      Using ERC-7201 prevents slot collisions under EIP-7702 re-delegation: if an EOA
    ///      previously delegated to another implementation that wrote to low slots (0, 1, ...),
    ///      re-delegating to this contract would misinterpret that data as an EntryPoint address.
    ///      The namespaced slot is derived from a unique string, making collision practically impossible.
    bytes32 private constant ENTRY_POINT_STORAGE_LOCATION =
        0x38a124a88e3a590426742b6544792c2b2bc21792f86c1fa1375b57726d827a00;

    /// @notice Deploys the implementation and disables initialization on it.
    /// @dev `EIP712` sets immutables (name/version hashes) in bytecode — these are shared by all
    ///      delegating EOAs and work correctly under EIP-7702.
    ///      `_disableInitializers()` prevents `initialize()` from being called on the implementation
    ///      contract itself. Each delegating EOA has clean storage and can call `initialize()` once.
    ///      The "T" prefix in the domain name stands for "Taurus" (the organization behind this wallet).
    ///      This name is immutable once deployed — all off-chain signing tools must use it exactly.
    constructor() EIP712("TSmart Account 7702", "1") {
        _disableInitializers();
    }

    /// @notice Initializes the account with the trusted EntryPoint address.
    ///
    /// @dev Must be called once after EIP-7702 delegation. Only the EOA itself can call this
    ///      (`msg.sender == address(this)`), which prevents front-running attacks where an
    ///      attacker sets a malicious EntryPoint before the owner.
    ///
    ///      In the EIP-7702 flow, the EOA signs a type-4 transaction that includes both the
    ///      authorization tuple (setting the code) and a call to `initialize()` as calldata
    ///      (with `to = address(this)`). This makes delegation and initialization atomic.
    ///
    /// @param entryPoint_ The EntryPoint address this account will trust.
    function initialize(address entryPoint_) external initializer {
        if (msg.sender != address(this)) revert Unauthorized();
        _getEntryPointStorage().entryPoint = entryPoint_;
        emit EntryPointSet(entryPoint_);
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
    /// @dev The account supports both paymaster-sponsored and self-funded UserOperations:
    ///
    ///      - **With paymaster**: `missingAccountFunds` is 0, no ETH needed from the account.
    ///      - **Self-funded**: The account pays `missingAccountFunds` to the EntryPoint from
    ///        its ETH balance. If the account has insufficient ETH, the EntryPoint reverts.
    ///
    ///      Paying prefund ensures the wallet remains functional even if the paymaster goes
    ///      offline or is discontinued. Without this, the wallet would be completely dependent
    ///      on a third-party paymaster service for all UserOperation flows. The EOA can always
    ///      fall back to self-funding by holding ETH.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        onlyEntryPoint
        returns (uint256 validationData)
    {
        // Pay prefund to the EntryPoint if required. When a paymaster sponsors the UserOp,
        // missingAccountFunds is 0 and this is a no-op. When self-funding, the account
        // sends the required ETH to the EntryPoint (caller).
        //
        // The call's return value is intentionally discarded (`pop`). If the transfer fails
        // (e.g. insufficient balance), the EntryPoint is trusted to catch the shortfall in
        // its own post-validation balance accounting and revert the entire UserOp.
        // This is the standard ERC-4337 prefund pattern (used by Coinbase, Solady, etc.).
        if (missingAccountFunds > 0) {
            assembly ("memory-safe") {
                pop(call(gas(), caller(), missingAccountFunds, 0x00, 0x00, 0x00, 0x00))
            }
        }

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

    /// @notice Deploys a contract using CREATE2 (deterministic address).
    ///
    /// @dev Can only be called by the EntryPoint or the account itself.
    ///      The deployed address is determined by `(address(this), salt, keccak256(creationCode))`.
    ///      Since `address(this)` is the EOA under EIP-7702, the deployer is the EOA itself.
    ///
    /// @param value        The ETH value to send to the new contract's constructor.
    /// @param creationCode The contract creation bytecode (bytecode + constructor args).
    /// @param salt         The salt for CREATE2 address derivation.
    ///
    /// @return deployed The address of the newly deployed contract.
    function deployDeterministic(uint256 value, bytes calldata creationCode, bytes32 salt)
        external
        payable
        virtual
        onlyEntryPointOrSelf
        returns (address deployed)
    {
        if (creationCode.length == 0) revert EmptyBytecode();
        // Memory-safe: writes beyond the free memory pointer without advancing it.
        // The only Solidity after the assembly is `emit ContractDeployed(deployed)`,
        // which uses only indexed parameters (LOG2 with zero data bytes) and does not
        // allocate memory. `deployed` is on the stack, not in the overwritten area at `m`.
        assembly ("memory-safe") {
            let m := mload(0x40)
            calldatacopy(m, creationCode.offset, creationCode.length)
            deployed := create2(value, m, creationCode.length, salt)
            if iszero(deployed) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
        }
        emit ContractDeployed(deployed);
    }

    /// @notice Returns the address of the trusted EntryPoint.
    function entryPoint() public view virtual returns (address) {
        return _getEntryPointStorage().entryPoint;
    }

    /// @dev Returns the ERC-7201 namespaced storage pointer for `EntryPointStorage`.
    function _getEntryPointStorage() private pure returns (EntryPointStorage storage $) {
        assembly {
            $.slot := ENTRY_POINT_STORAGE_LOCATION
        }
    }

    /// @notice ERC-165 interface detection.
    ///
    /// @dev Supports IAccount (ERC-4337), ERC-1271, ERC-7739, token receiver interfaces,
    ///      and ERC-165 itself.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IAccount).interfaceId // 0x3a871cdd
            || interfaceId == bytes4(0x1626ba7e) // ERC-1271
            || interfaceId == bytes4(0x77390001) // ERC-7739
            || interfaceId == bytes4(0x150b7a02) // IERC721Receiver
            || interfaceId == bytes4(0x4e2312e0) // IERC1155Receiver
            || interfaceId == bytes4(0x01ffc9a7); // ERC-165
    }

    // ─── Token Receiver Callbacks ────────────────────────────────────
    //
    // Under EIP-7702, the EOA has code, so ERC-721 `safeTransferFrom` and ERC-1155
    // transfers invoke receiver callbacks. Without these, the ABI decoder fails on the
    // empty `fallback()` return data and the transfer reverts.
    //
    // ERC-1155 has NO non-safe transfer function, so without `onERC1155Received` the
    // wallet cannot receive ANY ERC-1155 tokens.

    /// @dev Accepts ERC-721 safe transfers. Returns the `onERC721Received` magic value.
    ///      Accepts tokens from any operator unconditionally. Since this function is `pure`
    ///      (no state reads or writes), there is no re-entrancy vector from the callback.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    /// @dev Accepts ERC-1155 safe transfers. Returns the `onERC1155Received` magic value.
    ///      Accepts tokens from any operator unconditionally. Since this function is `pure`,
    ///      there is no re-entrancy vector from the callback.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return 0xf23a6e61;
    }

    /// @dev Accepts ERC-1155 safe batch transfers. Returns the `onERC1155BatchReceived` magic value.
    ///      Accepts tokens from any operator unconditionally. Since this function is `pure`,
    ///      there is no re-entrancy vector from the callback.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return 0xbc197c81;
    }

    /// @dev Executes a call and bubbles up revert data on failure.
    ///      Uses assembly to forward calldata directly without copying to memory,
    ///      saving gas on large payloads.
    function _call(address target, uint256 value, bytes calldata data) internal {
        // Memory-safe: writes beyond the free memory pointer but no Solidity code
        // runs after the assembly block — the function either succeeds silently or reverts.
        // Skipping `mstore(0x40, ...)` saves gas.
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
