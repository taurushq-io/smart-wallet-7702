# Security Audit Report — TSmartAccount7702

**Reviewer**: Claude Sonnet 4.6
**Contract**: `src/TSmartAccount7702.sol`
**Contract version**: 1.0.1
**Date**: 2026-03-24
**Scope**: Full security review — smart wallet vulnerabilities, ERC-4337/EIP-7702/ERC-1271/ERC-7739 specification compliance, ABDK audit findings (CVF-1 through CVF-12), and independent code review.

> **Note on previous report**: The prior Claude audit report (`doc/audit/tool/claude/CLAUDE_report.md`, dated 2026-03-23) contained two stale entries. The ERC-165 compliance table listed ERC-7739 as supported via `supportsInterface` (marked ✓), and the CVF-12 summary mentioned `ERC7739_INTERFACE_ID` as retained. Both are incorrect for the current codebase — ERC-7739 was removed from `supportsInterface` in `8eefd50`. This report reflects the correct current state.

---

## Executive Summary

`TSmartAccount7702` is a minimal ERC-4337 smart account designed for EIP-7702 delegation. The contract is conservatively scoped: no modules, no upgradeability mechanism beyond EIP-7702 re-delegation, no multi-owner logic, and no delegatecall exposure.

**All 12 ABDK audit findings are correctly addressed** (8 fixed, 1 not implementable due to a compiler limitation, 3 rejected/acknowledged with documented rationale). The independent code review findings from the previous session are also correctly applied. No new security vulnerabilities were identified.

| Severity      | Total | Open | Fixed / Addressed |
|---------------|-------|------|-------------------|
| Critical      | 0     | 0    | —                 |
| High          | 0     | 0    | —                 |
| Medium        | 0     | 0    | —                 |
| Low           | 0     | 0    | —                 |
| Informational | 3     | 0    | 3 documented      |

**141 tests, 0 failures.**

---

## Wallet Architecture

```
EOA (address(this))
  │
  │  EIP-7702 delegation
  ▼
TSmartAccount7702
  ├── ERC7739 (OZ v5.5.0)     — ERC-1271 + ERC-7739 anti-replay
  │     └── EIP712             — domain separator (name="TSmart Account 7702", ver="1")
  ├── SignerEIP7702 (OZ)       — _rawSignatureValidation: ecrecover == address(this)
  └── IAccount (ERC-4337 v0.9) — PackedUserOperation

Storage (ERC-7201 namespace "smartaccount7702.entrypoint", slot 0x38a1...7a00):
  EntryPointStorage {
      address entryPoint;   // 20 bytes  ─┐ packed in one
      bool    initialized;  //  1 byte   ─┘ 32-byte slot
  }
```

**Trust boundaries:**

| Caller          | Accessible functions |
|-----------------|----------------------|
| EntryPoint      | `validateUserOp`, `execute`, `deployDeterministic` |
| EOA (self)      | `initialize` (once), `execute`, `deployDeterministic` |
| Anyone          | `isValidSignature`, `supportsInterface`, token receiver callbacks, `entryPoint()`, `version()` |

---

## UserOperation Validation Flow

```
Bundler
  └─► EntryPoint.handleOps()
        └─► validateUserOp(userOp, userOpHash, missingAccountFunds)
              │  [onlyEntryPoint: SLOAD → check initialized → check msg.sender == entryPoint]
              ├─ _rawSignatureValidation(userOpHash, userOp.signature)
              │    └─ ecrecover(hash, sig) == address(this) → true/false (never reverts)
              ├─ if invalid → return 1 (SIG_VALIDATION_FAILED; no ETH transferred)
              ├─ if missingAccountFunds > 0 → assembly call(gas(), caller(), prefund, ...)
              └─ return 0 (valid)
        └─► execute(target, value, data)
              │  [onlyEntryPointOrSelf: SLOAD → check initialized → check msg.sender]
              └─► _call(target, value, data)
                    └─ assembly: calldatacopy → CALL → bubble revert on failure
```

---

## ABDK Audit Findings — Verification

### CVF-1 — Storage Collision via OZ `Initializable` *(Major)*

**Verdict: Fixed ✓**

OZ `Initializable` has been completely removed. The initialization flag is now `bool initialized` co-located in `EntryPointStorage`, under the wallet's own ERC-7201 namespace (`"smartaccount7702.entrypoint"`). No other contract shares this slot.

