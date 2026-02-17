# Smart Account 7702

A minimal [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) smart account designed for [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) delegation.

## Overview

With EIP-7702, an EOA delegates its execution logic to this contract. `address(this)` inside the contract **is** the EOA address, so multi-owner management is unnecessary — the EOA's private key is the sole authority.

The contract supports:
- ERC-4337 UserOperation validation (signature recovery against `address(this)`)
- Single and batch execution (`execute`, `executeBatch`)
- Contract deployment via CREATE and CREATE2 (`deploy`, `deployDeterministic`)
- ERC-1271 signature validation with ERC-7739 anti-replay protection
- Per-EOA EntryPoint configuration via `initialize()`
- ERC-721 and ERC-1155 token reception (`onERC721Received`, `onERC1155Received`, `onERC1155BatchReceived`)
- ETH receiving (`receive`, `fallback`)

## Architecture

### Inheritance Graph

```
SmartAccount7702
  ├── ERC7739 (OZ draft — ERC-1271 + ERC-7739 anti-replay)
  │     ├── IERC1271
  │     ├── EIP712 (domain separator, eip712Domain)
  │     └── AbstractSigner
  ├── SignerEIP7702 (OZ — _rawSignatureValidation: ecrecover == address(this))
  │     └── AbstractSigner
  ├── IAccount (ERC-4337)
  └── Initializable (OZ — one-time initialization guard)
```

### EIP-712 Domain

The contract uses the EIP-712 domain name `"TSmart Account 7702"` (version `"1"`), where the "T" stands for **Taurus** — the organization behind this wallet. This name is baked into bytecode immutables at construction and cannot be changed after deployment. All off-chain signing tools, dApps, and integrators must use this exact string to produce valid ERC-1271 / ERC-7739 signatures. The `eip712Domain()` view function returns the domain parameters for programmatic discovery.

### Access Control

| Function | Guard |
|---|---|
| `initialize` | `initializer` (once per EOA) |
| `validateUserOp` | `onlyEntryPoint` |
| `execute` / `executeBatch` | `onlyEntryPointOrSelf` |
| `deploy` / `deployDeterministic` | `onlyEntryPointOrSelf` |

`onlyEntryPointOrSelf` allows both the EntryPoint (for UserOp execution) and the EOA itself (for direct transactions, since `msg.sender == address(this)` with 7702 delegation).

### Contract Description Table

| Function | Visibility | Mutability | Modifiers |
|---|---|---|---|
| `initialize` | External | State-changing | `initializer` |
| `validateUserOp` | External | State-changing | `onlyEntryPoint` |
| `execute` | External | Payable | `onlyEntryPointOrSelf` |
| `executeBatch` | External | Payable | `onlyEntryPointOrSelf` |
| `deploy` | External | Payable | `onlyEntryPointOrSelf` |
| `deployDeterministic` | External | Payable | `onlyEntryPointOrSelf` |
| `entryPoint` | Public | View | — |
| `supportsInterface` | Public | View | — |
| `onERC721Received` | External | Pure | — |
| `onERC1155Received` | External | Pure | — |
| `onERC1155BatchReceived` | External | Pure | — |
| `_call` | Internal | State-changing | — |

### Token Receiver Callbacks

Under EIP-7702, the EOA has code (`address.code.length > 0`), which means ERC-721 `safeTransferFrom` and all ERC-1155 transfers invoke receiver callbacks on the wallet. Without proper callbacks, the ABI decoder fails on the empty `fallback()` return data and the transfer reverts.

This is especially critical for **ERC-1155**, which has **no** non-safe transfer function — without `onERC1155Received`, the wallet cannot receive any ERC-1155 tokens at all.

The contract implements all three receiver callbacks:

| Callback | Returns | Standard |
|---|---|---|
| `onERC721Received` | `0x150b7a02` | ERC-721 |
| `onERC1155Received` | `0xf23a6e61` | ERC-1155 |
| `onERC1155BatchReceived` | `0xbc197c81` | ERC-1155 |

