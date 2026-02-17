# Fuzz Testing — SmartAccount7702

**Source**: [`test/SmartAccount7702/Fuzz.t.sol`](../test/SmartAccount7702/Fuzz.t.sol)

## What is Fuzz Testing?

Fuzz testing (or property-based testing) is a technique where the test framework generates **random inputs** for function parameters and runs the test hundreds or thousands of times. Instead of checking a single handpicked value, fuzz tests verify that a **property** (an invariant) holds for every possible input.

In Foundry, any test function with parameters is automatically treated as a fuzz test. Foundry generates 256 random inputs per run by default.

```solidity
// Fixed test — checks ONE hash
function test_validateUserOp() public {
    bytes32 hash = keccak256("123");
    // ...
}

// Fuzz test — Foundry generates 256 random hashes
function testFuzz_validateUserOp(bytes32 userOpHash) public {
    // ...
}
```

## Why Fuzz This Contract?

SmartAccount7702 is a security-critical contract that handles:

- **Signature validation** — ECDSA recovery determines who can authorize UserOperations
- **ETH transfers** — `validateUserOp` pays prefund to the EntryPoint; `execute` sends ETH
- **Token transfers** — `execute` routes arbitrary calldata to external contracts
- **Interface detection** — `supportsInterface` must return correct values for integrators

A single edge case (e.g., a `userOpHash` value that causes `ecrecover` to return an unexpected address) could break the wallet's security. Fuzz testing explores the input space far more broadly than handwritten tests.

## Test Inventory

The fuzz test suite contains **12 tests** organized into 5 categories.

### 1. `validateUserOp` — Signature Validation

These tests verify that ECDSA signature validation in `validateUserOp` behaves correctly for all possible `userOpHash` values.

| Test | Fuzzed Variables | Property |
|---|---|---|
| `testFuzz_validateUserOp_validSignature` | `userOpHash: bytes32` | Signing any hash with the owner's key always returns 0 (valid) |
| `testFuzz_validateUserOp_wrongSigner` | `userOpHash: bytes32`, `wrongKey: uint256` | Signing any hash with any other key always returns 1 (invalid) |
| `testFuzz_validateUserOp_garbageSignature` | `userOpHash: bytes32`, `garbageSig: bytes` | Random byte arrays (non-65-byte) never pass validation |

**What is `userOpHash`?** The EntryPoint computes a hash of the entire UserOperation (including chain ID and EntryPoint address). The wallet's private key signs this hash. Fuzzing it means testing that signature verification works regardless of the hash content.

**What is `wrongKey`?** A random secp256k1 private key in the range `[1, 2^128]`, excluding the owner's key (`0xa11ce`). This simulates an attacker signing with their own key.

**What is `garbageSig`?** Completely random bytes of any length. Tests that malformed signatures (wrong length, random data) are always rejected. The 65-byte case is excluded from the strict assertion because a random 65-byte input *could* theoretically be a valid `(r, s, v)` tuple that recovers to the account address — astronomically unlikely, but not logically impossible.

### 2. `validateUserOp` — Prefund Payment

These tests verify the ETH transfer logic in the dual gas model (paymaster vs. self-funded).

| Test | Fuzzed Variables | Property |
|---|---|---|
| `testFuzz_validateUserOp_prefund` | `userOpHash: bytes32`, `prefund: uint256` | The exact prefund amount is transferred from account to EntryPoint |
| `testFuzz_validateUserOp_zeroPrefund` | `userOpHash: bytes32`, `accountBalance: uint256` | When prefund is 0 (paymaster present), no ETH moves |

**What is `prefund`?** The `missingAccountFunds` parameter passed by the EntryPoint. Bounded to `[1 wei, 100 ETH]` to stay within realistic values. The test funds the account with exactly this amount and verifies the full transfer.

**What is `accountBalance`?** A random ETH balance set on the account (bounded to `[0, 100 ETH]`). Even with a large balance, zero prefund must leave both the account and EntryPoint balances unchanged.

### 3. `isValidSignature` — PersonalSign (ERC-1271)

These tests verify the ERC-1271 signature validation path used by dApps (e.g., "Sign this message" prompts).

