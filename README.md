# Smart Account 7702

A minimal [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) smart account designed for [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) delegation.

> This project is a fork of [Coinbase Smart Wallet](https://github.com/coinbase/smart-wallet), simplified for the EIP-7702 single-EOA model.

## Overview

With EIP-7702, an EOA delegates its execution logic to this contract. `address(this)` inside the contract **is** the EOA address, so multi-owner management is unnecessary — the EOA's private key is the sole authority.

The contract supports:
- ERC-4337 UserOperation validation (signature recovery against `address(this)`)
- Single and batch execution (`execute`, `executeBatch`)
- Contract deployment via CREATE and CREATE2 (`deploy`, `deployDeterministic`)
- ERC-1271 signature validation with ERC-7739 anti-replay protection
- Per-EOA EntryPoint configuration via `initialize()`
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

### Access Control

| Function | Guard |
|---|---|
| `initialize` | `initializer` (once per EOA) |
| `validateUserOp` | `onlyEntryPoint` |
| `execute` / `executeBatch` | `onlyEntryPointOrSelf` |
| `deploy` / `deployDeterministic` | `onlyEntryPointOrSelf` |

`onlyEntryPointOrSelf` allows both the EntryPoint (for UserOp execution) and the EOA itself (for direct transactions, since `msg.sender == address(this)` with 7702 delegation).

### Contract Description Table

|     Contract      |       Type       |          Bases           |                |               |
| :---------------: | :--------------: | :----------------------: | :------------: | :-----------: |
|         └         | **Function Name** |      **Visibility**      | **Mutability** | **Modifiers** |
|                   |                  |                          |                |               |
| **SmartAccount7702** |  Implementation  | ERC7739, SignerEIP7702, IAccount, Initializable |                |               |
|         └         |   initialize     |       External ❗️        |       🛑        | initializer  |
|         └         |  validateUserOp  |       External ❗️        |       🛑        | onlyEntryPoint |
|         └         |     execute      |       External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         |   executeBatch   |       External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         |      deploy      |       External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         | deployDeterministic |    External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         |    entryPoint    |        Public ❗️         |                |      NO❗️      |
|         └         | supportsInterface |       External ❗️       |                |      NO❗️      |
|         └         |      _call       |       Internal 🔒        |       🛑        |               |

#### Legend

| Symbol | Meaning                   |
| :----: | ------------------------- |
|   🛑    | Function can modify state |
|   💵    | Function is payable       |

## Initialization Model

The account uses a **proxy-style initialization pattern** adapted for EIP-7702:

```
1. Deploy implementation ──> constructor() calls _disableInitializers()
                              EIP712 immutables (name, version) baked into bytecode

2. EOA signs EIP-7702 authorization tuple
   ──> EOA's code now points to the implementation bytecode

3. EOA (or anyone) calls initialize(entryPoint)
   ──> _entryPoint stored in the EOA's own storage
   ──> initializer modifier prevents re-initialization
```

Each delegating EOA has its own storage, so `initialize()` can be called once per EOA independently. The implementation contract itself is locked by `_disableInitializers()` in the constructor.

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

## Design Decisions

### No Prefund Payment

This account is designed to work exclusively with a paymaster (e.g. the [Circle USDC Paymaster](https://developers.circle.com/paymaster)) for gas sponsorship. The `missingAccountFunds` parameter in `validateUserOp` is intentionally ignored because:

- The paymaster covers all gas costs, so `missingAccountFunds` is always `0` when a paymaster is present in the UserOperation
- The account does not need to hold ETH for gas purposes
- This simplifies the contract and reduces attack surface

If you need an account that self-pays for gas (without a paymaster), you must add prefund logic back to `validateUserOp`.

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

Sets the trusted EntryPoint address. Must be called once after EIP-7702 delegation. The `initializer` modifier ensures this cannot be called twice on the same EOA.

### validateUserOp

```solidity
function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
) external onlyEntryPoint returns (uint256 validationData)
```

Validates the UserOperation signature. Returns `0` on success, `1` on signature failure (to support simulation). The signature should be a raw ECDSA signature (`abi.encodePacked(r, s, v)`) — no wrapper struct.

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

Deploys a contract using CREATE. The address depends on the EOA's EVM nonce.

### deployDeterministic

```solidity
function deployDeterministic(uint256 value, bytes calldata creationCode, bytes32 salt)
    external payable onlyEntryPointOrSelf returns (address deployed)
```

Deploys a contract using CREATE2. The address is deterministic: `keccak256(0xff ++ deployer ++ salt ++ keccak256(creationCode))`.

### entryPoint

```solidity
function entryPoint() public view returns (address)
```

Returns the EntryPoint address configured via `initialize()`.

## Walkthrough Tests

The `test/walkthrough/` directory contains step-by-step tests designed to be read as documentation. Each test logs every step with `console2.log` — run with `forge test -vvv` to see the full narrative.

| Test | Description |
|---|---|
| `WalkthroughSimple` | ERC-20 transfer via UserOp (no paymaster, gasFees=0) |
| `WalkthroughPaymaster` | ERC-20 transfer with a paymaster covering gas (realistic fees) |
| `WalkthroughDeploy` | Contract deployment via CREATE, CREATE2, and deploy-then-interact |

These tests share setup and helpers via the abstract `WalkthroughBase` contract and use a `MockPaymaster` (accept-all) for the paymaster flow.

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

## Influences

Based on [Coinbase Smart Wallet](https://github.com/coinbase/smart-wallet), with code originally from Solady's [ERC4337](https://github.com/Vectorized/solady/blob/main/src/accounts/ERC4337.sol). Also influenced by [DaimoAccount](https://github.com/daimo-eth/daimo/blob/master/packages/contract/src/DaimoAccount.sol) and [LightAccount](https://github.com/alchemyplatform/light-account).
