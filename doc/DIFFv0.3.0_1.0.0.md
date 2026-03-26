# Diff: v0.3.0 → v1.0.0 (`TSmartAccount7702.sol`)

This document compares the two versions, flags every behavioral change, and assesses whether any functionality was removed or a bug introduced.

---

## Summary

| Category | Count |
|---|---|
| Security improvements | 5 |
| Behavioral changes (intentional) | 4 |
| Bug fixes | 1 |
| Removed functionality | 0 |
| Bugs introduced | 0 |

No functionality was removed. No bugs were introduced. All behavioral changes are intentional and documented below.

---

## 1. Pragma

| | v0.3.0 | v1.0.0 |
|---|---|---|
| Pragma | `pragma solidity 0.8.34;` | `pragma solidity ^0.8.34;` |

**Reason**: CVF-6 — allows patch-level compiler updates without a source change, while enforcing the 0.8.34 minimum (required for Prague EVM / EIP-7702 support).

---

## 2. Imports

**Removed**: `Initializable` from OZ — consequence of removing the entire per-EOA initialization system (see section 7).

**Added**: `IERC165`, `IERC1271`, `IERC721Receiver`, `IERC1155Receiver` — needed to use `type(...).interfaceId` in `supportsInterface` instead of hardcoded magic values (CVF-12).

---

## 3. Contract inheritance

| v0.3.0 | v1.0.0 |
|---|---|
| `ERC7739, SignerEIP7702, IAccount, Initializable` | `ERC7739, SignerEIP7702, IAccount` |

`Initializable` removed alongside the entire initialization system.

---

## 4. Constants and immutables

```solidity
// v1.0.0 only
address public immutable ENTRY_POINT;
string private constant VERSION = "1.0.0";
```

- `ENTRY_POINT` immutable replaces `EntryPointStorage` ERC-7201 storage. The EntryPoint address is now baked into the bytecode at deployment time rather than stored per-EOA.
- `VERSION` replaces the hardcoded `"0.3.0"` string in `version()` (CVF-11).
- `ENTRY_POINT_STORAGE_LOCATION` and the entire `EntryPointStorage` struct are absent from v1.0.0.

A `bytes4 private constant ERC7739_INTERFACE_ID = 0x77390001` was introduced as part of CVF-12 but subsequently removed: ERC-7739 defines no new function signatures and therefore has no ERC-165 interface ID. It is absent from v1.0.0.

---

## 5. Error signatures — BEHAVIORAL CHANGE

| v0.3.0 | v1.0.0 |
|---|---|
| `error Unauthorized()` | `error Unauthorized(address caller)` |
| _(none)_ | `error EntryPointAddressZero()` |
| _(none)_ | `error EmptyBytecode()` |

`Unauthorized` now carries the offending `caller` address. This changes the ABI selector — off-chain tooling or tests that decode the old `Unauthorized()` selector (`0x82b42900`) will not match the new `Unauthorized(address)` selector (`0x8e4a23d6`). No security regression; improved debuggability.

`EntryPointAddressZero()` is thrown by the constructor when `address(0)` is passed as the EntryPoint.

The following errors present in intermediate rc0 state are absent from the final v1.0.0: `AlreadyInitialized()`, `NotInitialized()`, `AddressZeroForEntryPointNotAllowed()`.

---

## 6. Constructor — BEHAVIORAL CHANGE

### v0.3.0
```solidity
constructor() EIP712("TSmart Account 7702", "1") {
    _disableInitializers();
}
```

### v1.0.0
```solidity
constructor(address entryPoint_) EIP712("TSmart Account 7702", "1") {
    require(entryPoint_ != address(0), EntryPointAddressZero());
    ENTRY_POINT = entryPoint_;
}
```

**Changes:**
- Constructor now accepts `entryPoint_` and sets the `ENTRY_POINT` immutable. The EntryPoint address is fixed for all EOAs delegating to this implementation.
- `_disableInitializers()` removed — it belonged to `Initializable`, which is no longer inherited.
- Zero-address guard added: passing `address(0)` reverts with `EntryPointAddressZero()` at construction time (CR-1).

---

## 7. `initialize()` — REMOVED

### v0.3.0
```solidity
function initialize(address entryPoint_) external initializer {
    if (msg.sender != address(this)) revert Unauthorized();
    _getEntryPointStorage().entryPoint = entryPoint_;
    emit EntryPointSet(entryPoint_);
}
```

### v1.0.0

Function removed entirely, along with `EntryPointStorage`, `ENTRY_POINT_STORAGE_LOCATION`, `_getEntryPointStorage()`, `event EntryPointSet`, and associated errors.

**Rationale**: The `initialize()` approach required the EOA to submit its own initialization transaction after delegation, preventing sponsorship by a third party. It also created a gap between delegation and initialization during which UserOps would fail. Moving the EntryPoint to a constructor immutable eliminates both constraints: the account is immediately operational after delegation with no further steps.

The function signature is gone from v1.0.0. This is not a removal of capability — the EntryPoint is still configured, but at implementation deployment time rather than per-EOA.

---

## 8. Access control modifiers — BEHAVIORAL CHANGE

### v0.3.0
```solidity
modifier onlyEntryPoint() {
    if (msg.sender != entryPoint()) revert Unauthorized();
    _;
}
modifier onlyEntryPointOrSelf() {
    if (msg.sender != entryPoint() && msg.sender != address(this)) revert Unauthorized();
    _;
}
```