Verification in current code (lines 64–67):
```solidity
struct EntryPointStorage {
    address entryPoint;
    bool initialized;
}
```

`initialize()` reads the wallet-private flag, not any shared OZ slot. An EOA with prior delegation history to any OZ `Initializable` contract is unaffected.

`_disableInitializers()` was also removed as a consequence — it belonged to OZ `Initializable`. No replacement is needed: `initialize()` requires `msg.sender == address(this)`, which can never hold for any external caller on the bare implementation contract. This is documented in the constructor NatSpec (lines 80–84). Commit `b99881d`.

**Commits**: `9179aaf` (primary fix), `b99881d` (constructor NatSpec)

---

### CVF-2 — Modifiers Do Not Check Initialization *(Moderate)*

**Verdict: Fixed ✓**

Both `onlyEntryPoint` (lines 111–116) and `onlyEntryPointOrSelf` (lines 122–127) load `EntryPointStorage` and call `require($.initialized, NotInitialized())` before performing the address comparison. This applies to all four guarded functions: `validateUserOp`, `execute`, `deployDeterministic`, and any future overrides.

```solidity
modifier onlyEntryPoint() {
    EntryPointStorage storage $ = _getEntryPointStorage();
    require($.initialized, NotInitialized());
    require(msg.sender == $.entryPoint, Unauthorized(msg.sender));
    _;
}
```

**Commit**: `84c92fa`

---

### CVF-3 — Inaccurate Comment on `_call` *(Moderate)*

**Verdict: Fixed ✓**

The `_call()` NatSpec (lines 312–313) now accurately reads:

> "Uses assembly to copy calldata into memory and forward it via CALL, avoiding a Solidity ABI-encode round-trip for large payloads."

The previous erroneous claim that calldata is forwarded "without copying to memory" has been removed.

**Commit**: `8a2573c`

---

### CVF-4 — `execute` Drops Return Data on Success *(Moderate)*

**Verdict: No change — documented ✓**

Return data from the nested `CALL` in `_call` is intentionally discarded. The `execute()` NatSpec (lines 190–195) documents this:
- The EntryPoint does not use the return value of `execute`.
- All major ERC-4337 implementations follow the same convention.
- `execute` is declared `virtual` for callers that require return values in the direct self-call path.

No code change. The trade-off is correctly documented.

**Commit**: `d5db86b` (NatSpec only)

---

### CVF-5 — Revert Data Not Wrapped in Named Error *(Moderate)*

**Verdict: Rejected — no change ✓**

The contract intentionally bubbles raw revert data from `_call`. Wrapping would:
1. Break ERC-4337 bundler revert-selector parsing.
2. Obscure traces in Etherscan and Tenderly.
3. Create false ambiguity — the wallet's own errors (`Unauthorized`, `NotInitialized`, `EmptyBytecode`) are thrown exclusively in modifiers and pre-call guards, which execute before `_call` is ever reached.

No change. This is consistent with EIP-7821 and all major smart wallet implementations.

---

### CVF-6 — Exact Compiler Version Pragma *(Minor)*

**Verdict: Fixed ✓**

Line 2: `pragma solidity ^0.8.34;`

The `^` allows patch-level compiler updates while enforcing the minimum version required for Prague EVM / EIP-7702 support. (Note: commit `d5db86b` accidentally reverted this to `0.8.34`; re-applied in `ec0be70`.)

**Commit**: `f4fa540` (original fix), `ec0be70` (restored after accidental revert)

---

### CVF-7 — Dependencies Not Reviewed *(Minor)*

**Verdict: Acknowledged — out of scope ✓**

`IAccount` and `PackedUserOperation` are minimal interface definitions from the canonical `account-abstraction` v0.9.0 repository. No logic — one function signature and one struct. The upstream repository has received independent audits from multiple firms.

---

### CVF-8 — Custom Errors Without Parameters *(Minor)*

**Verdict: Fixed ✓**

Line 42: `error Unauthorized(address caller);`

All authorization revert sites pass `msg.sender`. `EmptyBytecode` has no meaningful parameter and was left unchanged.

**Commit**: `1c3521c`

---

### CVF-9 — Hardcoded ERC-7201 Storage Slot *(Minor)*

**Verdict: Not implemented — compiler limitation ✓**

Solidity 0.8.34 rejects expression-form constants (`keccak256(...)`) in inline assembly `$.slot :=` assignments. The hardcoded literal `0x38a124a88e3a590426742b6544792c2b2bc21792f86c1fa1375b57726d827a00` is retained.

