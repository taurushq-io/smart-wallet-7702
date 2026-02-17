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

- **159 tests** across 26 suites, all passing
- **Dual EntryPoint testing**: all `handleOps`-routed tests run against both EntryPoint v0.9.0 and v0.8.0 via abstract test contracts and `UseEntryPointV09` / `UseEntryPointV08` mixins
- **15 fuzz tests** (256 runs each): signature validation, prefund payment, PersonalSign, TypedDataSign, execute, executeBatch, deployDeterministic, supportsInterface
- **14 adversarial tests** (28 total with dual EntryPoint): front-running initialize, unauthorized execution, ETH/token theft, re-initialization, signature replay, cross-account replay, uninitialized account, callback attack
- **Deploy script tests** (8 tests): salt derivation, CREATE2 address prediction, initializer locking, interface support, EIP-712 domain, bytecode verification
- **Walkthrough tests**: step-by-step ERC-20 transfer (simple + paymaster), contract deployment (CREATE + CREATE2)
- **Gas profiling**: end-to-end gas comparison (smart account vs raw EOA) with and without paymaster
- **ERC-7201 verification**: on-chain computation of namespaced storage slot matches hardcoded constant

### Test Quality

- No hardcoded private keys: all test keys derived via Foundry's `makeAddrAndKey("label")` or `makeAddr("label")`
- No hardcoded hashes: arbitrary test hashes computed on-chain via `keccak256("...")` (e.g., `keccak256("test message")` instead of opaque hex literals)
- Interface ID verification: `supportsInterface` tests use `type(Interface).interfaceId` from OpenZeppelin imports, independently verifying the source code's hardcoded values
- Zero compiler warnings: deprecated `memory-safe-assembly` NatSpec replaced with `assembly ("memory-safe")`, `.transfer()` replaced with `.call{value:}("")`, `view` added to pure-read test functions

### Deployment

- `DeploySmartAccount7702.s.sol` — deterministic CREATE2 deployment script with known salt (`keccak256("TSmart Account 7702 v1")`)

### Static Analysis

- **Aderyn** ([Cyfrin](https://github.com/Cyfrin/aderyn)): 1 high (false positive — locked ETH), 4 low (all acknowledged or false positive). Reports in `doc/audit/tool/aderyn/`.
- **Slither** ([Trail of Bits](https://github.com/crytic/slither)): 0 high/medium/low, 5 informational (assembly usage — all intentional). Reports in `doc/audit/tool/slither/`.

### Documentation

- `doc/fuzzing.md` — fuzz testing methodology and fuzzed variable documentation
- `doc/create-contract.md` — how the EntryPoint calls `executeBatch` and other account functions
- `doc/ACCOUNT_EXECUTE.md` — design rationale for not using `IAccountExecute`
- `doc/audit/` — static analysis reports and feedback (Aderyn, Slither)

### Dependencies

- OpenZeppelin Contracts: `ERC7739`, `SignerEIP7702`, `EIP712`, `Initializable`
- `account-abstraction` v0.9.0: `IAccount`, `PackedUserOperation`, `EntryPoint`
- `account-abstraction` v0.8.0: `EntryPoint` (for cross-version compatibility testing)
- Foundry (forge, cast, anvil): build, test, deploy
