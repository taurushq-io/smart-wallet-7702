# Security Audit Report — TSmartAccount7702
**Reviewer**: Claude Sonnet 4.6
**Contract**: `src/TSmartAccount7702.sol`
**Version**: 1.0.0
**Date**: 2026-03-23
**Scope**: Full security review — smart wallet vulnerabilities, ERC-4337/EIP-7702/ERC-1271/ERC-7739 specification compliance, ABDK audit findings (CVF-1 through CVF-12), and independent code review (CR-1 through CR-7).

---

## Executive Summary

`TSmartAccount7702` is a minimal ERC-4337 smart account designed for EIP-7702 delegation. The contract is well-structured and conservatively scoped.

- All 12 ABDK audit findings addressed (8 fixed, 1 not implementable due to a compiler limitation, 3 rejected/acknowledged with documented rationale).
- 7 independent code review findings identified and all fixed or addressed.
- 1 additional post-review style improvement applied.

**No open findings. The contract is ready for production.**

| Severity      | Total | Open | Fixed / Addressed |
|---------------|-------|------|-------------------|
| Medium        | 1     | 0    | 1                 |
| Low           | 3     | 0    | 3                 |
| Informational | 3     | 0    | 3                 |

---

## Wallet Architecture

```
EOA (address(this))
  │
  │  EIP-7702 delegation
  ▼
TSmartAccount7702
  ├── ERC7739 (OZ)          — ERC-1271 + ERC-7739 anti-replay
  │     └── EIP712          — domain separator (name="TSmart Account 7702", ver="1")
  ├── SignerEIP7702 (OZ)    — _rawSignatureValidation: ecrecover == address(this)
  └── IAccount (ERC-4337)   — PackedUserOperation / EntryPoint v0.8/v0.9

Storage (ERC-7201 namespaced, slot 0x38a1...7a00):
  EntryPointStorage { address entryPoint; bool initialized; }
```

**Trust boundaries:**
- EntryPoint (trusted, set at initialization) → `validateUserOp`, `execute`, `deployDeterministic`
- EOA itself (`address(this)`) → `initialize` (once), `execute`, `deployDeterministic`
- Anyone → `isValidSignature`, `supportsInterface`, token receiver callbacks, `entryPoint()`, `version()`

---

## UserOperation Validation Flow

```
Bundler
  └─► EntryPoint.handleOps()
        └─► validateUserOp(userOp, userOpHash, missingAccountFunds)
              │  [onlyEntryPoint: checks initialized + msg.sender == entryPoint]
              ├─ _rawSignatureValidation(userOpHash, userOp.signature)
              │    └─ ecrecover(hash, sig) == address(this) → true/false (never reverts)
              ├─ if invalid → return 1 (SIG_VALIDATION_FAILED, no ETH spent)
              ├─ if missingAccountFunds > 0 → assembly call(gas(), entryPoint, prefund, ...)
              └─ return 0 (valid)
        └─► execute(target, value, data)
              │  [onlyEntryPointOrSelf]
              └─► _call(target, value, data)
```

---

## Execution Access Control Matrix

| Function                  | EntryPoint | EOA (self)  | Anyone |
|---------------------------|------------|-------------|--------|
| `initialize`              | ✗          | ✓ (once)    | ✗      |
| `validateUserOp`          | ✓          | ✗           | ✗      |
| `execute`                 | ✓          | ✓           | ✗      |
| `deployDeterministic`     | ✓          | ✓           | ✗      |
| `isValidSignature`        | —          | —           | ✓      |
| `supportsInterface`       | —          | —           | ✓      |
| `entryPoint` / `version`  | —          | —           | ✓      |
| Token receiver callbacks  | —          | —           | ✓      |

---

## Findings

### Medium

#### CR-1 — Missing Zero-Address Validation in `initialize()`

**Location**: `initialize()`, line 101

**Description**: If `entryPoint_` is `address(0)`, the function would succeed: `initialized` is set to `true` and `entryPoint` is set to `address(0)`. From that point:

- `onlyEntryPoint` checks `msg.sender == address(0)` — never true — so all UserOps are permanently blocked.
- `onlyEntryPointOrSelf` blocks EntryPoint calls for the same reason. Direct self-calls still work.
- Re-initialization is blocked by `AlreadyInitialized()`.

The account would be permanently locked for ERC-4337 flows within this implementation. Since `initialize()` requires `msg.sender == address(this)`, this can only be triggered by the EOA itself sending a malformed transaction. Recovery requires re-delegating via a new type-4 EIP-7702 transaction.

