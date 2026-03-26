# Diff: v0.3.0 (TOld.sol) → v1.0.0 (src/TSmartAccount7702.sol)

## 1. Pragma version

**Old**: `pragma solidity 0.8.34;` (exact/pinned)
**New**: `pragma solidity ^0.8.34;` (floating — allows 0.8.34 and above)

---

## 2. EntryPoint: Storage → Immutable

**Old** (`TOld.sol`): EntryPoint stored in ERC-7201 namespaced storage, set via `initialize()`.
```solidity
// ERC-7201 storage
struct EntryPointStorage { address entryPoint; }
bytes32 private constant ENTRY_POINT_STORAGE_LOCATION = 0x38a124a...;

function initialize(address entryPoint_) external initializer {
    if (msg.sender != address(this)) revert Unauthorized();
    _getEntryPointStorage().entryPoint = entryPoint_;
}
```

**New** (`src/`): EntryPoint is an immutable set in the constructor. No storage, no initializer.
```solidity
address public immutable ENTRY_POINT;

constructor(address entryPoint_) EIP712("TSmart Account 7702", "1") {
    require(entryPoint_ != address(0), EntryPointAddressZero());
    ENTRY_POINT = entryPoint_;
}
```

---

## 3. Removed: `Initializable` + `initialize()` + `_disableInitializers()`

Old contract inherited `Initializable` and required a two-step setup (delegation + `initialize()` call). New contract removes this entirely — no initialization needed.

---

## 4. `validateUserOp`: Signature check moved before prefund payment

**Old**: Pay prefund first, then validate signature.

**New**: Validate signature first — if invalid, return 1 immediately without sending ETH to the EntryPoint.

```solidity
// New order:
if (!_rawSignatureValidation(userOpHash, userOp.signature)) return 1;
if (missingAccountFunds > 0) { assembly { pop(call(...)) } }
```

---

## 5. `Unauthorized` error now includes caller address

**Old**: `error Unauthorized();`
**New**: `error Unauthorized(address caller);`

---

## 6. New error: `EntryPointAddressZero`

Guards the constructor against `address(0)` being passed as the EntryPoint.

---

## 7. `supportsInterface`: Removed ERC-7739 ID, use typed interface IDs

**Old**: Hardcoded magic bytes including `0x77390001` (ERC-7739) and legacy v0.6 `IAccount` ID (`0x3a871cdd`).

**New**: Uses `type(I...).interfaceId` for correctness. ERC-7739 removed (no ERC-165 ID defined by the standard).

---

## 8. Version: `"0.3.0"` → `"1.0.0"` (stored as `private constant`)

---

## 9. Minor: `deployDeterministic` uses `require` instead of `if/revert`

**Old**: `if (creationCode.length == 0) revert EmptyBytecode();`
**New**: `require(creationCode.length != 0, EmptyBytecode());`