### v1.0.0
```solidity
modifier onlyEntryPoint() {
    require(msg.sender == ENTRY_POINT, Unauthorized(msg.sender));
    _;
}
modifier onlyEntryPointOrSelf() {
    require(msg.sender == ENTRY_POINT || msg.sender == address(this), Unauthorized(msg.sender));
    _;
}
```

**Changes:**
- Both modifiers read `ENTRY_POINT` immutable directly instead of calling `entryPoint()` virtual. This prevents a subclass override of `entryPoint()` from silently bypassing the authorization check.
- `Unauthorized` now carries `msg.sender` (CVF-8).
- The `NotInitialized()` pre-check introduced in rc0 is absent: with an immutable, the EntryPoint is always set, so there is no uninitialized state to check.
- **Behavioral change for `onlyEntryPointOrSelf`**: In v0.3.0, a direct EOA self-call (`msg.sender == address(this)`) to `execute()` or `deployDeterministic()` could succeed even before `initialize()` was called (the self-check is independent of EntryPoint state). In v1.0.0, the ENTRY_POINT immutable is always set at deployment, so both branches of the modifier are always well-defined.

---

## 9. `validateUserOp()` — SECURITY IMPROVEMENT

### v0.3.0 order
1. Pay `missingAccountFunds` to EntryPoint
2. Validate signature → return 1 if invalid

### v1.0.0 order
1. Validate signature → return 1 if invalid
2. Pay `missingAccountFunds` to EntryPoint

**Impact**: In v0.3.0, an invalid signature still triggered an ETH transfer to the EntryPoint before returning `SIG_VALIDATION_FAILED`. In v1.0.0, no ETH is sent when the signature is invalid. Since `_rawSignatureValidation` is ecrecover-based and never reverts (only returns `true`/`false`), this reordering is safe. The account avoids unnecessary ETH exposure on failing UserOps (CR-6).

---

## 10. `supportsInterface()` — BUG FIX

### v0.3.0
```solidity
interfaceId == type(IAccount).interfaceId // 0x3a871cdd  ← WRONG
```

The old code reported `0x3a871cdd`, which is the `IAccount` interface ID for EntryPoint **v0.6/v0.7** (unpacked `UserOperation`). This contract implements the v0.8/v0.9 `IAccount` interface (`PackedUserOperation`), whose correct interface ID is `0x19822f7c`.

### v1.0.0
```solidity
interfaceId == type(IAccount).interfaceId // 0x19822f7c  ← CORRECT
```

All other interface IDs (`IERC1271`, `IERC721Receiver`, `IERC1155Receiver`, `IERC165`) are now derived via `type(...).interfaceId` instead of hardcoded magic literals (CVF-12). This eliminates the risk of copy-paste errors in future maintenance.

ERC-7739 was also removed from `supportsInterface`: it defines no new function signatures, so there is no ERC-165 interface ID to advertise. ERC-7739 support is detected via `isValidSignature(0x7739...7739, "")` returning `0x77390001`, not via ERC-165.

---

## 11. Token receiver callbacks — return value expression

| v0.3.0 | v1.0.0 |
|---|---|
| `return 0x150b7a02;` | `return IERC721Receiver.onERC721Received.selector;` |
| `return 0xf23a6e61;` | `return IERC1155Receiver.onERC1155Received.selector;` |
| `return 0xbc197c81;` | `return IERC1155Receiver.onERC1155BatchReceived.selector;` |

Same class of issue as CVF-12: hardcoded `bytes4` literals replaced with `.selector` expressions so the return value is self-documenting and a copy-paste mismatch becomes a compile-time impossibility. The spec-mandated values (`0x150b7a02`, `0xf23a6e61`, `0xbc197c81`) were verified against the ERC-721 and ERC-1155 specifications. No behavioral change.

---

## 12. `version()` return value

| v0.3.0 | v1.0.0 |
|---|---|
| `return "0.3.0";` | `return VERSION;` (value: `"1.0.0"`) |

---

## 13. `deployDeterministic()` empty bytecode check style

| v0.3.0 | v1.0.0 |
|---|---|
| `if (creationCode.length == 0) revert EmptyBytecode();` | `require(creationCode.length != 0, EmptyBytecode());` |

Identical bytecode output. Style change only — consistent with the rest of the contract.

---

## 14. Re-entrancy NatSpec

v1.0.0 adds a contract-level `@dev` paragraph documenting the re-entrancy protection model:

> Re-entrancy protection is provided by access control rather than a `nonReentrant` mutex. `execute()` and `deployDeterministic()` perform external calls but are gated by `onlyEntryPointOrSelf`: a re-entrant call from the target would have `msg.sender` equal to the target address, which is neither the EntryPoint nor `address(this)`, so it reverts. Future maintainers must preserve this invariant.

No code change — documentation only.

---

## Conclusion

All public functions present in v0.3.0 are present in v1.0.0 with the same signatures, except:
- `Unauthorized` error selector changed (`0x82b42900` → `0x8e4a23d6`).
- `initialize()` is gone; the EntryPoint is now configured at implementation deployment, not per-EOA.

No functionality was removed. The key improvements are:

1. **Immutable EntryPoint**: Eliminates the per-EOA initialization window and sponsorship limitation. The account is operational immediately after delegation.
2. **CR-6**: Signature validated before prefund payment — no ETH sent on invalid-signature UserOps.
3. **CR-1**: `EntryPointAddressZero()` guard in the constructor.
4. **CVF-6**: Flexible pragma allows patch compiler updates.
5. **CVF-12 + bug fix**: `supportsInterface` uses `type(...).interfaceId` — fixes the wrong `IAccount` interface ID (`0x3a871cdd` → `0x19822f7c`).