`supportsInterface` advertises `IERC721Receiver` (`0x150b7a02`) and `IERC1155Receiver` (`0x4e2312e0`).

### Custom Errors

| Error | Description |
|---|---|
| `Unauthorized()` | Caller is not authorized (`msg.sender` is not EntryPoint, self, or does not match required identity) |
| `EmptyBytecode()` | `deploy()` or `deployDeterministic()` called with zero-length creation code |

### Events

| Event | Emitted by |
|---|---|
| `Initialized(address indexed entryPoint)` | `initialize()` — logs the EntryPoint address set for this EOA |
| `ContractDeployed(address indexed deployed)` | `deploy()`, `deployDeterministic()` — logs the address of each newly deployed contract |

## Initialization Model

The account uses a **proxy-style initialization pattern** adapted for EIP-7702:

```
1. Deploy implementation ──> constructor() calls _disableInitializers()
                              EIP712 immutables (name, version) baked into bytecode

2. EOA signs EIP-7702 authorization tuple
   ──> EOA's code now points to the implementation bytecode

3. EOA calls initialize(entryPoint) on itself (msg.sender == address(this))
   ──> entryPoint stored in ERC-7201 namespaced storage (no slot collision risk)
   ──> initializer modifier prevents re-initialization
   ──> only the EOA can call initialize (prevents front-running)
```

Each delegating EOA has its own storage, so `initialize()` can be called once per EOA independently. The implementation contract itself is locked by `_disableInitializers()` in the constructor.

The `entryPoint` address is stored in [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) namespaced storage (slot `0x38a1...7a00`, derived from `"smartaccount7702.entrypoint"`). This prevents slot collisions if an EOA previously delegated to a different implementation that wrote to low slots.

## Contract Deployment (CREATE / CREATE2)

The wallet can deploy contracts directly via ERC-4337 UserOperations. This is useful for deploying token contracts, proxies, or factory patterns where the wallet acts as the deployer.

### How it works

```
UserOp.callData = abi.encodeCall(SmartAccount7702.deploy, (value, creationCode))

EntryPoint → validateUserOp() → deploy() → CREATE opcode → new contract
```

Under EIP-7702, the deployer is `address(this)` = the EOA. So `msg.sender` in the child contract's constructor is the EOA address.

### CREATE vs CREATE2

| Aspect | `deploy()` (CREATE) | `deployDeterministic()` (CREATE2) |
|---|---|---|
| Address formula | `keccak256(rlp([deployer, nonce]))` | `keccak256(0xff ++ deployer ++ salt ++ keccak256(creationCode))` |
| Deterministic | No (depends on EVM nonce) | Yes (no nonce dependency) |
| Pre-computable | Only with exact nonce knowledge | Always (deployer + salt + bytecode) |
| Cross-chain same address | Not guaranteed | Guaranteed |

**Important:** The ERC-4337 EntryPoint nonce (UserOp replay protection) and the EVM account nonce (used by CREATE) are completely independent systems. CREATE2 is recommended when the deployed address must be known in advance, as it avoids nonce tracking entirely.

### Usage Example

```solidity
// Deploy via CREATE
bytes memory creationCode = abi.encodePacked(
    type(MyContract).creationCode,
    abi.encode(constructorArg)
);
bytes memory callData = abi.encodeCall(SmartAccount7702.deploy, (0, creationCode));

// Deploy via CREATE2 (deterministic address)
bytes32 salt = bytes32(uint256(0x1234));
bytes memory callData = abi.encodeCall(
    SmartAccount7702.deployDeterministic,
    (0, creationCode, salt)
);
```

## Threat Model

This section documents the attack vectors analyzed against SmartAccount7702 and how each is mitigated. All attacks are covered by tests in `test/AttackTests.t.sol`.

### Front-Running `initialize()`

Without access control on `initialize()`, an attacker monitoring the mempool could front-run the owner after EIP-7702 delegation and set a malicious contract as the EntryPoint. The attacker's contract would then pass `onlyEntryPointOrSelf` and drain the account.

**Mitigation:** `initialize()` requires `msg.sender == address(this)` — only the EOA itself can call it:

