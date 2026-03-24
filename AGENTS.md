# Smart Account 7702 — Code Architecture

## Project Overview

A minimal ERC-4337 smart account designed for EIP-7702 delegation. Built with Foundry, targeting Solidity 0.8.33 with the Prague EVM.

The account allows an EOA to delegate its execution logic to `TSmartAccount7702` via EIP-7702, enabling ERC-4337 UserOperation flows with paymaster gas sponsorship while the EOA retains full ownership.

## Tech Stack

- **Framework**: Foundry (forge, cast, anvil)
- **Solidity**: 0.8.33, Prague EVM, optimizer enabled (999999 runs, via-ir)
- **ERC-4337**: EntryPoint v0.9 at `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`
- **Key Dependencies**: OpenZeppelin (ERC7739, SignerEIP7702, EIP712, Initializable), account-abstraction (IAccount, EntryPoint)

## Directory Structure

```
smart-wallet-7702/
├── src/
│   └── TSmartAccount7702.sol         # Main ERC-4337 account contract
├── test/
│   ├── TSmartAccount7702/            # Unit tests
│   │   ├── SmartWalletTestBase.sol  # Shared test setup (simulates 7702 via vm.etch)
│   │   ├── ValidateUserOp.t.sol
│   │   ├── Execute.t.sol
│   │   ├── Deploy.t.sol            # CREATE2 unit tests (edge cases, access control)
│   │   ├── EthReception.t.sol      # receive() / fallback() ETH reception tests
│   │   ├── ERC721Reception.t.sol   # ERC-721 safeTransferFrom / safeMint / send tests
│   │   ├── ERC1155Reception.t.sol  # ERC-1155 safeTransferFrom / batch / send tests
│   │   ├── IsValidSignature.t.sol
│   │   ├── TypedDataSign.t.sol     # ERC-7739 TypedDataSign nested signature tests
│   │   ├── Fuzz.t.sol              # Property-based fuzz tests (14 tests: signature, prefund, execution, deploy, ERC-165)
│   │   ├── StorageLocation.t.sol   # On-chain ERC-7201 slot computation verification
│   │   ├── entrypoint/
│   │   │   ├── UseEntryPointV09.sol # Mixin: deploys EntryPoint v0.9.0
│   │   │   └── UseEntryPointV08.sol # Mixin: deploys EntryPoint v0.8.0
│   │   └── v08/                     # V08 EntryPoint variants (same tests, different EP)
│   │       ├── Execute.v08.t.sol
│   │       ├── Deploy.v08.t.sol
│   │       ├── ValidateUserOp.v08.t.sol
│   │       ├── ERC721Reception.v08.t.sol
│   │       └── ERC1155Reception.v08.t.sol
│   ├── walkthrough/                 # Step-by-step documentation tests
│   │   ├── WalkthroughBase.sol      # Abstract base with shared actors & helpers
│   │   ├── WalkthroughSimple.t.sol  # ERC-20 transfer (no paymaster, gasFees=0)
│   │   ├── WalkthroughPaymaster.t.sol # ERC-20 transfer with paymaster (realistic gas)
│   │   └── WalkthroughDeploy.t.sol  # Contract deployment via CREATE2 UserOps
│   ├── mocks/
│   │   ├── MockEntryPoint.sol
│   │   ├── MockERC20.sol            # OZ ERC20 with public mint
│   │   ├── MockERC721.sol           # OZ ERC721 with public mint/safeMint
│   │   ├── MockERC1155.sol          # OZ ERC1155 with safe/unsafe mint
│   │   ├── MockPaymaster.sol        # Accept-all paymaster for testing
│   │   ├── MockTarget.sol
│   │   └── SimpleStorage.sol        # Shared minimal contract for deploy tests
│   ├── ERC1271.t.sol
│   ├── AttackTests.t.sol            # Adversarial tests (14 scenarios, abstract base + V09)
│   ├── AttackTests.v08.t.sol        # AttackTests V08 variant (same 14 scenarios, EntryPoint v0.8)
│   ├── script/
│   │   └── DeployTSmartAccount7702.t.sol # Deploy script verification (salt, CREATE2, locking, interfaces)
│   └── gas/
│       └── EndToEnd.t.sol           # E2E gas profiling
├── script/
│   └── DeployTSmartAccount7702.s.sol # Deterministic CREATE2 deployment
├── doc/
│   ├── fuzzing.md                   # Fuzz testing methodology and variable documentation

│   ├── audit/
│   │   └── tool/
│   │       ├── aderyn/
│   │       │   ├── aderyn-report.md  # Aderyn static analysis raw report
│   │       │   └── aderyn-report-feedback.md # Verdict and analysis for each finding
│   │       └── slither/
│   │           ├── slither-report.md # Slither static analysis raw report
│   │           └── slither-report-feedback.md # Verdict and analysis for each finding
│   ├── ERC/                         # EIP reference docs
│   └── circle/                      # Circle Paymaster docs
├── lib/                             # Dependencies (git submodules)
├── foundry.toml                     # Foundry config
└── remappings.txt                   # Import remappings
```