**Severity downgrade rationale**: Downgraded from Medium to Low because (1) only the EOA can trigger it, (2) recovery is possible via re-delegation, (3) there is no asset loss — the account becomes inert for UserOp flows only.

**Fix applied**: Added `error AddressZeroForEntryPointNotAllowed()` and a `require` guard before any state is written:

```solidity
require(entryPoint_ != address(0), AddressZeroForEntryPointNotAllowed());
```

On revert, `initialized` remains `false` and the EOA can retry with a valid address.

---

### Low

#### CR-2 — Pragma Regression: CVF-6 Fix Silently Reverted

**Location**: Line 2

**Description**: Commit `d5db86b` ("docs: add CVF-4 return-data NatSpec", authored by rya-sge) accidentally reverted the pragma from `^0.8.34` back to `0.8.34`. The CVF-6 fix was lost, creating a discrepancy between the source and the CHANGELOG/FEEDBACK.md documentation.

**Fix applied**: Restored `pragma solidity ^0.8.34;`. Commit `ec0be70`.

---

#### CR-3 — Wrong Inline Comment on `type(IAccount).interfaceId`

**Location**: `supportsInterface()`, line 271

**Description**: The comment `// 0x3a871cdd` was the selector of `IAccount.validateUserOp` from the legacy v0.6/v0.7 unpacked `UserOperation` interface, not `type(IAccount).interfaceId`. The actual value for the v0.8/v0.9 `PackedUserOperation` interface is `0x19822f7c`, confirmed by tests during CVF-12. The functional code was correct — only the comment misled reviewers.

**Fix applied**: Comment corrected to `// 0x19822f7c`. NatSpec added noting that the legacy v0.6/v0.7 interface (`0x3a871cdd`) is not supported and EntryPoint v0.6/v0.7 are incompatible with this contract. Commit `329c857`.

---

#### CR-4 — Trailing Whitespace on Line 77

**Location**: Line 77, after `ENTRY_POINT_STORAGE_LOCATION =`

**Description**: Commit `d5db86b` introduced a trailing space after `=` on the `ENTRY_POINT_STORAGE_LOCATION` constant declaration. Cosmetic issue causing linter noise.

**Fix applied**: Trailing space removed. Commit `ec0be70`.

---

### Informational

#### CR-5 — `supportsInterface` Does Not Call `super.supportsInterface()`

**Location**: `supportsInterface()`, lines 270–277

**Description**: The implementation returns a flat boolean expression without delegating to any base. This is correct today: none of the base contracts (`ERC7739`, `SignerEIP7702`, `EIP712`) implement `supportsInterface`, so calling `super.supportsInterface(interfaceId)` would be a **compilation error** — Solidity has no function to dispatch to in the MRO chain.

However, if a future OpenZeppelin version adds `supportsInterface` to any of these bases (for example, to advertise EIP-712 support via `IERC5267`), the flat override would silently shadow it.

**Resolution**: No code change possible. When upgrading OpenZeppelin, explicitly verify whether any base has gained a `supportsInterface` implementation and wire in `super.supportsInterface(interfaceId)` at that point.

---

#### CR-6 — Prefund Transferred Before Signature Validation

**Location**: `validateUserOp()`, lines 153–185

**Description**: The ETH prefund was sent to the EntryPoint before the signature was validated. On `SIG_VALIDATION_FAILED` (return value `1`), the ETH had already left the account and was not returned — it is retained by the EntryPoint to cover the bundler's gas cost.

`_rawSignatureValidation` (from `SignerEIP7702`) is ecrecover-based and **never reverts** — it only returns `true` or `false`. Checking the signature first is therefore safe: if invalid, the function returns `1` immediately without paying any prefund. If validation reverts unexpectedly, the entire transaction reverts regardless of order, so the prefund is safe either way.

The ERC-4337 protocol places the responsibility for not submitting failing UserOps on the bundler and EntryPoint (via simulation), not on the account. The account should still minimise unnecessary ETH exposure in the validation path.

**Fix applied**: Moved `_rawSignatureValidation` before the `missingAccountFunds` transfer. Invalid-signature UserOps no longer cause any ETH to leave the account. Comments document the rationale and the bundler/EntryPoint responsibility principle. Commit `920de4c`.

---

#### CR-7 — Re-entrancy Blocked by Access Control, Not a Guard

**Location**: `execute()` and `deployDeterministic()`

**Description**: Both functions perform external calls (`_call` / `CREATE2`) without a `nonReentrant` guard. Re-entrancy is structurally blocked because a re-entrant call from the target would have `msg.sender` equal to the target address, which is neither the EntryPoint nor `address(this)`, causing `onlyEntryPointOrSelf` to revert. The protection is real but relies on the invariant that all state-modifying entry points performing external calls are guarded.