Mitigations in place:
- The derivation formula is in the comment directly above the constant (lines 70–75).
- `StorageLocation.t.sol` verifies the literal matches the ERC-7201 on-chain computation at runtime.

A local-variable workaround exists but was intentionally rejected as adding non-obvious indirection for cosmetic benefit.

---

### CVF-10 — Empty Blocks Without Inline Comments *(Minor)*

**Verdict: Fixed ✓**

Lines 330–332 and 334–336:
```solidity
receive() external payable {
    // Intentionally empty: ETH accepted unconditionally.
}

fallback() external payable {
    // Intentionally empty: unknown calls accepted to maintain EOA-equivalent behavior.
}
```

**Commit**: `432a390`

---

### CVF-11 — Version Number Should Be a Named Constant *(Minor)*

**Verdict: Fixed ✓**

Line 39: `string private constant VERSION = "1.0.0";`

`version()` returns `VERSION`. Version bump is a single-location change.

**Commit**: `0f863e6`

---

### CVF-12 — Interface Signatures Should Be Named Constants *(Minor)*

**Verdict: Fixed ✓** (with post-fix cleanup)

`supportsInterface()` (lines 268–274) uses `type(...).interfaceId` for all five supported interfaces. No magic `bytes4` literals remain.

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
    return interfaceId == type(IAccount).interfaceId        // 0x19822f7c
        || interfaceId == type(IERC1271).interfaceId
        || interfaceId == type(IERC721Receiver).interfaceId
        || interfaceId == type(IERC1155Receiver).interfaceId
        || interfaceId == type(IERC165).interfaceId;
}
```

**Post-fix corrections applied:**

1. **ERC-7739 removed**: The initial fix included `ERC7739_INTERFACE_ID = 0x77390001`. After analysis, ERC-7739 defines no new function signatures and therefore has no ERC-165 interface ID. `0x77390001` is the detection sentinel returned by `isValidSignature(0x7739...7739, "")` — not a computed XOR of function selectors. It was non-standard to advertise it via `supportsInterface`. Removed in `8eefd50`. A NatSpec comment explains the absence (lines 259–263).

2. **Token receiver callbacks**: The magic literals in `onERC721Received`, `onERC1155Received`, `onERC1155BatchReceived` were replaced with `.selector` expressions (same class of issue as CVF-12). Commit `7048e0c`.

3. **`IAccount` interface ID corrected**: The comment `// 0x3a871cdd` was the legacy v0.6/v0.7 selector. The correct value for the v0.8/v0.9 `PackedUserOperation` interface is `0x19822f7c`, confirmed by tests. Commit `329c857`.

**Commits**: `5d7232f` (primary), `8eefd50` (ERC-7739 removal), `7048e0c` (token callbacks), `329c857` (IAccount comment)

---

## Independent Code Review — Verified Fixes

### CR-1 — Zero-Address Guard in `initialize()` *(previously Medium)*

**Status: Fixed ✓**

Line 102: `require(entryPoint_ != address(0), AddressZeroForEntryPointNotAllowed());`

Guard executes before any state is written. On revert, `initialized` remains `false` and the EOA can retry.

**Commit**: `ef3fd38`

---

### CR-2 — Pragma Regression *(previously Low)*

**Status: Fixed ✓**

Commit `d5db86b` accidentally reverted `^0.8.34` to `0.8.34`. Restored in `ec0be70`.

---

### CR-3 — Wrong `IAccount` Interface ID Comment *(previously Low)*

**Status: Fixed ✓**

Comment corrected to `// 0x19822f7c`. NatSpec added at lines 264–267 documenting that the legacy v0.6/v0.7 interface ID (`0x3a871cdd`) is incompatible with this contract.

**Commit**: `329c857`

---

### CR-6 — Prefund Paid Before Signature Validation *(previously Informational)*

**Status: Fixed ✓**

`_rawSignatureValidation` is called before the `missingAccountFunds` transfer. Invalid-signature UserOps no longer cause any ETH to leave the account.

**Commit**: `920de4c`

---

### CR-7 — Re-entrancy via Access Control, Not a Guard *(previously Informational)*

**Status: Documented ✓**

Contract-level NatSpec (lines 32–37) documents the structural re-entrancy invariant: a re-entrant call from a target has `msg.sender == target`, which satisfies neither `onlyEntryPoint` nor `onlyEntryPointOrSelf`. Future maintainers are explicitly warned to preserve this by guarding all state-modifying external-call entry points.