## Contract Architecture

### Inheritance Graph

```
TSmartAccount7702
  ├── ERC7739 (OZ draft — ERC-1271 + ERC-7739 anti-replay)
  │     ├── IERC1271
  │     ├── EIP712 (domain separator, eip712Domain)
  │     └── AbstractSigner
  ├── SignerEIP7702 (OZ — _rawSignatureValidation: ecrecover == address(this))
  │     └── AbstractSigner
  ├── IAccount (ERC-4337)
  └── Initializable (OZ — one-time initialization guard)
```

### Core Contracts

#### `TSmartAccount7702.sol` — Main Account (~285 lines)

Minimal ERC-4337 account for EIP-7702 delegation.

- **`initialize`**: Sets the trusted EntryPoint address. Must be called once per EOA after EIP-7702 delegation. Protected by OZ `Initializable` — cannot be called twice on the same EOA. Requires `msg.sender == address(this)` to prevent front-running. Emits `EntryPointSet(address entryPoint)`.
- **`validateUserOp`**: Verifies `msg.sender == entryPoint()`, calls `_rawSignatureValidation` (from `SignerEIP7702`) to check `ecrecover == address(this)` (the EOA). Pays `missingAccountFunds` to the EntryPoint when no paymaster is present (self-funded mode).
- **`isValidSignature`**: ERC-1271 signature validation with ERC-7739 anti-replay (from `ERC7739`). Supports both `PersonalSign` and `TypedDataSign` nested flows.
- **`execute`**: Executes a call via CALL opcode. Restricted to EntryPoint or self.
- **`deployDeterministic`**: Deploys a contract via CREATE2. Restricted to EntryPoint or self. Reverts with `EmptyBytecode()` on empty creation code. Emits `ContractDeployed(address deployed)`. The deployer is `address(this)` (the EOA under EIP-7702).
- **`onERC721Received` / `onERC1155Received` / `onERC1155BatchReceived`**: Token receiver callbacks returning the expected magic values. Required because EIP-7702 gives the EOA code, so `safeTransferFrom` checks receiver callbacks. Without these, ERC-721 safe transfers and ALL ERC-1155 transfers would revert.

**Custom Errors:**

| Error | Trigger |
|---|---|
| `Unauthorized()` | Caller is not authorized (wrong `msg.sender`) |
| `EmptyBytecode()` | `deployDeterministic()` called with zero-length creation code |

**Events:**

| Event | Emitted by |
|---|---|
| `EntryPointSet(address indexed entryPoint)` | `initialize()` |
| `ContractDeployed(address indexed deployed)` | `deployDeterministic()` |

**Access Control:**

| Function | Guard |
|---|---|
| `initialize` | `initializer` (once per EOA) |
| `validateUserOp` | `onlyEntryPoint` |
| `execute` | `onlyEntryPointOrSelf` |
| `deployDeterministic` | `onlyEntryPointOrSelf` |
| `onERC721Received` / `onERC1155Received` / `onERC1155BatchReceived` | None (pure, public) |

### Initialization Model

The account uses a **proxy-style initialization pattern** adapted for EIP-7702:

```
1. Deploy implementation ──> constructor() calls _disableInitializers()
                              EIP712 immutables (name, version) baked into bytecode

2. EOA signs EIP-7702 authorization tuple
   ──> EOA's code now points to the implementation bytecode

3. EOA calls initialize(entryPoint) on itself (msg.sender == address(this))
   ──> _entryPoint stored in the EOA's own storage
   ──> initializer modifier prevents re-initialization
   ──> only the EOA can call initialize (prevents front-running)
```

**How it works under EIP-7702:**

- The **constructor** runs once during implementation deployment. `EIP712("TSmart Account 7702", "1")` sets immutables (name/version hashes, cached domain separator) in the bytecode. `_disableInitializers()` sets the `Initializable` storage flag to `type(uint64).max` in the implementation's storage, locking the implementation itself.
- When an EOA **delegates** via EIP-7702, it gets the implementation's bytecode but keeps its own storage. The EOA's `Initializable` storage is clean (`_initialized = 0`), so `initialize()` can be called exactly once.
- The EIP-712 **domain separator cache** (`_cachedThis`, `_cachedDomainSeparator`) stores the implementation's address at construction. Under delegation, `address(this)` is the EOA, so the cache misses and `_domainSeparatorV4()` always rebuilds from scratch. This is correct but wastes a few gas on the conditional check.
- `_entryPoint` is stored in **ERC-7201 namespaced storage** (slot `0x38a1...7a00`, derived from `"smartaccount7702.entrypoint"`), set via `initialize()`. Each EOA can configure its own EntryPoint. The namespaced slot prevents collision with prior delegation storage.

**Pros:**