**Fix applied**: Added a contract-level NatSpec `@dev` paragraph documenting that re-entrancy protection is provided by access control rather than a mutex, explaining the structural invariant, and requiring that future maintainers apply `onlyEntryPoint` or `onlyEntryPointOrSelf` to any new entry point performing external calls.

---

### ABDK Findings (CVF-1 through CVF-12)

#### CVF-1 — Storage Collision via OZ `Initializable` *(Major — Fixed)*
Removed OZ `Initializable`. Custom `bool initialized` flag co-located in `EntryPointStorage` under the wallet's own ERC-7201 namespace (`smartaccount7702.entrypoint`). Zero collision risk with any other OZ contract. Commit `9179aaf`.

#### CVF-2 — Modifiers Do Not Check Initialization *(Moderate — Fixed)*
Both `onlyEntryPoint` and `onlyEntryPointOrSelf` now load `EntryPointStorage` and revert `NotInitialized()` before the address comparison. Commit `84c92fa`.

#### CVF-3 — Inaccurate `_call` NatSpec *(Moderate — Fixed)*
Comment corrected to "copies calldata into memory and forwards via CALL, avoiding ABI-encode round-trip". Commit `8a2573c`.

#### CVF-4 — `execute` Drops Return Data *(Moderate — No change)*
No change. The EntryPoint does not use the return value of `execute`. Return data is intentionally discarded for ERC-4337 compatibility. `execute` is `virtual` for callers that need return values in the direct self-call path. NatSpec documents this trade-off.

#### CVF-5 — Revert Data Not Wrapped in Named Error *(Moderate — Rejected)*
Rejected. Raw bubble-up is correct. Wrapping would break ERC-4337 bundler error parsing, Etherscan/Tenderly traces, and EIP-7821 compatibility. The wallet's own errors are thrown exclusively before `_call` executes — there is no actual ambiguity.

#### CVF-6 — Exact Compiler Version Pragma *(Minor — Fixed)*
`pragma solidity 0.8.34` → `pragma solidity ^0.8.34`. Commit `f4fa540`. (Accidentally reverted in `d5db86b`, re-applied in `ec0be70`.)

#### CVF-7 — Dependencies Not Reviewed *(Minor — Acknowledged)*
`IAccount` and `PackedUserOperation` are minimal interface definitions from the audited `account-abstraction` v0.9.0 repository. No action required.

#### CVF-8 — Custom Errors Without Parameters *(Minor — Fixed)*
`Unauthorized()` → `Unauthorized(address caller)`. All sites pass `msg.sender`. Commit `1c3521c`.

#### CVF-9 — Hardcoded ERC-7201 Storage Slot *(Minor — Not implemented)*
Solidity 0.8.34 rejects expression-form constants (`keccak256(...)`) in `$.slot :=` assembly assignments. The hardcoded literal is retained. The derivation formula is in the comment above. `StorageLocation.t.sol` verifies the constant against the on-chain ERC-7201 computation at runtime.

#### CVF-10 — Empty Blocks Without Comments *(Minor — Fixed)*
`// Intentionally empty:` inline comments added to `receive()` and `fallback()`. Commit `432a390`.

#### CVF-11 — Version Number Hardcoded *(Minor — Fixed)*
`string private constant VERSION = "1.0.0"`. Commit `0f863e6`.

#### CVF-12 — Magic `bytes4` Literals in `supportsInterface` *(Minor — Fixed)*
All standard interfaces now use `type(...).interfaceId`. ERC-7739 uses named constant `ERC7739_INTERFACE_ID`. Tests confirmed `IAccount` ID is `0x19822f7c`, not `0x3a871cdd` (old v0.6/v0.7 selector). Commit `5d7232f`.

---

### Post-Review Style Improvement

#### `require(condition, CustomError())` Guards

All `if (!condition) revert CustomError()` guards were migrated to the `require(condition, CustomError())` form introduced in Solidity 0.8.26. The two styles produce identical bytecode — purely stylistic, for consistency with the OpenZeppelin v5 convention used by this contract's dependencies.

The `if (!_rawSignatureValidation(...)) return 1` path in `validateUserOp` was intentionally left as `if` — it returns a value rather than reverting and cannot be expressed as a `require`. Commit `82b698c`.

---

## Specification Compliance

### ERC-4337 (UserOperation)