**Commit**: `6ce9a04`

---

## Informational Notes

### INFO-1 — `supportsInterface` Does Not Call `super.supportsInterface()`

`supportsInterface` returns a flat boolean expression without delegating to any base contract. This is correct today: none of the base contracts (`ERC7739`, `SignerEIP7702`, `EIP712`) implement `supportsInterface`, so calling `super.supportsInterface(interfaceId)` would be a compilation error.

**Risk**: If a future OpenZeppelin version adds `supportsInterface` to one of these bases (e.g., to advertise EIP-712 support via `IERC5267`), the flat override would silently shadow it.

**Recommendation**: When upgrading OpenZeppelin, verify whether any base has gained a `supportsInterface` implementation and add `|| super.supportsInterface(interfaceId)` at that point.

---

### INFO-2 — EntryPoint Is Immutable After Initialization

`entryPoint` can only be set once via `initialize()`. If the configured EntryPoint is deprecated (e.g., the ecosystem migrates from v0.9 to v1.0), the EOA must re-delegate to a new implementation version. Re-delegating to the same implementation is blocked: `$.initialized` remains `true` and `initialize()` will revert with `AlreadyInitialized()`.

This is a documented design trade-off (CLAUDE.md, "Cons" section). No code change required. Protocol integrators should be aware.

---

### INFO-3 — ERC-7739 Detection via `isValidSignature`, Not ERC-165

ERC-7739 support is correctly detected by calling `isValidSignature(0x7739773977397739...7739, "")` and verifying the return value is `0x77390001`. This is handled by OZ `ERC7739` (line 45 in `draft-ERC7739.sol`). The `supportsInterface` function correctly does NOT advertise `0x77390001` — there is no ERC-165 interface ID for ERC-7739 (it defines no new function signatures). A NatSpec comment explains this (lines 259–263 of the contract).

---

## Specification Compliance

### ERC-4337 (UserOperation)

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| `validateUserOp` only callable by EntryPoint | `onlyEntryPoint` modifier | ✓ |
| Returns `0` for valid, `1` for invalid — must not revert on bad sig | `_rawSignatureValidation` returns bool | ✓ |
| Signature validated before prefund payment | Sig check before `missingAccountFunds` transfer | ✓ |
| Prefund paid via `missingAccountFunds` | Assembly `call` to `caller()` | ✓ |
| Nonce management delegated to EntryPoint | No account-level nonce | ✓ |
| Paymaster-sponsored mode (`missingFunds = 0`) | `if (missingAccountFunds > 0)` guard | ✓ |
| Compatible with EntryPoint v0.8 and v0.9 | `PackedUserOperation`, dual test suite | ✓ |

### EIP-7702 (EOA Delegation)

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| `address(this)` resolves to the delegating EOA | EIP-7702 semantics | ✓ |
| `receive()` for ETH reception when code is present | `receive() external payable` | ✓ |
| ERC-7201 storage prevents slot collision on re-delegation | Namespace `smartaccount7702.entrypoint` | ✓ |
| Re-init prevented after re-delegation to same impl | `initialized` in private namespace | ✓ |
| Front-running `initialize()` prevented | `msg.sender == address(this)` guard | ✓ |
| `address(0)` EntryPoint rejected | `AddressZeroForEntryPointNotAllowed` guard | ✓ |
| Uninitialized account is inert (not exploitable) | Both modifiers check `initialized` first | ✓ |

### ERC-1271 / ERC-7739 (Signatures)

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| `isValidSignature` returns `0x1626ba7e` on valid sig | OZ `ERC7739` | ✓ |
| Returns `0xffffffff` on invalid — must not revert | OZ `ERC7739` | ✓ |
| PersonalSign nested hash anti-replay | OZ `ERC7739` | ✓ |
| TypedDataSign nested hash anti-replay | OZ `ERC7739` | ✓ |
| Domain separator includes `address(this)` (per-EOA) | `verifyingContract` in EIP-712 domain | ✓ |
| Cross-account replay blocked | Domain separator is per-EOA | ✓ |
| Cross-chain replay blocked | `chainId` in domain separator | ✓ |
| ERC-7739 detection via `isValidSignature(0x7739...7739, "")` | OZ `ERC7739` returns `0x77390001` | ✓ |

### ERC-165 (Interface Detection)

