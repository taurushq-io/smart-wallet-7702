# Diff: v0.3.0 (``) → v1.0.0 (`TSmartAccount7702.sol`)

This document compares the two versions, flags every behavioral change, and assesses whether any functionality was removed or a bug introduced.

---

## Summary

| Category | Count |
|---|---|
| Security improvements | 5 |
| Behavioral changes (intentional) | 3 |
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

**Removed**: `Initializable` from OZ — consequence of CVF-1 (replaced by wallet-local `initialized` flag).

**Added**: `IERC165`, `IERC1271`, `IERC721Receiver`, `IERC1155Receiver` — needed to use `type(...).interfaceId` in `supportsInterface` instead of hardcoded magic values (CVF-12).

---

## 3. Contract inheritance

| v0.3.0 | v1.0.0 |
|---|---|
| `ERC7739, SignerEIP7702, IAccount, Initializable` | `ERC7739, SignerEIP7702, IAccount` |

`Initializable` removed (CVF-1). No other base contracts changed.

---

## 4. New constants

```solidity
// v1.0.0 only
string private constant VERSION = "1.0.0";
```

`VERSION` replaces the hardcoded `"0.3.0"` string in `version()` (CVF-11).

A `bytes4 private constant ERC7739_INTERFACE_ID = 0x77390001` was introduced as part of CVF-12 but subsequently removed: ERC-7739 defines no new function signatures and therefore has no ERC-165 interface ID. The `0x77390001` value is the detection sentinel for `isValidSignature`, not a computed interface ID. It is absent from v1.0.0.

---

## 5. Error signatures — BEHAVIORAL CHANGE

| v0.3.0 | v1.0.0 |
|---|---|
| `error Unauthorized()` | `error Unauthorized(address caller)` |
| _(none)_ | `error AlreadyInitialized()` |
| _(none)_ | `error NotInitialized()` |
| _(none)_ | `error AddressZeroForEntryPointNotAllowed()` |

`Unauthorized` now carries the offending `caller` address. This changes the ABI selector — off-chain tooling or tests that decode the old `Unauthorized()` selector (`0x82b42900`) will not match the new `Unauthorized(address)` selector (`0x8e4a23d6`). No security regression; improved debuggability.

---

## 6. `EntryPointStorage` struct

| v0.3.0 | v1.0.0 |
|---|---|
| `{ address entryPoint; }` | `{ address entryPoint; bool initialized; }` |

The `bool initialized` flag was added to replace OZ `Initializable`'s `_initialized` counter (CVF-1). Both fields are packed in the same 32-byte slot — no extra storage slot consumed.

---

## 7. Constructor

| v0.3.0 | v1.0.0 |
|---|---|
| Calls `_disableInitializers()` | Empty body |

`_disableInitializers()` was removed as a side effect of removing `Initializable`. The protection is now provided by `require(msg.sender == address(this), ...)` in `initialize()`, which can never be satisfied by an external caller on the bare implementation.

---

## 8. `initialize()` — SECURITY IMPROVEMENTS

### v0.3.0
```solidity
function initialize(address entryPoint_) external initializer {
    if (msg.sender != address(this)) revert Unauthorized();
    _getEntryPointStorage().entryPoint = entryPoint_;
    emit EntryPointSet(entryPoint_);
}
```

### v1.0.0
```solidity
function initialize(address entryPoint_) external {
    require(msg.sender == address(this), Unauthorized(msg.sender));
    require(entryPoint_ != address(0), AddressZeroForEntryPointNotAllowed());
    EntryPointStorage storage $ = _getEntryPointStorage();
    require(!$.initialized, AlreadyInitialized());
    $.initialized = true;
    $.entryPoint = entryPoint_;
    emit EntryPointSet(entryPoint_);
}
```

**Changes:**
- OZ `initializer` modifier replaced by wallet-local `$.initialized` flag (CVF-1 — avoids shared slot collision with other OZ `Initializable` contracts).
- `address(0)` guard added: `initialize(address(0))` now reverts with `AddressZeroForEntryPointNotAllowed()` instead of silently setting a zero EntryPoint that makes the wallet permanently inert.
- `AlreadyInitialized()` error replaces the silent OZ revert on double-init — gives a clear diagnostic.

---

