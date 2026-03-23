# Changelog

## [1.0.0] — 2026-03-23

ABDK audit remediation release. All Major and Minor findings addressed; two Moderate findings rejected with documented rationale; one Minor finding not implemented due to compiler limitation.

### Security

- **CVF-1 (Major)**: Replaced OZ `Initializable` with a wallet-local init guard. The `bool initialized` flag is now co-located in `EntryPointStorage` under the contract's own ERC-7201 namespace (`smartaccount7702.entrypoint`), eliminating any shared-slot collision risk from prior EOA delegations. Added `error AlreadyInitialized()`. Removed `_disableInitializers()` from the constructor — the `msg.sender == address(this)` guard on `initialize()` provides equivalent protection. (`9179aaf`)
- **CVF-2 (Moderate)**: `onlyEntryPoint` and `onlyEntryPointOrSelf` now revert with `error NotInitialized()` before performing the caller check, giving operators a clear error when the account has not yet been initialized rather than a misleading `Unauthorized()`. (`84c92fa`)

### Changed

- **CVF-8**: `error Unauthorized()` → `error Unauthorized(address caller)`. All revert sites pass `msg.sender` as the parameter. (`1c3521c`)
- **CVF-6**: Pragma relaxed from `0.8.34` to `^0.8.34` to allow patch-level compiler updates while retaining the minimum version required for Prague EVM / EIP-7702 support. (`f4fa540`)
- **CVF-12**: Magic `bytes4` literals in `supportsInterface` replaced with `type(...).interfaceId` expressions for all standard interfaces. `ERC7739_INTERFACE_ID` named constant added for the draft ERC-7739 interface (no stable Solidity type available). (`5d7232f`)
- **CVF-11**: Inline `"0.3.0"` string in `version()` replaced with `string private constant VERSION`. (`0f863e6`)
- **Version**: Contract version bumped to `"1.0.0"`.

### Documentation

- **CVF-3**: Corrected `_call()` NatSpec — calldata is copied into memory via `calldatacopy` before the nested `CALL`; the previous comment incorrectly stated it was forwarded "without copying to memory". (`8a2573c`)
- **CVF-4**: Added NatSpec to `execute()` documenting that return data from the nested call is intentionally discarded. The EntryPoint does not consume `execute` return values; callers requiring return data in the direct self-call path should override `execute` (declared `virtual`) or call the target directly. (`d5db86b`)
- **CVF-10**: Added `// Intentionally empty:` inline comments to `receive()` and `fallback()`. (`432a390`)

### Not changed

- **CVF-4**: No logic change — return data drop is intentional and consistent with all major ERC-4337 implementations. Documented in NatSpec.
- **CVF-5**: Rejected — wrapping raw revert data in a named error would break ERC-4337 bundler parsing, off-chain tooling, and EIP-7821 compatibility. The wallet's own errors are only ever thrown before `_call` executes, so there is no actual ambiguity.
- **CVF-7**: Out of scope — `IAccount` and `PackedUserOperation` are minimal interface definitions from the audited `account-abstraction` v0.9.0 upstream.
- **CVF-9**: Not implemented — Solidity 0.8.34 rejects expression-form constants in inline assembly `$.slot :=` assignments. A local-variable workaround exists but was intentionally rejected as not worth the added indirection. The literal is verified against the ERC-7201 derivation formula by `StorageLocation.t.sol`.



## [0.3.0] — 2026-02-26

Commit: `ab478748442d8603b30593b06f6a267b11d3a2d4`

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