- **Per-EOA EntryPoint**: Each delegating EOA can target a different EntryPoint version (v0.7, v0.8, v0.9) by passing a different address to `initialize()`. With the immutable approach, all EOAs sharing the same implementation were locked to one EntryPoint.
- **Familiar pattern**: Uses the same `Initializable` + `initializer` pattern from OpenZeppelin that developers and auditors know from proxy contracts. Reduces review friction.
- **Re-initialization protection**: OZ `Initializable` uses ERC-7201 namespaced storage to track initialization state, preventing double-initialization even if the EOA re-delegates to the same implementation.
- **Implementation locking**: `_disableInitializers()` in the constructor prevents initialization on the implementation contract itself — standard security practice for proxy-compatible contracts.
- **Forward-compatible**: If more per-EOA configuration is needed in the future (e.g., guardians, modules, spending limits), `reinitializer(2)` can add new initialization steps without redeploying.

**Cons:**

- **Higher gas for `entryPoint()` reads**: `_entryPoint` is now a storage SLOAD (~2100 gas cold, ~100 gas warm) instead of an immutable (~3 gas). This adds ~2000 gas to the first call per transaction that touches `entryPoint()` (typically `validateUserOp`). Subsequent calls in the same transaction are warm (100 gas).
- **Extra transaction step**: The EOA must call `initialize(entryPoint)` after delegation. This is typically bundled in the same transaction as the EIP-7702 authorization tuple, but it is an additional calldata cost.
- **Increased bytecode size**: `Initializable` adds ~200 bytes of bytecode for the ERC-7201 namespaced storage and initialization guards.
- **Uninitialized state risk**: If `initialize()` is not called after delegation, `entryPoint()` returns `address(0)`. The `onlyEntryPoint` modifier will block all UserOps (no address matches `address(0)`), so the account is inert — not exploitable, but non-functional until initialized.
- **Self-call required for init**: `initialize()` requires `msg.sender == address(this)` to prevent front-running. This means the EOA must send the initialization transaction itself (type-4 tx with `to = self`). Third-party relayers cannot initialize on behalf of the EOA.

### Contract Deployment (CREATE2)

The wallet supports deploying contracts deterministically from the EOA via ERC-4337 UserOperations. This requires a dedicated `deployDeterministic()` function because `execute()` uses the `CALL` opcode, which cannot create contracts.

**How it works:**

```
UserOp.callData = abi.encodeCall(TSmartAccount7702.deployDeterministic, (value, creationCode, salt))

EntryPoint → validateUserOp() → deployDeterministic() → CREATE2 opcode → new contract
```

Under EIP-7702, the deployer is `address(this)` = the EOA. So `msg.sender` in the child contract's constructor is the EOA address. The deployed address is deterministic: `keccak256(0xff ++ deployer ++ salt ++ keccak256(creationCode))`.

### Key Design Decisions

- **Dual EntryPoint version testing**: All tests that route through the real EntryPoint (`handleOps`) are tested against both v0.9.0 and v0.8.0. Test logic is in abstract contracts; concrete V09/V08 classes inherit it with different `UseEntryPointV09`/`UseEntryPointV08` mixins. V08 variants live in `test/TSmartAccount7702/v08/`.
- **Dual gas model**: Supports both paymaster-sponsored and self-funded UserOperations. Pays `missingAccountFunds` to EntryPoint when no paymaster is present.
- **No UUPS proxy**: EIP-7702 re-delegation is the native upgrade mechanism.
- **No multi-owner**: `address(this)` is the EOA. Only the EOA's key can sign.
- **No factory**: EOA delegates directly to the implementation.
- **Initializable EntryPoint**: Each EOA sets its own EntryPoint via `initialize()` after delegation. The implementation constructor disables initialization on itself.

## Build & Test

```bash
forge build
forge test
forge test --gas-report
forge test --match-contract TestFuzz --fuzz-runs 10000  # extended fuzz testing
forge test --match-path "test/TSmartAccount7702/v08/*"   # run V08 EntryPoint tests only
forge build --profile deploy
```

See [`doc/fuzzing.md`](doc/fuzzing.md) for a detailed explanation of fuzzed variables, input constraints, and testing methodology.

## Deployment Flow

```bash
# 1. Deploy the implementation (initializers disabled on the implementation itself)
forge script script/DeployTSmartAccount7702.s.sol --broadcast

# 2. Each EOA delegates to the implementation via EIP-7702 authorization tuple

# 3. Each EOA initializes with its chosen EntryPoint
cast send <EOA_ADDRESS> "initialize(address)" <ENTRY_POINT_ADDRESS>
```

## Remappings

```
account-abstraction/ → lib/account-abstraction/contracts/       (v0.9.0)
account-abstraction-v0.8/ → lib/account-abstraction-v0.8/contracts/ (v0.8.0)
forge-std/ → lib/forge-std/src/
@openzeppelin/contracts/ → lib/openzeppelin-contracts/contracts/
```
