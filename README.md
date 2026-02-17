# Smart Account 7702

A minimal [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) smart account designed for [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) delegation.

> This project is a fork of [Coinbase Smart Wallet](https://github.com/coinbase/smart-wallet), simplified for the EIP-7702 single-EOA model.

## Overview

With EIP-7702, an EOA delegates its execution logic to this contract. `address(this)` inside the contract **is** the EOA address, so multi-owner management is unnecessary — the EOA's private key is the sole authority.

The contract supports:
- ERC-4337 UserOperation validation (signature recovery against `address(this)`)
- Single and batch execution (`execute`, `executeBatch`)
- Contract deployment (`deploy`, `deployDeterministic`)
- ERC-1271 signature validation with cross-account replay protection
- ETH and ERC-721/ERC-1155 token receiving

## Architecture

### Contract Structure

```
SmartAccount7702 is ERC1271, IAccount, Receiver
```

| Contract | Description |
|---|---|
| `SmartAccount7702.sol` | Main ERC-4337 account with execute, deploy, and signature validation |
| `ERC1271.sol` | Abstract ERC-1271 with anti-replay EIP-712 domain binding |

### Access Control

| Function | Guard |
|---|---|
| `validateUserOp` | `onlyEntryPoint` |
| `execute` / `executeBatch` | `onlyEntryPointOrSelf` |
| `deploy` / `deployDeterministic` | `onlyEntryPointOrSelf` |

`onlyEntryPointOrSelf` allows both the EntryPoint (for UserOp execution) and the EOA itself (for direct transactions, since `msg.sender == address(this)` with 7702 delegation).

### Contract Description Table

|     Contract      |       Type       |          Bases           |                |               |
| :---------------: | :--------------: | :----------------------: | :------------: | :-----------: |
|         └         | **Function Name** |      **Visibility**      | **Mutability** | **Modifiers** |
|                   |                  |                          |                |               |
| **SmartAccount7702** |  Implementation  | ERC1271, IAccount, Receiver |                |               |
|         └         |  validateUserOp  |       External ❗️        |       🛑        | onlyEntryPoint |
|         └         |     execute      |       External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         |   executeBatch   |       External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         |      deploy      |       External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         | deployDeterministic |    External ❗️        |       💵        | onlyEntryPointOrSelf |
|         └         |    entryPoint    |        Public ❗️         |                |      NO❗️      |
|         └         | _isValidSignature |      Internal 🔒        |                |               |
|         └         |      _call       |       Internal 🔒        |       🛑        |               |
|         └         | _domainNameAndVersion | Internal 🔒           |                |               |

#### Legend

| Symbol | Meaning                   |
| :----: | ------------------------- |
|   🛑    | Function can modify state |
|   💵    | Function is payable       |

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

- **Multi-owner management**: The EOA's private key is the sole signer. `validateUserOp` verifies `ECDSA.recover(userOpHash, signature) == address(this)`.
- **Factory**: No proxy deployment is needed. Each EOA delegates directly to the deployed implementation contract.
- **Initialization**: No `initialize()` call is needed. `address(this)` is already the EOA.

## Integration Flow

```
1. Deploy SmartAccount7702 implementation contract
2. Bob's EOA delegates to SmartAccount7702 via EIP-7702 authorization tuple
3. No initialization needed — address(this) is already Bob
4. Bob signs EIP-2612 permit for USDC → Circle Paymaster
5. UserOp submitted to bundler (e.g. Pimlico)
6. EntryPoint → validateUserOp() recovers signature == address(this) ✓
7. Circle Paymaster pays gas in USDC
8. execute() runs the target call
```

## Ethereum API

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

### deploy / deployDeterministic

```solidity
function deploy(uint256 value, bytes calldata bytecode) external payable onlyEntryPointOrSelf returns (address)
function deployDeterministic(uint256 value, bytes calldata bytecode, bytes32 salt) external payable onlyEntryPointOrSelf returns (address)
```

Deploys contracts using CREATE or CREATE2.

### entryPoint

```solidity
function entryPoint() public pure returns (address)
```

Returns the EntryPoint v0.9 address: `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`.

## Developing

After cloning the repo, install dependencies and run tests:

```bash
forge install
forge test
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
forge script script/DeployFactory.s.sol --rpc-url $RPC_URL --account $ACCOUNT --broadcast
```

Each EOA then delegates to the deployed implementation address via an EIP-7702 authorization tuple.

## Influences

Based on [Coinbase Smart Wallet](https://github.com/coinbase/smart-wallet), with code originally from Solady's [ERC4337](https://github.com/Vectorized/solady/blob/main/src/accounts/ERC4337.sol). Also influenced by [DaimoAccount](https://github.com/daimo-eth/daimo/blob/master/packages/contract/src/DaimoAccount.sol) and [LightAccount](https://github.com/alchemyplatform/light-account).
