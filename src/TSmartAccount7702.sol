// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignerEIP7702} from "@openzeppelin/contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @title TSmartAccount7702
///
/// @notice Minimal ERC-4337 smart account designed for EIP-7702 delegation.
///
/// @dev With EIP-7702, an EOA delegates its code to this contract. `address(this)` is the EOA
///      itself, so owner management is unnecessary. The EOA's private key is the sole authority.
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
///
///      Re-entrancy protection is provided by access control rather than a `nonReentrant` mutex.
///      `execute()` and `deployDeterministic()` perform external calls but are gated by
///      `onlyEntryPointOrSelf`: a re-entrant call from the target would have `msg.sender` equal
///      to the target address, which is neither the EntryPoint nor `address(this)`, so it reverts.
///      Future maintainers must preserve this invariant: every state-modifying entry point that
///      performs external calls must be protected by `onlyEntryPoint` or `onlyEntryPointOrSelf`.
contract TSmartAccount7702 is ERC7739, SignerEIP7702, IAccount {
    string private constant VERSION = "1.0.0";

    /// @notice The trusted ERC-4337 EntryPoint address, set once at deployment.
    ///
    /// @dev Stored as an immutable baked into the bytecode at construction time,
    ///      shared by all EOAs that delegate to this implementation via EIP-7702.
    ///
    ///      To target a different EntryPoint version, deploy a new implementation with the
    ///      desired address. All delegating EOAs re-point automatically by signing a new
    ///      EIP-7702 authorization tuple.
    address public immutable ENTRY_POINT;

    /// @notice Thrown when the caller is not authorized.
    error Unauthorized(address caller);

    /// @notice Thrown when `deployDeterministic` is called with empty creation code.
    error EmptyBytecode();

    /// @notice Thrown when the zero address is passed as the EntryPoint to the constructor.
    error EntryPointAddressZero();

    /// @notice Emitted when a contract is deployed via CREATE2.
    event ContractDeployed(address indexed deployed);

    /// @notice Deploys the implementation with a fixed EntryPoint.
    ///
    /// @dev `EIP712` and `ENTRY_POINT` set immutables in bytecode. Both are shared by all
    ///      delegating EOAs and work correctly under EIP-7702.
    ///      The "T" prefix in the domain name stands for "Taurus" (the organization behind this wallet).
    ///      This name is immutable once deployed. All off-chain signing tools must use it exactly.
    ///
    /// @param entryPoint_ The EntryPoint address this implementation will trust.
    ///                    Must not be the zero address. Passing address(0) permanently bricks
    ///                    the account since no caller can ever satisfy `msg.sender == address(0)`.
    constructor(address entryPoint_) EIP712("TSmart Account 7702", "1") {
        require(entryPoint_ != address(0), EntryPointAddressZero());
        ENTRY_POINT = entryPoint_;
    }

    /// @notice Reverts if the caller is not the EntryPoint.
    modifier onlyEntryPoint() {
        require(msg.sender == ENTRY_POINT, Unauthorized(msg.sender));
        _;
    }

    /// @notice Reverts if the caller is neither the EntryPoint nor the account itself.
    ///
    /// @dev With EIP-7702, `address(this)` is the EOA. When the EOA sends a normal transaction
    ///      to itself, `msg.sender == address(this)`, allowing direct execution without the EntryPoint.
    modifier onlyEntryPointOrSelf() {
        require(msg.sender == ENTRY_POINT || msg.sender == address(this), Unauthorized(msg.sender));
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
        // Validate the signature before paying the prefund. Since _rawSignatureValidation
        // (ecrecover-based) never reverts (it only returns true or false), so checking first
        // avoids sending ETH to the EntryPoint on SIG_VALIDATION_FAILED. On an invalid
        // signature the EntryPoint retains the prefund to cover the bundler's gas cost, so
        // skipping the payment saves the account ETH for UserOps that will never execute.
        //
        // The ERC-4337 protocol places the responsibility for not submitting failing UserOps
        // on the bundler and EntryPoint (via simulation), not on the account. The account
        // should still minimise unnecessary ETH exposure in the validation path.
        //
        // Recover signer and verify it's the EOA itself.
        // _rawSignatureValidation (from SignerEIP7702) returns false on invalid signatures
        // instead of reverting, which lets us return 1 (SIG_VALIDATION_FAILED) for bundler
        // simulation support.
        if (!_rawSignatureValidation(userOpHash, userOp.signature)) {
            return 1;
        }

        // Pay prefund to the EntryPoint if required. When a paymaster sponsors the UserOp,
        // missingAccountFunds is 0 and this is a no-op. When self-funding, the account
        // sends the required ETH to the EntryPoint (caller).
        //
        // The call's return value is intentionally discarded (`pop`). If the transfer fails
        // (e.g. insufficient balance), the EntryPoint is trusted to catch the shortfall in
        // its own post-validation balance accounting and revert the entire UserOp.
        if (missingAccountFunds > 0) {
            assembly ("memory-safe") {
                pop(call(gas(), caller(), missingAccountFunds, 0x00, 0x00, 0x00, 0x00))
            }
        }

        return 0;
    }

    /// @notice Executes a call from this account.
    ///
    /// @dev Can only be called by the EntryPoint or the account itself (direct EOA transaction).
    ///
    ///      Return data from the nested call is intentionally discarded. The EntryPoint does not
    ///      use the return value of `execute`, and all major ERC-4337 implementations follow the
    ///      same convention. Callers that require return data in the direct self-call path should
    ///      override this function (it is `virtual`) or call the target directly.
    ///
    /// @param target The address to call.
    /// @param value  The value to send with the call.
    /// @param data   The data of the call.
    function execute(address target, uint256 value, bytes calldata data) external payable virtual onlyEntryPointOrSelf {
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
        require(creationCode.length != 0, EmptyBytecode());
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

    /// @notice Returns the contract version string.
    function version() external pure virtual returns (string memory) {
        return VERSION;
    }

    /// @notice Returns the address of the trusted EntryPoint.
    function entryPoint() public view virtual returns (address) {
        return ENTRY_POINT;
    }

    /// @notice ERC-165 interface detection.
    ///
    /// @dev Supports IAccount (ERC-4337), ERC-1271, token receiver interfaces, and ERC-165 itself.
    ///
    ///      ERC-7739 is intentionally absent: the standard defines no new function signatures,
    ///      so there is no ERC-165 interface ID to advertise. ERC-7739 support is detected by
    ///      calling `isValidSignature(0x7739...7739, "")` and checking for the `0x77390001`
    ///      return value, not via ERC-165.
    ///
    ///      This contract implements the ERC-4337 v0.8/v0.9 `IAccount` interface, which uses
    ///      `PackedUserOperation` (interface ID `0x19822f7c`). The legacy v0.6/v0.7 `IAccount`
    ///      interface, which uses the unpacked `UserOperation` struct (interface ID `0x3a871cdd`),
    ///      is NOT supported. EntryPoint v0.6 and v0.7 are incompatible with this contract.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IAccount).interfaceId // 0x19822f7c
            || interfaceId == type(IERC1271).interfaceId // ERC-1271
            || interfaceId == type(IERC721Receiver).interfaceId // IERC721Receiver
            || interfaceId == type(IERC1155Receiver).interfaceId // IERC1155Receiver
            || interfaceId == type(IERC165).interfaceId; // ERC-165
    }

    // ─── Token Receiver Callbacks
    // ────────────────────────────────────
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
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev Accepts ERC-1155 safe transfers. Returns the `onERC1155Received` magic value.
    ///      Accepts tokens from any operator unconditionally. Since this function is `pure`,
    ///      there is no re-entrancy vector from the callback.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @dev Accepts ERC-1155 safe batch transfers. Returns the `onERC1155BatchReceived` magic value.
    ///      Accepts tokens from any operator unconditionally. Since this function is `pure`,
    ///      there is no re-entrancy vector from the callback.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @dev Executes a call and bubbles up revert data on failure.
    ///      Uses assembly to copy calldata into memory and forward it via CALL,
    ///      avoiding a Solidity ABI-encode round-trip for large payloads.
    function _call(address target, uint256 value, bytes calldata data) internal {
        // Memory-safe: writes beyond the free memory pointer but no Solidity code
        // runs after the assembly block. The function either succeeds silently or reverts.
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
    receive() external payable {
        // Intentionally empty: ETH accepted unconditionally.
    }

    /// @dev Allows the account to receive ETH with data and handles unknown selectors.
    fallback() external payable {
        // Intentionally empty: unknown calls accepted to maintain EOA-equivalent behavior.
    }
}
