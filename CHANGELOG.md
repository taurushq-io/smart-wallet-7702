# Changelog

## Semantic Version 2.0.0

Given a version number MAJOR.MINOR.PATCH, increment the:

1. MAJOR version when the new version makes:
   - Incompatible proxy **storage** change internally or through the upgrade of an external library (OpenZeppelin)
   - A significant change in external APIs (public/external functions) or in the internal architecture
2. MINOR version when the new version adds functionality in a backward compatible manner
3. PATCH version when the new version makes backward compatible bug fixes

See [https://semver.org](https://semver.org/)

## Type of changes

- `Added` for new features.
- `Changed` for changes in existing functionality.
- `Deprecated` for soon-to-be removed features.
- `Removed` for now removed features.
- `Fixed` for any bug fixes.
- `Security` in case of vulnerabilities.

Reference: [keepachangelog.com/en/1.1.0/](https://keepachangelog.com/en/1.1.0/)

Custom changelog tag: `Dependencies`, `Documentation`, `Testing`

## Checklist

> Before a new release, perform the following tasks

- Code: Update the **version name**, variable VERSION
- Run formatter and linter

```
forge fmt
forge lint
```

- Documentation
  - Perform a code coverage and update the files in the corresponding directory [./doc/coverage](./doc/coverage)
  - Perform an audit with several audit tools (Aderyn and Slither), update the report in the corresponding directory [./doc/audits/tools](./doc/audit/tool)
  - Update surya doc by running the 3 scripts in [./doc/script](./doc/script)
  - Update changelog

## [1.0.0]

Final release. Combines all changes from rc0 and rc1. Full diff from v0.3.0 is documented in [`doc/DIFFv0.3.0_1.0.0.md`](doc/DIFFv0.3.0_1.0.0.md).

### Security

- **CVF-1 (Major)**: Replaced OZ `Initializable` with a wallet-private ERC-7201 init guard, then superseded by an immutable constructor parameter (see rc1). The entire per-EOA initialization system was eliminated, removing the initialization window and sponsorship limitation entirely.
- **CVF-2 (Moderate)**: Modifiers now check the `ENTRY_POINT` immutable directly. No uninitialized state exists, so no `NotInitialized` check is needed. A subclass override of `entryPoint()` cannot bypass the modifier because it reads the immutable, not the virtual function.
- **CR-6**: Signature validation moved before the prefund payment in `validateUserOp`. Invalid-signature UserOps no longer cause any ETH to leave the account.
- **CR-1**: Zero-address guard on the EntryPoint parameter, now enforced at construction time via `EntryPointAddressZero()`.

### Added

- `address public immutable ENTRY_POINT` — EntryPoint set once at deployment, shared by all delegating EOAs.
- `error EntryPointAddressZero()` — reverts when `address(0)` is passed to the constructor.
- `test/mocks/TSmartAccount7702V09.sol` — convenience subcontract targeting the EntryPoint v0.9.0 canonical address, for tests that need the actual v0.9 address.

### Removed

- `initialize(address entryPoint_)` — no per-EOA initialization required.
- `EntryPointStorage` struct and `ENTRY_POINT_STORAGE_LOCATION` constant — entire ERC-7201 namespaced storage system removed.
- `_getEntryPointStorage()` helper.
- `error AlreadyInitialized()`, `error NotInitialized()`, `error AddressZeroForEntryPointNotAllowed()`.
- `event EntryPointSet(address indexed entryPoint)`.
- `test/TSmartAccount7702/StorageLocation.t.sol` — no storage slot to verify.
- Five initialization-specific attack tests from `AttackTests.t.sol` (front-run initialize, re-initialize, uninitialized account, initialize via callback, initialize with address(0)).

### Changed

- **CVF-8**: `error Unauthorized()` → `error Unauthorized(address caller)`. All revert sites pass `msg.sender`. (`1c3521c`)
- **CVF-12**: Magic `bytes4` literals in `supportsInterface` replaced with `type(...).interfaceId` expressions. `ERC7739_INTERFACE_ID` subsequently removed — ERC-7739 has no ERC-165 interface ID; detection is via `isValidSignature`. Token receiver callback return literals replaced with `.selector` expressions. (`5d7232f`, `8eefd50`, `7048e0c`)
- **CVF-11**: Inline version string replaced with `string private constant VERSION`. (`0f863e6`)
- **CVF-6**: Pragma relaxed from `0.8.34` to `^0.8.34`. (`f4fa540`)
- `onlyEntryPoint` and `onlyEntryPointOrSelf` modifiers read `ENTRY_POINT` immutable directly rather than calling `entryPoint()` virtual function.
- **Version**: Contract version bumped to `"1.0.0"`.

### Fixed

- **CVF-3**: Corrected `_call()` NatSpec — calldata is copied into memory via `calldatacopy`; the previous comment incorrectly stated it was forwarded "without copying to memory". (`8a2573c`)

### Documentation

- **CVF-4**: NatSpec added to `execute()` documenting intentional return data discard. (`d5db86b`)
- **CVF-10**: `// Intentionally empty:` inline comments added to `receive()` and `fallback()`. (`432a390`)
- ABDK audit feedback document added at `doc/audit/abdk/taurus-reportv0.3.0-feedback.md`.

### Not changed

- **CVF-4**: No logic change — return data drop is intentional and consistent with all major ERC-4337 implementations.
- **CVF-5**: Rejected — wrapping raw revert data in a named error would break ERC-4337 bundler parsing, off-chain tooling, and EIP-7821 compatibility.
- **CVF-7**: Out of scope — `IAccount` and `PackedUserOperation` are minimal interface definitions from the audited `account-abstraction` v0.9.0 upstream.
- **CVF-9**: Obsolete — the entire ERC-7201 storage system was removed; `ENTRY_POINT_STORAGE_LOCATION` no longer exists.

---

## [1.0.0-rc1] — 2026-03-26

Commits: `6dc652f`, `8d78988`, `6d23314`, `98f1801`, `c5ff3fd`

Supersedes the per-EOA initialization model introduced in rc0 with an immutable constructor parameter. Eliminates the initialization window and the sponsorship limitation identified in the post-rc0 review.

### Security

- **EntryPoint moved to immutable**: `address public immutable ENTRY_POINT` replaces the ERC-7201 `EntryPointStorage` system. The EntryPoint is baked into the implementation bytecode at deployment. No per-EOA `initialize()` call is required or possible. (`6dc652f`, `8d78988`)
- **`EntryPointAddressZero()` guard**: `require(entryPoint_ != address(0), EntryPointAddressZero())` added to the constructor. Deploying with `address(0)` reverts immediately at construction time. (`98f1801`)

### Added

- `address public immutable ENTRY_POINT` set via constructor parameter. (`8d78988`)
- `error EntryPointAddressZero()`. (`98f1801`)
- `test/mocks/TSmartAccount7702V09.sol`: subcontract targeting EntryPoint v0.9.0 canonical address for tests that need the actual v0.9 address rather than bytecode deployed at the v0.8 address. (`6dc652f`)
- `test_implementation_entryPointZeroReverts`: verifies the constructor reverts with `EntryPointAddressZero()` when `address(0)` is passed. (`98f1801`)

### Removed

- `initialize(address entryPoint_)` and all associated infrastructure: `EntryPointStorage` struct, `ENTRY_POINT_STORAGE_LOCATION` constant, `_getEntryPointStorage()` helper. (`6dc652f`)
- `error AlreadyInitialized()`, `error NotInitialized()`, `error AddressZeroForEntryPointNotAllowed()`. (`6dc652f`)
- `event EntryPointSet(address indexed entryPoint)`. (`6dc652f`)
- `test/TSmartAccount7702/StorageLocation.t.sol`. (`6dc652f`)
- `TestValidateUserOpUninitialized`, `TestExecuteUninitialized`, `TestDeployUninitialized` test classes. (`6dc652f`)
- Five initialization attack tests from `AttackTests.t.sol`: front-run initialize, re-initialize, uninitialized account, initialize via callback, initialize with address(0). (`6dc652f`)

### Changed

- Constructor signature changed from `constructor()` to `constructor(address entryPoint_)`. (`8d78988`)
- `onlyEntryPoint` and `onlyEntryPointOrSelf` read `ENTRY_POINT` immutable directly instead of calling `entryPoint()`, preventing subclass divergence from bypassing the security check. (`8d78988`)
- Code comments rewritten: em dash phrase structures removed throughout `TSmartAccount7702.sol`. (`6d23314`)

### Documentation

- Updated README, ABDK audit feedback, Aderyn and Slither feedback to reflect the removal of the initialization system and the new immutable architecture. (`18194ed`, `c5ff3fd`)

---

## [1.0.0-rc0] — 2026-03-23

Commit: `51c0b3398933268c29c846a82da529bb1eb511ed`

ABDK audit remediation release. All Major and Minor findings addressed; two Moderate findings rejected with documented rationale; one Minor finding not implemented due to compiler limitation.

### Security

- **CVF-1 (Major)**: Replaced OZ `Initializable` with a wallet-local init guard. The `bool initialized` flag is co-located in `EntryPointStorage` under the contract's own ERC-7201 namespace (`smartaccount7702.entrypoint`), eliminating shared-slot collision risk from prior EOA delegations. Added `error AlreadyInitialized()`. Removed `_disableInitializers()` from the constructor — the `msg.sender == address(this)` guard on `initialize()` provides equivalent protection. (`9179aaf`)
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
