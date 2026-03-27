# Slither Static Analysis: Feedback
**Contract version**: 1.0.0
**Tool**: [Slither](https://github.com/crytic/slither) by Trail of Bits
**Report**: `slither-report.md`

This document provides the verdict and analysis for each finding in the current Slither report.

Slither reported **4 informational findings**: 3 assembly usage instances and 1 naming-convention finding. No high, medium, or low severity issues were found.

Compared to v0.3.0:
- The `_getEntryPointStorage` assembly finding is gone: the entire ERC-7201 storage system was removed, so that function no longer exists.
- A new naming-convention finding appears for `ENTRY_POINT`: Slither flags it as not mixedCase. This is expected for an immutable constant and is intentional.

---

## Summary

| Finding | Verdict |
|---------|---------|
| **Assembly usage** (Informational, 3 instances) | Acknowledged: all intentional and necessary |
| **Naming convention** (Informational, 1 instance) | Acknowledged: intentional, UPPER_CASE is correct for immutables |

No high, medium, or low severity issues detected.

---

## Assembly Usage (Informational, 3 instances)

> Functions that use assembly.

| ID | Function | Lines | Assembly purpose |
|----|----------|-------|-----------------|
| ID-0 | `_call(address,uint256,bytes)` | L267–280 | Low-level CALL with revert data bubbling |
| ID-1 | `validateUserOp(PackedUserOperation,bytes32,uint256)` | L108–145 | ETH prefund transfer to EntryPoint |
| ID-2 | `deployDeterministic(uint256,bytes,bytes32)` | L174–196 | CREATE2 contract deployment |

**Verdict: All acknowledged: assembly is intentional and necessary**

Each use of inline assembly serves a specific purpose that cannot be achieved, or would be significantly more expensive, in pure Solidity:

- **`_call` (ID-0)**: Bubbles revert data from the nested call without Solidity's ABI re-encoding overhead. The `CALL` opcode is used directly to copy calldata and forward it. This is the standard pattern used by OpenZeppelin, Solady, and all major smart wallet implementations.

- **`validateUserOp` (ID-1)**: Sends `missingAccountFunds` ETH to the EntryPoint using a raw low-level call. Using `transfer` or `send` would impose a 2300 gas stipend, which can fail with EntryPoint implementations that have non-trivial `receive` logic. The raw call discards the return value intentionally — the EntryPoint handles any shortfall in its own post-validation balance accounting.

- **`deployDeterministic` (ID-2)**: The CREATE2 opcode is not exposed as a Solidity built-in for arbitrary runtime bytecode. Assembly is the only way to use CREATE2 with caller-supplied creation code.

All assembly blocks are annotated `("memory-safe")` where applicable. The contract compiles cleanly with `via-ir` optimisation enabled and zero warnings.

---

## Naming Convention (Informational, 1 instance)

> Variable [TSmartAccount7702.ENTRY_POINT](src/TSmartAccount7702.sol#L49) is not in mixedCase.

**Verdict: Acknowledged: intentional, no change**

`ENTRY_POINT` is declared `public immutable`. Solidity style conventions treat immutables like constants — UPPER_SNAKE_CASE is the standard and widely adopted naming for both. OpenZeppelin, Solady, and the ERC-4337 reference implementations all use UPPER_SNAKE_CASE for immutables (e.g. `ENTRY_POINT` in Coinbase Smart Wallet).

Slither's naming-convention detector applies mixedCase rules uniformly to all state variables without distinguishing between mutable storage and immutables. The flag is expected and the name is correct as written.