## 9. Access control modifiers — BEHAVIORAL CHANGE

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
    EntryPointStorage storage $ = _getEntryPointStorage();
    require($.initialized, NotInitialized());
    require(msg.sender == $.entryPoint, Unauthorized(msg.sender));
    _;
}
modifier onlyEntryPointOrSelf() {
    EntryPointStorage storage $ = _getEntryPointStorage();
    require($.initialized, NotInitialized());
    require(msg.sender == $.entryPoint || msg.sender == address(this), Unauthorized(msg.sender));
    _;
}
```

**Changes (CVF-2):**
- Both modifiers now check `$.initialized` first and revert with `NotInitialized()` if not yet initialized, instead of silently reverting with `Unauthorized()` (which was misleading when the root cause was missing initialization).
- **Behavioral change for `onlyEntryPointOrSelf`**: In v0.3.0, a direct EOA self-call (`msg.sender == address(this)`) to `execute()` or `deployDeterministic()` would have passed the modifier even before `initialize()` was called (since the EOA check is independent of initialization state). In v1.0.0, all access-controlled functions are blocked until initialization — including direct self-calls. This is intentional and correct: calling `execute()` before the EntryPoint is set is meaningless.

---

## 10. `validateUserOp()` — SECURITY IMPROVEMENT

### v0.3.0 order
1. Pay `missingAccountFunds` to EntryPoint
2. Validate signature → return 1 if invalid

### v1.0.0 order
1. Validate signature → return 1 if invalid
2. Pay `missingAccountFunds` to EntryPoint

**Impact**: In v0.3.0, an invalid signature still triggered an ETH transfer to the EntryPoint before returning `SIG_VALIDATION_FAILED`. In v1.0.0, no ETH is sent when the signature is invalid. Since `_rawSignatureValidation` is ecrecover-based and never reverts (only returns `true`/`false`), this reordering is safe. The account avoids unnecessary ETH exposure on failing UserOps.

---

## 11. `supportsInterface()` — BUG FIX

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

## 12. Token receiver callbacks — return value expression

| v0.3.0 | v1.0.0 |
|---|---|
| `return 0x150b7a02;` | `return IERC721Receiver.onERC721Received.selector;` |
| `return 0xf23a6e61;` | `return IERC1155Receiver.onERC1155Received.selector;` |
| `return 0xbc197c81;` | `return IERC1155Receiver.onERC1155BatchReceived.selector;` |

Same class of issue as CVF-12: hardcoded `bytes4` literals replaced with `.selector` expressions so the return value is self-documenting and a copy-paste mismatch becomes a compile-time impossibility. The spec-mandated values (`0x150b7a02`, `0xf23a6e61`, `0xbc197c81`) were verified against the ERC-721 and ERC-1155 specifications. No behavioral change.

---

## 13. `version()` return value

| v0.3.0 | v1.0.0 |
|---|---|
| `return "0.3.0";` | `return VERSION;` (value: `"1.0.0"`) |

---

## 14. `deployDeterministic()` empty bytecode check style

| v0.3.0 | v1.0.0 |
|---|---|
| `if (creationCode.length == 0) revert EmptyBytecode();` | `require(creationCode.length != 0, EmptyBytecode());` |

Identical bytecode output. Style change only (consistent with the rest of the contract).

---

## 15. Re-entrancy NatSpec

v1.0.0 adds a contract-level `@dev` paragraph documenting the re-entrancy protection model:

> Re-entrancy protection is provided by access control rather than a `nonReentrant` mutex. `execute()` and `deployDeterministic()` perform external calls but are gated by `onlyEntryPointOrSelf`: a re-entrant call from the target would have `msg.sender` equal to the target address, which is neither the EntryPoint nor `address(this)`, so it reverts. Future maintainers must preserve this invariant.

No code change — documentation only.

---

## Conclusion

All public functions present in v0.3.0 are present in v1.0.0 with the same signatures (except `Unauthorized` error selector change). No functionality was removed. The key improvements are:

1. **CVF-1**: Storage slot collision risk eliminated — wallet-local `initialized` flag replaces shared OZ slot.
2. **CVF-2**: `NotInitialized()` error gives actionable diagnostics when modifiers fire pre-init.
3. **CVF-6**: Flexible pragma allows patch compiler updates.
4. **CVF-12**: `supportsInterface` uses `type(...).interfaceId` — fixes wrong `IAccount` interface ID.
5. **CR-1**: `address(0)` guard on `initialize()`.
6. **CR-6**: Signature validated before prefund payment.
