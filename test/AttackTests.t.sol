// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Test} from "forge-std/Test.sol";

import {TSmartAccount7702} from "../src/TSmartAccount7702.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

/// @title AttackTests
///
/// @notice Adversarial tests against TSmartAccount7702. Every test simulates an attack
///         and PASSES if the attack is correctly prevented.
///
/// @dev Attack vectors tested:
///
///      1. Direct unauthorized execute() / deployDeterministic()
///      2. ETH theft via execute()
///      3. ERC-20 theft via execute()
///      4. UserOp with wrong signer
///      5. UserOp replay (same nonce)
///      6. ERC-1271 cross-account signature replay
///      7. validateUserOp from non-EntryPoint
///
/// @dev Abstract base — concrete classes provide the EntryPoint version via `_deployEntryPoint()`.
abstract contract AttackTestsBase is Test {
    // -----------------------------------------------------------------------
    // Actors
    // -----------------------------------------------------------------------

    uint256 aliceKey;
    address alice;

    uint256 attackerKey;
    address attacker;

    address bundler = makeAddr("bundler");

    // -----------------------------------------------------------------------
    // Contracts
    // -----------------------------------------------------------------------

    IEntryPoint entryPoint = IEntryPoint(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);
    TSmartAccount7702 smartAccount;
    MockERC20 usdc;

    // -----------------------------------------------------------------------
    // Setup helpers
    // -----------------------------------------------------------------------

    /// @dev Override to deploy the EntryPoint bytecode at the canonical address.
    function _deployEntryPoint() internal virtual;

    /// @dev Deploys infrastructure and simulates EIP-7702 delegation.
    function _setup() internal {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (attacker, attackerKey) = makeAddrAndKey("attacker");

        _deployEntryPoint();

        TSmartAccount7702 impl = new TSmartAccount7702();
        vm.etch(alice, address(impl).code);
        smartAccount = TSmartAccount7702(payable(alice));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(alice, 1000e6);
        vm.deal(alice, 10 ether);
    }

    // =======================================================================
    //  ATTACK 1: Unauthorized execute / deployDeterministic
    //
    //  A random address tries to call execution functions directly.
    //  Should revert with Unauthorized.
    // =======================================================================

    function test_attack_unauthorizedExecute_reverts() public {
        _setup();

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TSmartAccount7702.Unauthorized.selector, attacker));
        smartAccount.execute(attacker, 1 ether, "");
    }

    function test_attack_unauthorizedDeployDeterministic_reverts() public {
        _setup();

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TSmartAccount7702.Unauthorized.selector, attacker));
        smartAccount.deployDeterministic(0, hex"60006000", bytes32(0));
    }

    // =======================================================================
    //  ATTACK 2: ETH theft via execute
    //
    //  Attacker tries to drain ETH from Alice's EOA by calling execute.
    //  This must be blocked by onlyEntryPointOrSelf.
    // =======================================================================

    function test_attack_stealEther_reverts() public {
        _setup();

        uint256 aliceBalanceBefore = alice.balance;

        // Attacker cannot call execute directly
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TSmartAccount7702.Unauthorized.selector, attacker));
        smartAccount.execute(attacker, alice.balance, "");

        // Alice's balance unchanged
        assertEq(alice.balance, aliceBalanceBefore);
    }

    // =======================================================================
    //  ATTACK 3: ERC-20 token theft via execute
    //
    //  Attacker tries to drain USDC from Alice's EOA by calling execute
    //  with usdc.transfer() calldata.
    // =======================================================================

    function test_attack_stealTokens_reverts() public {
        _setup();

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        bytes memory transferCall = abi.encodeCall(IERC20.transfer, (attacker, aliceUsdcBefore));

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TSmartAccount7702.Unauthorized.selector, attacker));
        smartAccount.execute(address(usdc), 0, transferCall);

        // Alice's USDC unchanged
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore);
        assertEq(usdc.balanceOf(attacker), 0);
    }

    // =======================================================================
    //  ATTACK 4: UserOp with wrong signer
    //
    //  Attacker submits a UserOp signed with their own key instead of
    //  Alice's key. validateUserOp must return 1 (SIG_VALIDATION_FAILED).
    // =======================================================================

    function test_attack_wrongSignerUserOp_fails() public {
        _setup();

        bytes memory callData = abi.encodeCall(TSmartAccount7702.execute, (attacker, 1 ether, ""));

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: alice,
            nonce: entryPoint.getNonce(alice, 0),
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(1_000_000) << 128 | uint256(1_000_000)),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: ""
        });

        // Sign with attacker's key instead of Alice's
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);

        // EntryPoint rejects: signature doesn't match address(this)
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.prank(bundler, bundler);
        vm.expectRevert();
        entryPoint.handleOps(ops, payable(bundler));
    }

    // =======================================================================
    //  ATTACK 5: UserOp replay (same nonce)
    //
    //  Attacker captures a valid UserOp and tries to replay it.
    //  The EntryPoint's nonce system must reject the duplicate.
    // =======================================================================

    function test_attack_replayUserOp_reverts() public {
        _setup();

        bytes memory callData = abi.encodeCall(TSmartAccount7702.execute, (address(0x1234), 0, ""));

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: alice,
            nonce: entryPoint.getNonce(alice, 0),
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(1_000_000) << 128 | uint256(1_000_000)),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);

        // First submission succeeds
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.prank(bundler, bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // Replay with the exact same UserOp and nonce — must revert
        vm.prank(bundler, bundler);
        vm.expectRevert();
        entryPoint.handleOps(ops, payable(bundler));
    }

    // =======================================================================
    //  ATTACK 6: ERC-1271 cross-account signature replay
    //
    //  Attacker has a valid ERC-1271 signature from Alice's account and
    //  tries to use it on a different account (Bob's). ERC-7739 anti-replay
    //  must reject it because the domain separator includes address(this).
    // =======================================================================

    function test_attack_erc1271CrossAccountReplay_rejected() public {
        _setup();

        // Setup Bob's account
        address bob = makeAddr("bob");
        TSmartAccount7702 impl2 = new TSmartAccount7702();
        vm.etch(bob, address(impl2).code);
        TSmartAccount7702 bobAccount = TSmartAccount7702(payable(bob));

        bytes32 appHash = keccak256("authorize transfer");

        // Alice signs via PersonalSign ERC-7739 flow
        bytes32 personalSignTypehash = keccak256("PersonalSign(bytes prefixed)");
        bytes32 structHash = keccak256(abi.encode(personalSignTypehash, appHash));
        bytes32 domainSep = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("TSmart Account 7702"),
                keccak256("1"),
                block.chainid,
                alice // Alice's domain
            )
        );
        bytes32 toSign = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, toSign);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Valid on Alice's account
        assertEq(smartAccount.isValidSignature(appHash, signature), bytes4(0x1626ba7e));

        // REJECTED on Bob's account — different domain separator
        assertEq(bobAccount.isValidSignature(appHash, signature), bytes4(0xffffffff));
    }

    // =======================================================================
    //  ATTACK 7: validateUserOp from non-EntryPoint
    //
    //  Attacker tries to call validateUserOp directly. This is blocked
    //  by the onlyEntryPoint modifier.
    // =======================================================================

    function test_attack_validateUserOpFromNonEntryPoint_reverts() public {
        _setup();

        PackedUserOperation memory fakeOp;
        fakeOp.sender = alice;

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TSmartAccount7702.Unauthorized.selector, attacker));
        smartAccount.validateUserOp(fakeOp, bytes32(0), 0);
    }
}

/// @dev Runs attack tests against EntryPoint v0.9.
contract AttackTests is AttackTestsBase {
    function _deployEntryPoint() internal override {
        EntryPoint ep = new EntryPoint();
        vm.etch(address(entryPoint), address(ep).code);
    }
}