| Requirement | Check | Status |
|-------------|-------|--------|
| `validateUserOp` only callable by EntryPoint | `onlyEntryPoint` modifier | ✓ |
| Returns `0` for valid, `1` for invalid — must not revert on bad sig | `_rawSignatureValidation` returns bool | ✓ |
| Prefund payment via `missingAccountFunds` | Assembly `call` to `caller()` | ✓ |
| Prefund paid only on valid signature | Sig check before prefund (CR-6 fix) | ✓ |
| Nonce management delegated to EntryPoint | No account-level nonce | ✓ |
| Paymaster-sponsored mode (`missingFunds=0`) | `if (missingAccountFunds > 0)` guard | ✓ |
| Compatible with EntryPoint v0.8 and v0.9 | `PackedUserOperation`, dual test suite | ✓ |

### EIP-7702 (EOA Delegation)

| Requirement | Check | Status |
|-------------|-------|--------|
| `address(this)` resolves to the delegating EOA | Inherited from EIP-7702 semantics | ✓ |
| `receive()` for ETH reception with code | `receive() external payable` | ✓ |
| ERC-7201 storage prevents slot collision on re-delegation | Namespaced slot `smartaccount7702.entrypoint` | ✓ |
| Re-init prevented after re-delegation to same impl | `initialized` flag in private namespace | ✓ |
| Front-running `initialize()` prevented | `msg.sender == address(this)` guard | ✓ |
| `address(0)` EntryPoint rejected | `AddressZeroForEntryPointNotAllowed` guard | ✓ |

### ERC-1271 / ERC-7739 (Signatures)

| Requirement | Check | Status |
|-------------|-------|--------|
| `isValidSignature` returns `0x1626ba7e` on valid sig | Via OZ `ERC7739` | ✓ |
| Returns `0xffffffff` on invalid — must not revert | OZ `ERC7739` | ✓ |
| PersonalSign anti-replay | ERC-7739 nested hash | ✓ |
| TypedDataSign anti-replay | ERC-7739 nested hash | ✓ |
| Domain separator includes `address(this)` | `verifyingContract` in EIP-712 domain | ✓ |
| Cross-account replay blocked | Domain per-EOA | ✓ |
| Cross-chain replay blocked | `chainId` in domain separator | ✓ |

### ERC-165 (Interface Detection)

| Interface | ID | Declared |
|-----------|----|----------|
| `IAccount` (v0.8/v0.9 `PackedUserOperation`) | `0x19822f7c` | ✓ |
| `IERC1271` | `0x1626ba7e` | ✓ |
| ERC-7739 | `0x77390001` | ✓ |
| `IERC721Receiver` | `0x150b7a02` | ✓ |
| `IERC1155Receiver` | `0x4e2312e0` | ✓ |
| `IERC165` | `0x01ffc9a7` | ✓ |

---

## Attack Surface Analysis

### Front-running `initialize()` — **Mitigated**
`initialize` requires `msg.sender == address(this)`. Under EIP-7702, only the EOA can satisfy this. An attacker cannot call `initialize` from any external contract or EOA. Verified by `test_attack_frontRunInitialize_reverts` and `test_attack_initializeViaCallback_reverts`.

### Re-initialization — **Mitigated**
`AlreadyInitialized()` is thrown on any second call to `initialize`. The custom flag lives in the wallet's own ERC-7201 namespace, preventing cross-implementation flag collisions (CVF-1 fix). Verified by `test_attack_reinitialize_reverts`.

### Unauthorized Execution — **Mitigated**
`execute` and `deployDeterministic` are gated by `onlyEntryPointOrSelf`. Both modifiers check `initialized` first, then verify `msg.sender`. Verified by `test_attack_unauthorizedExecute_reverts`, `test_attack_stealEther_reverts`, `test_attack_stealTokens_reverts`.

### UserOp with Wrong Signer — **Mitigated**
`_rawSignatureValidation` (ecrecover) returns `false` for any signature not made by the EOA. Returns `1`, not a revert, for bundler simulation compatibility. Verified by `test_attack_wrongSignerUserOp_fails` and fuzz tests.

### UserOp Replay — **Mitigated**
EntryPoint nonce management prevents replay. Nonce is monotonically incremented per `(sender, key)`. Verified by `test_attack_replayUserOp_reverts`.

### ERC-1271 Cross-Account Replay — **Mitigated**
ERC-7739 domain separator includes `verifyingContract = address(this)` (the specific EOA). A signature valid for Alice is rejected by Bob's account. Verified by `test_attack_erc1271CrossAccountReplay_rejected`.

### Uninitialized Account Exploitation — **Mitigated**
Both modifiers check `initialized` and revert `NotInitialized()` before the address comparison. An uninitialized wallet is completely inert. Verified by `test_attack_uninitializedAccount_isInert`.

