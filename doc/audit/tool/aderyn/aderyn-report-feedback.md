# Aderyn Static Analysis — Feedback

This document provides feedback on each finding from the [Aderyn](https://github.com/Cyfrin/aderyn) static analysis report (`aderyn-report.md`).

---

## H-1: Contract locks Ether without a withdraw function

> It appears that the contract includes a payable function to accept Ether but lacks a corresponding function to withdraw it, which leads to the Ether being locked in the contract.

**Status: False positive**

This is an EIP-7702 delegated account, not a standalone contract. Under EIP-7702, `address(this)` is the EOA itself. The contract does not hold ETH in its own storage — the ETH belongs to the EOA.

The EOA can withdraw ETH in two ways:

1. **Via `execute()`**: The EntryPoint or the EOA itself calls `execute(recipient, amount, "")` to transfer ETH. This is the standard ERC-4337 withdrawal path.
2. **Direct EOA transaction**: The EOA can always send a regular transaction (type-0/1/2) to transfer ETH, just like any normal EOA. EIP-7702 delegation does not remove the EOA's ability to sign native transactions.

The `receive()` and `fallback()` functions are essential: with EIP-7702, the EOA has code (`address.code.length > 0`), so plain ETH transfers require `receive()` to succeed. Without it, the delegating EOA would be unable to receive ETH at all.

No withdraw function is needed because the EOA is the account.

---

## L-1: Literal Instead of Constant

> Define and use `constant` variables instead of using literals. `0x150b7a02` used in both `supportsInterface` and `onERC721Received`.

**Status: Acknowledged — mitigated via tests**

The literal `0x150b7a02` (`IERC721Receiver.onERC721Received.selector`) appears twice in the source: once in `supportsInterface` and once as the return value of `onERC721Received`. The same pattern applies to the other callback selectors (`0xf23a6e61`, `0xbc197c81`) though those each appear only once.

Introducing a named constant is one option, but these are ERC-defined selectors, not arbitrary values. Replacing them with `type(IERC721Receiver).interfaceId` in the source would add an import and slightly increase bytecode without improving safety — the values are specified by the ERC standards and will never change.

The risk of a typo is mitigated by two layers of testing:

1. **`supportsInterface` tests** (`Fuzz.t.sol`, `DeployTSmartAccount7702.t.sol`) use `type(IERC721Receiver).interfaceId`, `type(IERC1155Receiver).interfaceId`, `type(IERC1271).interfaceId`, and `type(IERC165).interfaceId` — computed from OpenZeppelin interface definitions. If the source had the wrong value, these tests would fail.

2. **Callback return value tests** (`ERC721Reception.t.sol`, `ERC1155Reception.t.sol`) perform actual token transfers via OpenZeppelin's `safeTransferFrom` and `safeMint`. The OZ token contracts check the callback return value and revert if it doesn't match. A wrong literal in the source would cause these tests to fail.

---

## L-2: Modifier Invoked Only Once

> Consider removing the modifier or inlining the logic into the calling function.
>
> Found: `onlyEntryPoint()` modifier.

**Status: Acknowledged — no change (intentional design)**

`onlyEntryPoint` is used only by `validateUserOp`, while `onlyEntryPointOrSelf` is used by `execute` and `deployDeterministic`. Having two separate modifiers is an intentional security design:

- **`onlyEntryPoint`**: Only the EntryPoint can call `validateUserOp`. The EOA itself must NOT be able to call it — `validateUserOp` is a validation function that returns `0` (valid) or `1` (invalid), not a function the owner should invoke directly.
- **`onlyEntryPointOrSelf`**: The EntryPoint or the EOA can call execution functions. The EOA needs direct access for non-UserOp transactions.

Inlining the check into `validateUserOp` would work functionally, but the named modifier communicates intent clearly: reviewers immediately see "this function is EntryPoint-only" without reading the body. This is valuable in a security-critical contract where access control boundaries must be obvious.

The single-use pattern is common in audited smart accounts (Coinbase Smart Wallet, Light Account, Safe) for the same reason.

---

## L-3: Unused State Variable

> State variable appears to be unused. `ENTRY_POINT_STORAGE_LOCATION` — no analysis has been performed to see if any inline assembly references it.

**Status: False positive**

`ENTRY_POINT_STORAGE_LOCATION` is used in inline assembly inside `_getEntryPointStorage()`:

```solidity
function _getEntryPointStorage() private pure returns (EntryPointStorage storage $) {
    assembly {
        $.slot := ENTRY_POINT_STORAGE_LOCATION
    }
}
```

Aderyn's note acknowledges this limitation: "No analysis has been performed to see if any inline assembly references it." The variable is indeed referenced — it is the ERC-7201 namespaced storage slot for the EntryPoint address.

This slot's correctness is verified on-chain by `StorageLocation.t.sol`, which recomputes the ERC-7201 formula and asserts it matches the hardcoded constant.

