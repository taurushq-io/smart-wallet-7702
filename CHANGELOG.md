# Changelog

## v1 — EIP-7702 Refactor

Complete architectural overhaul: replaced the Coinbase multi-owner smart wallet with a minimal ERC-4337 account designed for EIP-7702 delegation.

### Key Insight

With EIP-7702, `address(this)` **is** the EOA. Owner management is redundant — the EOA's private key is the sole authority. This enabled a dramatic simplification from ~700 lines to ~200 lines.

### Added

- `SmartAccount7702.sol` — new minimal ERC-4337 account contract
  - `validateUserOp` — recovers ECDSA signer and checks `signer == address(this)` (the EOA)
  - `execute` / `executeBatch` — restricted to EntryPoint or self
  - `deploy` / `deployDeterministic` — CREATE/CREATE2 deployment from the account
  - `onlyEntryPoint` / `onlyEntryPointOrSelf` modifiers for access control
- Paymaster-only design: `missingAccountFunds` is ignored (paymaster covers all gas costs)
- Direct EOA execution: `msg.sender == address(this)` allows the EOA to call functions without the EntryPoint
- EIP-712 domain: `("Smart Account 7702", "1")`

### Removed

- **MultiOwnable** — no owner storage, initialization, add/remove owners
- **CoinbaseSmartWalletFactory** — no proxy deployment; the EOA delegates directly via EIP-7702
- **SignatureWrapper** — no `ownerIndex`; replaced with raw ECDSA signature
- **ERC1271InputGenerator** — tied to the factory/proxy pattern
- **UUPSUpgradeable** — EIP-7702 re-delegation is the native upgrade mechanism
- **`initialize()`** — no initialization needed; `address(this)` is already the EOA
- **`executeWithoutChainIdValidation()`** — no cross-chain owner sync
- **`canSkipChainIdValidation()`** — no owner functions to whitelist
- **`REPLAYABLE_NONCE_KEY`** — nonce key validation logic removed
- **Prefund logic** — wallet does not hold ETH for gas; paymaster-only
- **Constructor** — no implementation guard needed without proxy

### Changed

- Renamed contract from `CoinbaseSmartWallet` to `SmartAccount7702`
- Simplified `_isValidSignature()` to use Solady `ECDSA.tryRecoverCalldata` and compare to `address(this)`
- Replaced OpenZeppelin ECDSA with Solady ECDSA
- Simplified access control: `onlyEntryPointOrOwner` became `onlyEntryPointOrSelf`
- Rewrote test suite to cover the new simplified contract
- Updated deployment script for single-contract deployment (no factory)
- Updated to EntryPoint v0.9 at `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`

### Kept

- `ERC1271.sol` — anti-cross-account-replay signature validation (unchanged)
- `Receiver` (Solady) — for ETH reception
- `execute()` / `executeBatch()` / `deploy()` / `deployDeterministic()` core functions

### Design Decisions

| Decision | Rationale |
|---|---|
| No prefund | Paymaster-only; wallet never holds ETH for gas |
| No UUPS proxy | EIP-7702 re-delegation is the native upgrade path |
| No multi-owner | `address(this)` is the EOA; only the EOA's key can sign |
| No factory | EOA delegates directly to the implementation |
| No initialization | `address(this)` is already the EOA |

### Security Notes

- **Cross-account isolation**: Each EOA runs the wallet's code in the context of its own storage and address. Two EOAs delegating to the same implementation cannot access each other's funds.
- **Signature malleability**: Solady `ECDSA.tryRecoverCalldata` enforces low-s, preventing malleability attacks.
- **EIP-7702 re-delegation risk**: If the EOA delegates to a malicious contract, all funds are at risk. This is an inherent EIP-7702 risk, not preventable at the wallet level.
- **Replay protection**: UserOp nonces are managed entirely by EntryPoint v0.9. ERC-1271 replay protection is handled by the `replaySafeHash` wrapper binding signatures to `(chainId, address(this))`.