### Re-entrancy — **Mitigated via Access Control**
`execute` and `deployDeterministic` perform external calls but are gated by `onlyEntryPointOrSelf`. A re-entrant call from the target has `msg.sender == target`, which is neither the EntryPoint nor `address(this)`. Documented in contract-level NatSpec (CR-7 fix).

### No `delegatecall` — **Safe by Design**
Only `call` (in `_call`) and `create2` (in `deployDeterministic`) are used. No `delegatecall` exposure — a malicious target cannot overwrite the wallet's storage.

### Dual Nonce System — **Not Applicable**
Only CREATE2 (`deployDeterministic`) is supported. CREATE2 is nonce-independent — no EVM nonce drift risk.

---

## EIP-7702 Residual Risks

These are inherent EIP-7702 properties that cannot be mitigated at the smart contract level. Protocol integrators must be aware of them.

| Risk | Description |
|------|-------------|
| **Re-delegation** | The EOA can re-delegate to a different implementation at any time. Storage persists under the new implementation, which may interpret it differently. |
| **Delegation revocation** | The EOA can revoke delegation entirely. Pending UserOps in the mempool will fail at execution time. |
| **Legacy transaction bypass** | The EOA can always send type-0/1/2 transactions that bypass `validateUserOp` entirely. |
| **EOA key compromise** | A stolen private key allows signing UserOps, re-delegating, or draining the account via legacy transactions. No on-chain guardian or recovery mechanism exists. |
| **ERC-1271 cache staleness** | Protocols caching `isValidSignature` results must re-validate — the delegation can change. |

---

## Static Analysis

### Slither (Trail of Bits)
4 informational findings — all assembly usage, all acknowledged as intentional:
- `_getEntryPointStorage`: ERC-7201 slot assignment (no Solidity syntax alternative)
- `_call`: low-level CALL with revert bubbling (avoids ABI re-encoding)
- `validateUserOp`: raw ETH prefund transfer (standard ERC-4337 pattern)
- `deployDeterministic`: CREATE2 opcode (no built-in Solidity alternative for arbitrary bytecode)

No high, medium, or low severity findings.

### Aderyn (Cyfrin)
3 findings, all false positives or acknowledged:
- **H-1 "Locks Ether"**: False positive. Under EIP-7702, `address(this)` is the EOA. ETH is withdrawn via `execute()` or direct EOA transactions.
- **L-1 "Modifier used once"**: Acknowledged. `onlyEntryPoint` / `onlyEntryPointOrSelf` separation is intentional access control design.
- **L-2 "Unused state variable"**: False positive. `ENTRY_POINT_STORAGE_LOCATION` is referenced in inline assembly; Aderyn does not analyse assembly.

---

## Test Coverage

| Test File | Scenarios |
|-----------|-----------|
| `AttackTests.t.sol` | 11 adversarial scenarios (front-running, theft, replay, wrong signer, uninitialized, callback attack) |
| `AttackTests.v08.t.sol` | Same 11 attack scenarios against EntryPoint v0.8 |
| `Fuzz.t.sol` | 14 fuzz tests (signature, prefund, execution, CREATE2, ERC-165) |
| `ValidateUserOp.t.sol` | Valid sig, wrong signer, non-EntryPoint, prefund (with/without paymaster), self-funded E2E |
| `Execute.t.sol` | Direct call, EntryPoint routing, uninitialized guard |
| `Deploy.t.sol` | Success, with value, event, empty bytecode, salt collision, constructor revert, unauthorized, via UserOp |
| `IsValidSignature.t.sol` | Valid EOA sig, wrong signer, invalid length |
| `TypedDataSign.t.sol` | Valid TypedDataSign, wrong signer, cross-account replay |
| `ERC1271.t.sol` | Domain values, cross-account replay, ERC-7739 detection |
| `StorageLocation.t.sol` | ERC-7201 slot verification (step-by-step and aggregate) |
| `Walkthrough*.t.sol` | End-to-end: ERC-20 transfer, paymaster, CREATE2 deployment |

135 tests, 0 failures. All V09 tests mirrored for V08 EntryPoint via abstract/concrete inheritance.

---

## Conclusion

`TSmartAccount7702` v1.0.0 has no open findings. All 12 ABDK audit findings have been resolved appropriately and all 7 independent code review findings have been fixed or documented. The contract correctly implements ERC-4337, EIP-7702, ERC-1271, and ERC-7739 specifications. Re-entrancy protection via access control is sound, storage slot isolation is correct, and the test suite provides comprehensive coverage including adversarial scenarios and property-based fuzzing.