```solidity
function initialize(address entryPoint_) external initializer {
    if (msg.sender != address(this)) revert Unauthorized();
    _getEntryPointStorage().entryPoint = entryPoint_;
}
```

In the EIP-7702 flow, the EOA signs a type-4 transaction where `to = address(this)` and `data = abi.encodeCall(initialize, (entryPoint))`. This makes delegation and initialization atomic in a single transaction.

### Attack: Unauthorized Execution

| Attack | Mitigation | Test |
|---|---|---|
| Random address calls `execute()` | `onlyEntryPointOrSelf` reverts | `test_attack_unauthorizedExecute_reverts` |
| Random address calls `executeBatch()` | `onlyEntryPointOrSelf` reverts | `test_attack_unauthorizedExecuteBatch_reverts` |
| Random address calls `deploy()` | `onlyEntryPointOrSelf` reverts | `test_attack_unauthorizedDeploy_reverts` |
| Random address calls `deployDeterministic()` | `onlyEntryPointOrSelf` reverts | `test_attack_unauthorizedDeployDeterministic_reverts` |

The `onlyEntryPointOrSelf` modifier ensures only two callers are allowed:
- The trusted EntryPoint (set via `initialize()`)
- The EOA itself (`msg.sender == address(this)`, for direct transactions)

### Attack: ETH and Token Theft

| Attack | Mitigation | Test |
|---|---|---|
| Drain ETH via `execute(attacker, balance, "")` | `onlyEntryPointOrSelf` blocks unauthorized callers | `test_attack_stealEther_reverts` |
| Drain ERC-20 via `execute(token, 0, transfer(...))` | Same access control | `test_attack_stealTokens_reverts` |

Even if the attacker knows the exact calldata needed to drain the account, they cannot invoke `execute()` because only the EntryPoint or the EOA itself is authorized.

### Attack: Re-Initialization

| Attack | Mitigation | Test |
|---|---|---|
| Call `initialize()` again to change EntryPoint | OpenZeppelin `Initializable` reverts on second call | `test_attack_reinitialize_reverts` |

The `initializer` modifier (from OpenZeppelin) tracks initialization state in ERC-7201 namespaced storage. Once `initialize()` has been called, any subsequent call reverts — even from the EOA itself.

### Attack: Signature Attacks

| Attack | Mitigation | Test |
|---|---|---|
| UserOp signed by wrong private key | `_rawSignatureValidation` returns `false`, `validateUserOp` returns 1 (SIG_VALIDATION_FAILED) | `test_attack_wrongSignerUserOp_fails` |
| Replay a valid UserOp (same nonce) | EntryPoint nonce system rejects duplicate nonces | `test_attack_replayUserOp_reverts` |
| Replay ERC-1271 signature on different account | ERC-7739 domain separator includes `address(this)`, so signature is invalid on any other account | `test_attack_erc1271CrossAccountReplay_rejected` |
| Call `validateUserOp` directly (not via EntryPoint) | `onlyEntryPoint` modifier reverts | `test_attack_validateUserOpFromNonEntryPoint_reverts` |

Signature security relies on three layers:
1. **ECDSA recovery**: `ecrecover(hash, sig) == address(this)` — only the EOA's private key can produce valid signatures
2. **EntryPoint nonce**: Each UserOp must carry a fresh nonce from the EntryPoint's nonce mapping, preventing replay
3. **ERC-7739 domain binding**: ERC-1271 signatures include the account address in the EIP-712 domain separator, preventing cross-account replay

### Attack: Uninitialized Account

| Attack | Mitigation | Test |
|---|---|---|
| Exploit account before `initialize()` is called | `entryPoint()` returns `address(0)`. No real caller can match `address(0)`, so `onlyEntryPoint` blocks everything. `onlyEntryPointOrSelf` only allows the EOA itself. | `test_attack_uninitializedAccount_isInert` |

An uninitialized account is **inert**: it cannot process UserOperations (no EntryPoint) and cannot be called by anyone except the EOA itself. This is a safe default — the account is non-functional but not exploitable.

### Attack: Initialize via Callback

