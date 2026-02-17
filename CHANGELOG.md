# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] — 2026-02-17

Initial release of SmartAccount7702 — a minimal ERC-4337 smart account for EIP-7702 delegation.

### Core Contract

- **`SmartAccount7702.sol`** (~336 lines) — single-file ERC-4337 account
  - EIP-7702 delegation model: `address(this)` is the EOA, no multi-owner management needed
  - `validateUserOp` with ECDSA signature recovery against `address(this)`
  - `execute` / `executeBatch` for single and batch call execution
  - `deploy` / `deployDeterministic` for CREATE / CREATE2 contract deployment
  - ERC-1271 signature validation with ERC-7739 anti-replay (PersonalSign + TypedDataSign)
  - ERC-721 and ERC-1155 token receiver callbacks (`onERC721Received`, `onERC1155Received`, `onERC1155BatchReceived`)
  - Dual gas model: supports both paymaster-sponsored and self-funded UserOperations
  - Per-EOA EntryPoint via `initialize()` with front-running protection (`msg.sender == address(this)`)
  - ERC-7201 namespaced storage for EntryPoint address (prevents slot collision under re-delegation)

### Architecture

- **Inheritance**: `ERC7739` (OZ) + `SignerEIP7702` (OZ) + `IAccount` (ERC-4337) + `Initializable` (OZ)
- **EIP-712 domain**: `"TSmart Account 7702"` version `"1"` (immutable in bytecode)
- **Access control**: `onlyEntryPoint` for validation, `onlyEntryPointOrSelf` for execution/deployment
- **Initialization**: Proxy-style `initializer` pattern adapted for EIP-7702; `_disableInitializers()` locks the implementation
- **No UUPS proxy**: EIP-7702 re-delegation is the native upgrade mechanism
- **No factory**: EOA delegates directly to the implementation contract

### Test Suite

- **137 tests** across 24 suites, all passing
- **Dual EntryPoint testing**: all `handleOps`-routed tests run against both EntryPoint v0.9.0 and v0.8.0 via abstract test contracts and `UseEntryPointV09` / `UseEntryPointV08` mixins
- **15 fuzz tests** (256 runs each): signature validation, prefund payment, PersonalSign, TypedDataSign, execute, executeBatch, deployDeterministic, supportsInterface
- **14 adversarial tests**: front-running initialize, unauthorized execution, ETH/token theft, re-initialization, signature replay, cross-account replay, uninitialized account, callback attack
- **Walkthrough tests**: step-by-step ERC-20 transfer (simple + paymaster), contract deployment (CREATE + CREATE2)
- **Gas profiling**: end-to-end gas comparison (smart account vs raw EOA) with and without paymaster
- **ERC-7201 verification**: on-chain computation of namespaced storage slot matches hardcoded constant

### Deployment

- `DeploySmartAccount7702.s.sol` — deterministic CREATE2 deployment script with known salt (`keccak256("TSmart Account 7702 v1")`)

### Dependencies

- OpenZeppelin Contracts: `ERC7739`, `SignerEIP7702`, `EIP712`, `Initializable`
- `account-abstraction` v0.9.0: `IAccount`, `PackedUserOperation`, `EntryPoint`
- `account-abstraction` v0.8.0: `EntryPoint` (for cross-version compatibility testing)
- Foundry (forge, cast, anvil): build, test, deploy