| Interface | Expected ID | Declared |
|-----------|-------------|----------|
| `IAccount` (v0.8/v0.9 `PackedUserOperation`) | `0x19822f7c` | ✓ |
| `IERC1271` | `0x1626ba7e` | ✓ |
| `IERC721Receiver` | `0x150b7a02` | ✓ |
| `IERC1155Receiver` | `0x4e2312e0` | ✓ |
| `IERC165` | `0x01ffc9a7` | ✓ |
| ERC-7739 | — | Not applicable (no ERC-165 ID; see INFO-3) |

---

## Attack Surface Analysis

### Front-running `initialize()` — **Mitigated**

`initialize` requires `msg.sender == address(this)`. Under EIP-7702 the only entity that can satisfy this is the EOA itself. No external contract or EOA can call `initialize` on someone else's account. The delegation + initialization should be bundled in the same type-4 transaction (`authorization_list` + `calldata = initialize(entryPoint_)`) to eliminate any window.

Verified by: `test_attack_frontRunInitialize_reverts`, `test_attack_initializeViaCallback_reverts`.

### Re-initialization — **Mitigated**

`AlreadyInitialized()` is thrown on any second call to `initialize`. The flag lives in the wallet's private ERC-7201 namespace, preventing cross-implementation collisions (CVF-1 fix).

Verified by: `test_attack_reinitialize_reverts`.

### Unauthorized Execution — **Mitigated**

`execute` and `deployDeterministic` are gated by `onlyEntryPointOrSelf`, which checks `initialized` before comparing `msg.sender`. An uninitialized account cannot execute anything, even via direct self-call.

Verified by: `test_attack_unauthorizedExecute_reverts`, `test_attack_stealEther_reverts`, `test_attack_stealTokens_reverts`.

### UserOp with Wrong Signer — **Mitigated**

`_rawSignatureValidation` (ecrecover, from `SignerEIP7702`) returns `false` for any signature not from the EOA. The function never reverts — it returns `1` for bundler simulation compatibility.

Verified by: `test_attack_wrongSignerUserOp_fails`, fuzz tests.

### UserOp Replay — **Mitigated**

EntryPoint nonce management prevents replay. The nonce is per `(sender, key)` and monotonically increases.

Verified by: `test_attack_replayUserOp_reverts`.

### ERC-1271 Cross-Account Replay — **Mitigated**

The ERC-7739 domain separator includes `verifyingContract = address(this)` (the specific EOA). A signature valid for Alice's account is rejected by Bob's.

Verified by: `test_attack_erc1271CrossAccountReplay_rejected`.

### Uninitialized Account Exploitation — **Mitigated**

Both modifiers check `initialized` and revert `NotInitialized()` before the address comparison. An uninitialized wallet is completely inert for all entry points.

Verified by: `test_attack_uninitializedAccount_isInert`.

### Re-entrancy — **Mitigated via Access Control**

`execute` and `deployDeterministic` perform external calls but are gated by `onlyEntryPointOrSelf`. A re-entrant call from the external target would have `msg.sender == target`, which satisfies neither guard condition. No `delegatecall` is used — a malicious target cannot modify the wallet's storage.

Documented in contract-level NatSpec (commit `6ce9a04`).

### Dual Nonce System — **Not Applicable**

Only CREATE2 (`deployDeterministic`) is supported. CREATE2 is nonce-independent. No EVM nonce drift risk exists.

### ETH Prefund on Invalid Signature — **Mitigated**

`_rawSignatureValidation` is called before the `missingAccountFunds` transfer (CR-6 fix). An invalid-signature UserOp returns `1` without spending any account ETH.

---

## EIP-7702 Residual Risks

These are inherent properties of EIP-7702 with no smart-contract-level mitigation. Protocol integrators must be aware.

| Risk | Description |
|------|-------------|
| **Re-delegation** | The EOA can re-delegate to a different implementation at any time. Storage persists, but a new implementation may interpret it differently. |
| **Delegation revocation** | The EOA can revoke delegation entirely. Pending UserOps in the mempool will fail at execution time. |
| **Legacy transaction bypass** | The EOA can always sign type-0/1/2 transactions that bypass `validateUserOp` entirely. |
| **EOA key compromise** | A stolen private key enables signing UserOps, re-delegation, or direct account drainage via legacy transactions. No on-chain recovery mechanism. |
| **ERC-1271 cache staleness** | Protocols caching `isValidSignature` results must re-validate — the delegation and thus the signer can change. |
| **EntryPoint immutability** | After initialization, the EntryPoint cannot be changed without re-delegating to a new implementation. |

