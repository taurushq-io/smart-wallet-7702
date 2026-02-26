# Changelog

## [0.3.0] — 2026-02-26

### Changed

- **Contract renamed** from `SmartAccount7702` to `TSmartAccount7702`. The `T` prefix reflects the Taurus organization. All file names, test directories, and script files updated accordingly.
- **Solidity updated** from `0.8.33` to `0.8.34`.

### Added

- **`version()`**: Returns the contract version string (`"0.3.0"`). Declared `external pure virtual` to allow overrides in derived contracts.

## [0.2.0] — 2026-02-18

### Removed

- **`executeBatch`**: Removed batch execution function and the `Call` struct. Use `execute` for single calls via UserOps or direct EOA transactions.
- **`deploy`** (CREATE): Removed non-deterministic contract deployment. Use `deployDeterministic` (CREATE2) instead — addresses are pre-computable and consistent across chains.

### Updated

- Tests: removed ExecuteBatch and CREATE test suites, updated walkthrough and fuzz tests

## [0.1.0] — 2026-02-17

Initial release of TSmartAccount7702 — a minimal ERC-4337 smart account for EIP-7702 delegation.

### Core Contract

- **`SmartAccount7702.sol`** — single-file ERC-4337 account
- EIP-7702 delegation: `address(this)` is the EOA, single-owner by design
- `validateUserOp` with ECDSA recovery against `address(this)`
- `execute` / `executeBatch` / `deploy` / `deployDeterministic`
- ERC-1271 + ERC-7739 signature validation (PersonalSign + TypedDataSign)
- ERC-721 and ERC-1155 token receiver callbacks
- Dual gas model: paymaster-sponsored or self-funded
- Per-EOA EntryPoint via `initialize()` with front-running protection
- ERC-7201 namespaced storage for EntryPoint address

### Architecture

- **Inheritance**: `ERC7739` + `SignerEIP7702` + `IAccount` + `Initializable` (all OpenZeppelin)
- **EIP-712 domain**: `"TSmart Account 7702"` version `"1"`
- **No UUPS proxy** — EIP-7702 re-delegation is the native upgrade mechanism
- **No factory** — EOA delegates directly to the implementation

### Test Suite

- Dual EntryPoint testing (v0.9.0 + v0.8.0)
- Fuzz tests, adversarial tests, walkthroughs, gas profiling
- Deploy script verification
- Zero compiler warnings, no hardcoded keys or hashes in tests

### Static Analysis

- **Aderyn**: 1 high (false positive), 4 low (acknowledged). See `doc/audit/tool/aderyn/`.
- **Slither**: 0 issues, 5 informational (assembly — intentional). See `doc/audit/tool/slither/`.

### Deployment

- `DeploySmartAccount7702.s.sol` — deterministic CREATE2 with salt `keccak256("TSmart Account 7702 v1")`

### Dependencies

- OpenZeppelin Contracts: `ERC7739`, `SignerEIP7702`, `EIP712`, `Initializable`
- `account-abstraction` v0.9.0 + v0.8.0
- Foundry (forge, cast, anvil)