| Attack | Mitigation | Test |
|---|---|---|
| Contract tries to call `initialize()` during a callback | `msg.sender` is the calling contract, not `address(this)` | `test_attack_initializeViaCallback_reverts` |

Even if a malicious contract receives a callback from the wallet, it cannot call `initialize()` because `msg.sender` would be the malicious contract's address, not the EOA's address.

### Residual Risks

These risks are inherent to the EIP-7702 model and cannot be mitigated at the smart contract level:

| Risk | Description |
|---|---|
| **Private key compromise** | If the EOA's private key is stolen, the attacker has full control. There is no multi-sig, guardian, or social recovery — by design, the EOA key is the sole authority. |
| **Re-delegation to malicious implementation** | The EOA can re-delegate to any contract via EIP-7702. If the owner is tricked into signing an authorization tuple pointing to a malicious implementation, the new code could drain the account. |

## Design Decisions

### Dual Gas Model (Paymaster or Self-Funded)

The account supports both gas payment modes:

- **With paymaster**: A paymaster (e.g. the [Circle USDC Paymaster](https://developers.circle.com/paymaster)) sponsors gas. `missingAccountFunds` is `0` and no ETH is needed from the account.
- **Self-funded**: When no paymaster is attached, `validateUserOp` pays `missingAccountFunds` to the EntryPoint from the account's ETH balance. The EOA must hold sufficient ETH to cover gas.

This ensures the wallet remains functional even if a paymaster goes offline or is discontinued.

### No UUPS Proxy

Traditional smart accounts use UUPS proxies for upgradeability. This account does not, because EIP-7702 provides a native upgrade mechanism:

- The EOA can re-delegate to a **new implementation** at any time by signing a new EIP-7702 authorization tuple `(chainId, address, nonce)`
- This is simpler and cheaper than UUPS proxy upgrades
- No proxy storage slots or `delegatecall` indirection is needed
- The EOA retains full control over which implementation it delegates to

### No Multi-Owner / Factory

With EIP-7702, the EOA *is* the wallet. There is no need for:

- **Multi-owner management**: The EOA's private key is the sole signer. `validateUserOp` verifies `ecrecover(userOpHash, signature) == address(this)`.
- **Factory**: No proxy deployment is needed. Each EOA delegates directly to the deployed implementation contract.

### Initializable EntryPoint

Each EOA sets its own EntryPoint via `initialize()` after delegation. This allows different EOAs to target different EntryPoint versions (v0.7, v0.8, v0.9). The implementation constructor disables initialization on itself via `_disableInitializers()`.

## Integration Flow

```
1. Deploy SmartAccount7702 implementation contract
2. Bob's EOA delegates to SmartAccount7702 via EIP-7702 authorization tuple
3. Bob calls initialize(entryPoint) to set his trusted EntryPoint
4. Bob signs EIP-2612 permit for USDC → Circle Paymaster
5. UserOp submitted to bundler (e.g. Pimlico)
6. EntryPoint → validateUserOp() recovers signature == address(this) ✓
7. Circle Paymaster pays gas in USDC
8. execute() / deploy() runs the target action
```

## Ethereum API

### initialize

```solidity
function initialize(address entryPoint_) external initializer
```

Sets the trusted EntryPoint address. Must be called once after EIP-7702 delegation. Only the EOA itself can call this (`msg.sender == address(this)`), preventing front-running attacks. The `initializer` modifier ensures this cannot be called twice on the same EOA. Emits `Initialized(entryPoint)`.

### validateUserOp

```solidity
function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
) external onlyEntryPoint returns (uint256 validationData)
```

Validates the UserOperation signature. Returns `0` on success, `1` on signature failure (to support simulation). The signature should be a raw ECDSA signature (`abi.encodePacked(r, s, v)`) — no wrapper struct. If `missingAccountFunds > 0` (no paymaster), the account pays the required prefund to the EntryPoint from its ETH balance.

### execute

```solidity
function execute(address target, uint256 value, bytes calldata data)
    external payable onlyEntryPointOrSelf
```

Executes a single call from this account.

### executeBatch

```solidity
function executeBatch(Call[] calldata calls) external payable onlyEntryPointOrSelf
```

Executes multiple calls in a batch.

### deploy

```solidity
function deploy(uint256 value, bytes calldata creationCode)
    external payable onlyEntryPointOrSelf returns (address deployed)
```

Deploys a contract using CREATE. The address depends on the EOA's EVM nonce. Reverts with `EmptyBytecode()` if `creationCode` is empty. Emits `ContractDeployed(deployed)`.

### deployDeterministic

```solidity
function deployDeterministic(uint256 value, bytes calldata creationCode, bytes32 salt)
    external payable onlyEntryPointOrSelf returns (address deployed)
```

Deploys a contract using CREATE2. The address is deterministic: `keccak256(0xff ++ deployer ++ salt ++ keccak256(creationCode))`. Reverts with `EmptyBytecode()` if `creationCode` is empty. Emits `ContractDeployed(deployed)`.

### entryPoint

```solidity
function entryPoint() public view returns (address)
```

Returns the EntryPoint address configured via `initialize()`.

## Test Suite

The project has 137 tests across 24 test suites.

### Dual EntryPoint Testing

All tests that route UserOperations through the real EntryPoint are run against **two versions**:

- **EntryPoint v0.9.0** — the latest canonical release
- **EntryPoint v0.8.0** — the previous stable release

This ensures the smart account is compatible with both versions. Test logic is extracted into abstract contracts, and two concrete classes (V09, V08) inherit the same tests with different EntryPoint implementations via `UseEntryPointV09` / `UseEntryPointV08` mixins.

```bash
# Run only V08 tests
forge test --match-path "test/SmartAccount7702/v08/*"

# Run only V09 tests (default)
forge test --match-path "test/SmartAccount7702/*.t.sol"
```

### Unit Tests (`test/SmartAccount7702/`)

| Test File | Coverage | V08 variant |
|---|---|---|
| `ValidateUserOp.t.sol` | Signature validation, wrong signer, non-EntryPoint caller, prefund payment | Yes |
| `Execute.t.sol` | Single call execution, access control, revert bubbling | Yes |
| `ExecuteBatch.t.sol` | Batch execution, empty batch, revert propagation | Yes |
| `Deploy.t.sol` | CREATE/CREATE2 deployment, empty bytecode, constructor revert, salt collision, value forwarding, access control, EntryPoint routing | Yes |
| `IsValidSignature.t.sol` | ERC-7739 PersonalSign path, wrong signer, invalid signature length | — |
| `TypedDataSign.t.sol` | ERC-7739 TypedDataSign path (EIP-712 Permit), wrong signer, cross-account replay | — |
| `EthReception.t.sol` | Plain ETH transfer (`receive`), ETH with data (`fallback`), zero-value calls | — |
| `ERC721Reception.t.sol` | ERC-721 reception via mint, transferFrom, safeTransferFrom, safeMint; sending via execute | Yes |
| `ERC1155Reception.t.sol` | ERC-1155 reception via safeTransferFrom, safeBatchTransferFrom, safeMint, safeMintBatch; sending via execute | Yes |
| `Fuzz.t.sol` | Fuzz tests (256 runs each) for signature validation, prefund, PersonalSign, TypedDataSign, execution, executeBatch, deployDeterministic, and supportsInterface | — |
| `StorageLocation.t.sol` | Verifies on-chain ERC-7201 slot computation matches hardcoded `ENTRY_POINT_STORAGE_LOCATION` | — |

### Walkthrough Tests (`test/walkthrough/`)

Step-by-step tests designed to be read as documentation. Each test logs every step with `console2.log` — run with `forge test -vvv` to see the full narrative.

| Test | Description |
|---|---|
| `WalkthroughSimple` | ERC-20 transfer via UserOp (no paymaster, gasFees=0) |
| `WalkthroughPaymaster` | ERC-20 transfer with a paymaster covering gas (realistic fees) |
| `WalkthroughDeploy` | Contract deployment via CREATE, CREATE2, and deploy-then-interact |

These tests share setup and helpers via the abstract `WalkthroughBase` contract and use a `MockPaymaster` (accept-all) for the paymaster flow.

### Fuzz Tests (`test/SmartAccount7702/Fuzz.t.sol`)

15 property-based fuzz tests (256 runs each by default) covering the core signing, execution, and deployment paths. For a detailed explanation of each fuzzed variable, input constraints, and testing methodology, see [`doc/fuzzing.md`](doc/fuzzing.md).

| Test | Property |
|---|---|
| `testFuzz_validateUserOp_validSignature` | Any `userOpHash` signed with the correct key always validates (returns 0) |
| `testFuzz_validateUserOp_wrongSigner` | Any `userOpHash` signed with a random wrong key always fails (returns 1) |
| `testFuzz_validateUserOp_garbageSignature` | Non-65-byte random data always fails signature validation |
| `testFuzz_validateUserOp_prefund` | Fuzzed `missingAccountFunds` (1–100 ETH) with independent fuzzed balance is correctly transferred; remainder stays |
| `testFuzz_validateUserOp_zeroPrefund` | Zero prefund leaves both balances unchanged regardless of account balance |
| `testFuzz_isValidSignature_personalSign_valid` | Any hash signed via PersonalSign with correct key returns the ERC-1271 magic value |
| `testFuzz_isValidSignature_personalSign_wrongSigner` | Any hash signed with a wrong key returns `0xffffffff` |
| `testFuzz_isValidSignature_garbageSignature` | Non-65-byte garbage always returns `0xffffffff` |
| `testFuzz_isValidSignature_typedDataSign_valid` | Fuzzed permit parameters through full ERC-7739 TypedDataSign encoding validate correctly |
| `testFuzz_execute_ethTransfer` | Fuzzed ETH amounts transfer correctly to fuzzed recipients |
| `testFuzz_execute_erc20Transfer` | Fuzzed ERC-20 amounts transfer correctly to fuzzed recipients |
| `testFuzz_executeBatch_multipleValues` | Fuzzed number of calls (1–8) with fuzzed ETH values distribute correctly |
| `testFuzz_deployDeterministic_predictedAddress` | Fuzzed salt produces deployed address matching CREATE2 prediction |
| `test_supportsInterface_knownIds` | All 6 known interface IDs return `true` |
| `testFuzz_supportsInterface_unknownId` | Random unknown interface IDs always return `false` |

To increase the number of runs:

```bash
forge test --match-contract TestFuzz --fuzz-runs 10000
```

### Attack Tests (`test/AttackTests.t.sol`)

14 adversarial tests that simulate attacks and pass if the attack is correctly prevented. See [Threat Model](#threat-model) for details.

## Developing

After cloning the repo, install dependencies and run tests:

```bash
forge install
forge test
```

Run the walkthrough tests with verbose output to see the step-by-step logs:

```bash
forge test --match-path test/walkthrough -vvv
```

## Deploying

Set in your `.env`:

```bash
# `cast wallet` name
ACCOUNT=
# Node RPC URL
RPC_URL=
```

Then deploy the implementation:

```bash
# 1. Deploy the implementation (initializers disabled on the implementation itself)
forge script script/DeploySmartAccount7702.s.sol --rpc-url $RPC_URL --account $ACCOUNT --broadcast

# 2. Each EOA delegates to the implementation via EIP-7702 authorization tuple

# 3. Each EOA initializes with its chosen EntryPoint
cast send <EOA_ADDRESS> "initialize(address)" <ENTRY_POINT_ADDRESS>
```

## References

Based on [Coinbase Smart Wallet](https://github.com/coinbase/smart-wallet), with code originally from Solady's [ERC4337](https://github.com/Vectorized/solady/blob/main/src/accounts/ERC4337.sol). Also influenced by [DaimoAccount](https://github.com/daimo-eth/daimo/blob/master/packages/contract/src/DaimoAccount.sol) and [LightAccount](https://github.com/alchemyplatform/light-account).

## Intellectual property

This code is copyright (c) 2026 Taurus SA and is licensed under the MIT
