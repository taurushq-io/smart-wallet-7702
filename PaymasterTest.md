# PaymasterTest

This document explains the test in:

- `test/TSmartAccount7702/v08/SponsorPaymaster.v08.t.sol`

## Purpose

Verify that `TSmartAccount7702` can execute a sponsored UserOperation through **EntryPoint v0.8.0** using Circle's `SponsorPaymaster` (from `buidl-wallet-contracts`).

The test confirms:

1. The UserOperation executes successfully.
2. Gas is charged to the paymaster deposit.
3. The smart account balance is unchanged (sponsored mode).

## Test Setup (`setUp`)

The setup does the following:

1. Deploy EntryPoint v0.8 (via `UseEntryPointV08`).
2. Deploy and prepare `TSmartAccount7702` in the existing test base.
3. Deploy `MockTarget` (the call target).
4. Create a paymaster signer key/address and paymaster owner address.
5. Deploy `SponsorPaymaster` implementation + `ERC1967Proxy` and initialize it with:
   - `paymasterOwner`
   - one verifying signer (`paymasterSigner`)
6. Fund paymaster in EntryPoint:
   - `deposit{value: 10 ether}()`
   - `addStake{value: 1 ether}(1)`

## Main Test Flow

### 1. Build a sponsored UserOperation

`_buildSponsoredUserOp(payload)` creates a `PackedUserOperation` that calls:

- `TSmartAccount7702.execute(target.setData(payload))`

with realistic gas fields:

- `verificationGasLimit = 500_000`
- `callGasLimit = 500_000`
- `paymasterVerificationGasLimit = 120_000`
- `paymasterPostOpGasLimit = 60_000`
- `preVerificationGas = 50_000`
- `maxPriorityFeePerGas = 1 gwei`
- `maxFeePerGas = 30 gwei`

### 2. Create paymaster signature

The paymaster hash is obtained from `SponsorPaymaster.getHash(...)` (called via `_sponsorGetHash`).

Then the test signs:

- `toEthSignedMessageHash(paymasterHash)`

with `paymasterSignerPrivateKey`.

The signature is appended into `paymasterAndData` in this format:

- paymaster address
- paymaster verification gas limit (`uint128`)
- paymaster post-op gas limit (`uint128`)
- `abi.encode(validUntil, validAfter)`
- paymaster signature

### 3. Sign account UserOperation

After paymaster data is attached, the account signature is added with `_sign(op)` (the wallet owner signature over `entryPoint.getUserOpHash(op)`).

### 4. Execute through EntryPoint

`_sendUserOperation(op)` submits the operation via `entryPoint.handleOps(...)`.

## Assertions

After execution, the test checks:

1. `target.datahash()` equals `keccak256(payload)`.
   - Confirms wallet call execution happened.
2. `sponsorPaymaster.getDeposit()` is lower than before.
   - Confirms gas was paid from paymaster deposit.
3. `address(account).balance` unchanged.
   - Confirms account did not pay gas directly.

## Why `_sponsorGetHash` uses `staticcall`

The helper uses low-level `staticcall` to `getHash` with explicit ABI encoding for the tuple. This avoids Solidity type friction between different `PackedUserOperation` import paths while still calling the real `SponsorPaymaster` logic.