| Test | Fuzzed Variables | Property |
|---|---|---|
| `testFuzz_isValidSignature_personalSign_valid` | `hash: bytes32` | Any hash signed via ERC-7739 PersonalSign with the owner's key returns `0x1626ba7e` |
| `testFuzz_isValidSignature_personalSign_wrongSigner` | `hash: bytes32`, `wrongKey: uint256` | Any hash signed with a wrong key returns `0xffffffff` |
| `testFuzz_isValidSignature_garbageSignature` | `hash: bytes32`, `garbageSig: bytes` | Non-65-byte garbage always returns `0xffffffff` |

**What is `hash`?** The application-level hash that a dApp passes to `isValidSignature`. The test wraps it in the ERC-7739 PersonalSign envelope (with the account's EIP-712 domain separator) before signing. Fuzzing the hash verifies that the wrapping and unwrapping work for any input.

**ERC-7739 wrapping**: The actual hash signed is `keccak256("\x19\x01" || domainSeparator || keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, hash)))`. This binds the signature to the specific account (via `address(this)` in the domain separator) and prevents cross-account replay.

### 4. `execute` — Execution

These tests verify that the `execute` function correctly transfers ETH and ERC-20 tokens.

| Test | Fuzzed Variables | Property |
|---|---|---|
| `testFuzz_execute_ethTransfer` | `amount: uint256`, `recipient: address` | ETH arrives exactly at the recipient; account balance is zeroed |
| `testFuzz_execute_erc20Transfer` | `amount: uint256`, `recipient: address` | ERC-20 tokens arrive exactly at the recipient; account balance is zeroed |

**What is `amount`?** A random transfer amount. ETH is bounded to `[0, 100 ETH]`. ERC-20 is bounded to `[1, 2^128]`.

**What is `recipient`?** A random address, with constraints:
- Not `address(0)` (ERC-20 would revert)
- Not the account itself (would confuse balance assertions)
- Not precompile addresses 1–9 (could have side effects)
- Not the EntryPoint (could trigger deposit logic)
- For ETH: must have no code (to avoid reverting `receive`/`fallback`)

### 5. `supportsInterface` — ERC-165

| Test | Fuzzed Variables | Property |
|---|---|---|
| `testFuzz_supportsInterface_unknownId` | `interfaceId: bytes4` | Any interface ID not in the known set returns `false` |

**What is `interfaceId`?** A random 4-byte value. The test excludes the 6 known supported IDs (`IAccount`, ERC-1271, ERC-7739, `IERC721Receiver`, `IERC1155Receiver`, ERC-165) via `vm.assume`. Every other value must return `false`.

## Foundry Fuzz Primitives

The tests use three Foundry fuzz helpers:

| Helper | Purpose |
|---|---|
| `bound(value, min, max)` | Constrains a fuzzed `uint256` to a range. Does not discard — maps the input into the range. |
| `vm.assume(condition)` | Discards the current fuzz run if the condition is false. Used sparingly because too many discards slow down fuzzing. |
| `vm.sign(privateKey, hash)` | Signs a hash with the given private key. Returns `(v, r, s)`. |

## Running the Tests

```bash
# Run with default 256 runs
forge test --match-contract TestFuzz

# Run a specific test
forge test --match-test testFuzz_validateUserOp_validSignature

# Increase runs for deeper coverage (recommended before deployment)
forge test --match-contract TestFuzz --fuzz-runs 10000

# Verbose output (see individual run details)
forge test --match-contract TestFuzz -vvv
```

To set a permanent default, add to `foundry.toml`:

```toml
[fuzz]
runs = 1000
```

## Limitations

- **65-byte garbage signatures**: A random 65-byte input could theoretically be a valid ECDSA `(r, s, v)` that recovers to the account's address. The probability is roughly 1 in 2^160 (address space), so the fuzzer will never find one in practice, but the test conservatively skips the strict assertion for 65-byte inputs.
- **No TypedDataSign fuzzing**: The ERC-7739 TypedDataSign path requires constructing a valid nested EIP-712 envelope with matching type strings and domain bytes. Fuzzing the raw inputs would produce structurally invalid envelopes that are rejected before reaching signature validation. The TypedDataSign path is covered by fixed tests in `TypedDataSign.t.sol`.
- **No cross-chain fuzzing**: All tests run on a single chain ID (`block.chainid`). Cross-chain replay protection is inherent to the EIP-712 domain separator (which includes `chainId`), but this is not directly fuzzed.