---

## Static Analysis

### Slither (Trail of Bits)

4 informational findings — all assembly usage, all intentional and necessary:

| Instance | Function | Purpose |
|----------|----------|---------|
| ID-0 | `_getEntryPointStorage()` | ERC-7201 slot assignment — no Solidity syntax alternative |
| ID-1 | `validateUserOp` | ETH prefund transfer — avoids 2300-gas stipend of `transfer`/`send` |
| ID-2 | `_call` | Low-level CALL with revert data bubbling — avoids ABI re-encode |
| ID-3 | `deployDeterministic` | CREATE2 opcode — no built-in Solidity alternative for arbitrary bytecode |

No high, medium, or low findings.

### Aderyn (Cyfrin)

5 findings in current report:

| ID | Finding | Verdict |
|----|---------|---------|
| H-1 | Contract locks Ether without withdraw | **False positive** — EOA withdraws via `execute()` or direct legacy transaction |
| L-1 | Unspecific Solidity Pragma (`^0.8.34`) | **Acknowledged** — intentional CVF-6 fix; exact pin would reintroduce the original finding |
| L-2 | PUSH0 Opcode | **Not applicable** — Prague EVM is required for EIP-7702; PUSH0 (Shanghai) predates Prague |
| L-3 | Modifier Invoked Only Once (`onlyEntryPoint`) | **Acknowledged** — separation of `onlyEntryPoint` / `onlyEntryPointOrSelf` is intentional access control design |
| L-4 | Unused State Variable (`ENTRY_POINT_STORAGE_LOCATION`) | **False positive** — Aderyn's own note: "No analysis performed to see if assembly references it." It is referenced in `_getEntryPointStorage()` |

---

## Test Coverage

| Test File | Scenarios |
|-----------|-----------|
| `AttackTests.t.sol` + `.v08.t.sol` | 12 adversarial scenarios × 2 EntryPoint versions |
| `Fuzz.t.sol` | 14 property-based fuzz tests (signature, prefund, execution, CREATE2, ERC-165) |
| `ValidateUserOp.t.sol` + `v08/` | Valid sig, wrong signer, non-EntryPoint, prefund (paymaster + self-funded), E2E |
| `Execute.t.sol` + `v08/` | Direct call, EntryPoint routing, uninitialized guard |
| `Deploy.t.sol` + `v08/` | Success, with value, event, empty bytecode, salt collision, constructor revert, unauthorized, via UserOp |
| `ERC721Reception.t.sol` + `v08/` | `_mint`, `transferFrom`, `safeTransferFrom` (with/without data), `safeMint`, send via execute, callback magic value |
| `ERC1155Reception.t.sol` + `v08/` | Unsafe mint, safe mint, `safeTransferFrom`, `safeBatchTransferFrom`, mint batch, send/batch-send, callback magic values |
| `IsValidSignature.t.sol` | Valid EOA sig, wrong signer, invalid length |
| `TypedDataSign.t.sol` | Valid TypedDataSign, wrong signer, cross-account replay |
| `ERC1271.t.sol` | Domain values, cross-account replay, ERC-7739 detection |
| `StorageLocation.t.sol` | ERC-7201 slot verification (step-by-step and aggregate) |
| `Walkthrough*.t.sol` | End-to-end: ERC-20 transfer (no paymaster), with paymaster, CREATE2 deployment |
| `script/DeployTSmartAccount7702.t.sol` | Salt derivation, CREATE2 address determinism, impl locking, interface support, EIP-712 domain, code presence, script dry-run |
| `gas/EndToEnd.t.sol` | Gas profiling (E2E paymaster and non-paymaster) |

**141 tests, 0 failures.** All V09 test suites are mirrored for EntryPoint v0.8 via abstract/concrete inheritance.

---

## Conclusion

`TSmartAccount7702` v1.0.1 is well-implemented and correctly addresses all 12 ABDK audit findings. The contract is conservatively scoped — no modules, no delegatecall exposure, no multi-owner complexity. Storage isolation via ERC-7201 private namespacing is correct. Re-entrancy protection via access control is structurally sound and documented. The three informational notes (super-chain `supportsInterface`, immutable EntryPoint, ERC-7739 via `isValidSignature`) are design trade-offs that are either intentional or not actionable at the contract level.

**No open findings. All ABDK findings correctly addressed.**
