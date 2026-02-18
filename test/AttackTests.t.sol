// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SmartAccount7702} from "../src/SmartAccount7702.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

/// @dev Malicious "EntryPoint" that an attacker deploys.
///      Once set as the account's EntryPoint via front-running initialize(),
///      the attacker can call execute() on the victim's wallet because
///      onlyEntryPointOrSelf checks msg.sender == entryPoint().
contract MaliciousEntryPoint {
    function drainEth(SmartAccount7702 victim, address attacker) external {
        victim.execute(attacker, address(victim).balance, "");
    }

    function drainERC20(SmartAccount7702 victim, address token, address attacker) external {
        uint256 balance = MockERC20(token).balanceOf(address(victim));
        victim.execute(
            token,
            0,
            abi.encodeCall(IERC20.transfer, (attacker, balance))
        );
    }
}

/// @title AttackTests
///
/// @notice Adversarial tests against SmartAccount7702. Every test simulates an attack
///         and PASSES if the attack is correctly prevented.
///
/// @dev Attack vectors tested:
///
///      1. Front-running initialize() with a malicious EntryPoint
///      2. Direct unauthorized execute() / deployDeterministic()
///      3. ETH theft via execute()
///      4. ERC-20 theft via execute()
///      5. Re-initialization (changing EntryPoint after setup)
///      6. UserOp with wrong signer
///      7. UserOp replay (same nonce)
///      8. ERC-1271 cross-account signature replay
///      9. Uninitialized account exploitation
///     10. validateUserOp from non-EntryPoint
///     11. initialize() via callback from an external contract
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
    SmartAccount7702 smartAccount;
    MockERC20 usdc;

    // -----------------------------------------------------------------------
    // Setup helpers
    // -----------------------------------------------------------------------

    /// @dev Override to deploy the EntryPoint bytecode at the canonical address.
    function _deployEntryPoint() internal virtual;

    /// @dev Deploys infrastructure and simulates EIP-7702 delegation WITHOUT initializing.
    function _setupUninitialized() internal {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (attacker, attackerKey) = makeAddrAndKey("attacker");

        _deployEntryPoint();

        SmartAccount7702 impl = new SmartAccount7702();
        vm.etch(alice, address(impl).code);
        smartAccount = SmartAccount7702(payable(alice));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(alice, 1000e6);
        vm.deal(alice, 10 ether);
    }

    /// @dev Full setup: deploy, delegate, AND initialize (Alice calls initialize on herself).
    function _setupInitialized() internal {
        _setupUninitialized();
        vm.prank(alice);
        smartAccount.initialize(address(entryPoint));
    }

    // =======================================================================
    //  ATTACK 1: Front-running initialize()
    //
    //  Scenario: After EIP-7702 delegation, an attacker calls initialize()
    //  before Alice, setting a malicious contract as the EntryPoint.
    //  The malicious "EntryPoint" can then call execute() to drain funds.
    //
    //  This was a CRITICAL VULNERABILITY. Fixed by requiring
    //  msg.sender == address(this) in initialize().
    // =======================================================================

    function test_attack_frontRunInitialize_reverts() public {
        _setupUninitialized();

        MaliciousEntryPoint malicious = new MaliciousEntryPoint();

        // Attacker tries to front-run initialize() with their malicious contract
        vm.prank(attacker);
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        smartAccount.initialize(address(malicious));

        // Alice's account is still uninitialized — entryPoint is address(0)
        assertEq(smartAccount.entryPoint(), address(0));
    }

    // =======================================================================
    //  ATTACK 2: Unauthorized execute / deployDeterministic
    //
    //  A random address tries to call execution functions directly.
    //  Should revert with Unauthorized.
    // =======================================================================

    function test_attack_unauthorizedExecute_reverts() public {
        _setupInitialized();

        vm.prank(attacker);
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        smartAccount.execute(attacker, 1 ether, "");
    }

    function test_attack_unauthorizedDeployDeterministic_reverts() public {
        _setupInitialized();

        vm.prank(attacker);
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        smartAccount.deployDeterministic(0, hex"60006000", bytes32(0));
    }

    // =======================================================================
    //  ATTACK 3: ETH theft via execute
    //
    //  Attacker tries to drain ETH from Alice's EOA by calling execute.
    //  This must be blocked by onlyEntryPointOrSelf.
    // =======================================================================

    function test_attack_stealEther_reverts() public {
        _setupInitialized();

        uint256 aliceBalanceBefore = alice.balance;

        // Attacker cannot call execute directly
        vm.prank(attacker);
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        smartAccount.execute(attacker, alice.balance, "");

        // Alice's balance unchanged
        assertEq(alice.balance, aliceBalanceBefore);
    }

    // =======================================================================
    //  ATTACK 4: ERC-20 token theft via execute
    //
    //  Attacker tries to drain USDC from Alice's EOA by calling execute
    //  with usdc.transfer() calldata.
    // =======================================================================

    function test_attack_stealTokens_reverts() public {
        _setupInitialized();

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        bytes memory transferCall = abi.encodeCall(IERC20.transfer, (attacker, aliceUsdcBefore));

        vm.prank(attacker);
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        smartAccount.execute(address(usdc), 0, transferCall);

        // Alice's USDC unchanged
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore);
        assertEq(usdc.balanceOf(attacker), 0);
    }

    // =======================================================================
    //  ATTACK 5: Re-initialization (change EntryPoint after setup)
    //
    //  Attacker tries to call initialize() again to change the EntryPoint
    //  to their malicious contract. Blocked by OpenZeppelin Initializable.
    // =======================================================================

    function test_attack_reinitialize_reverts() public {
        _setupInitialized();

        MaliciousEntryPoint malicious = new MaliciousEntryPoint();

        // Even the EOA itself cannot re-initialize
        vm.prank(alice);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        smartAccount.initialize(address(malicious));

        // EntryPoint unchanged
        assertEq(smartAccount.entryPoint(), address(entryPoint));
    }

    // =======================================================================
    //  ATTACK 6: UserOp with wrong signer
    //
    //  Attacker submits a UserOp signed with their own key instead of
    //  Alice's key. validateUserOp must return 1 (SIG_VALIDATION_FAILED).
    // =======================================================================

    function test_attack_wrongSignerUserOp_fails() public {
        _setupInitialized();

        bytes memory callData = abi.encodeCall(
            SmartAccount7702.execute,
            (attacker, 1 ether, "")
        );

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
    //  ATTACK 7: UserOp replay (same nonce)
    //
    //  Attacker captures a valid UserOp and tries to replay it.
    //  The EntryPoint's nonce system must reject the duplicate.
    // =======================================================================

    function test_attack_replayUserOp_reverts() public {
        _setupInitialized();

        bytes memory callData = abi.encodeCall(
            SmartAccount7702.execute,
            (address(0x1234), 0, "")
        );

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
    //  ATTACK 8: ERC-1271 cross-account signature replay
    //
    //  Attacker has a valid ERC-1271 signature from Alice's account and
    //  tries to use it on a different account (Bob's). ERC-7739 anti-replay
    //  must reject it because the domain separator includes address(this).
    // =======================================================================

    function test_attack_erc1271CrossAccountReplay_rejected() public {
        _setupInitialized();

        // Setup Bob's account
        address bob = makeAddr("bob");
        SmartAccount7702 impl2 = new SmartAccount7702();
        vm.etch(bob, address(impl2).code);
        SmartAccount7702 bobAccount = SmartAccount7702(payable(bob));
        vm.prank(bob);
        bobAccount.initialize(address(entryPoint));

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
    //  ATTACK 9: Uninitialized account exploitation
    //
    //  Before initialize() is called, entryPoint() returns address(0).
    //  Nobody can send from address(0), so onlyEntryPoint and
    //  onlyEntryPointOrSelf effectively block all calls except self-calls.
    //  The account is inert — not exploitable, just non-functional.
    // =======================================================================

    function test_attack_uninitializedAccount_isInert() public {
        _setupUninitialized();

        // Verify entryPoint is address(0)
        assertEq(smartAccount.entryPoint(), address(0));

        // Attacker cannot call execute
        vm.prank(attacker);
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        smartAccount.execute(attacker, 1 ether, "");

        // Even a contract at address(0) can't call (impossible in EVM)
        // The only entity that can call is address(this) = alice
        // This is safe: Alice can still recover by calling initialize on herself

        // Alice CAN call execute on herself (msg.sender == address(this))
        vm.prank(alice);
        smartAccount.execute(address(0x1234), 0, "");
    }

    // =======================================================================
    //  ATTACK 10: validateUserOp from non-EntryPoint
    //
    //  Attacker tries to call validateUserOp directly. This is blocked
    //  by the onlyEntryPoint modifier.
    // =======================================================================

    function test_attack_validateUserOpFromNonEntryPoint_reverts() public {
        _setupInitialized();

        PackedUserOperation memory fakeOp;
        fakeOp.sender = alice;

        vm.prank(attacker);
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        smartAccount.validateUserOp(fakeOp, bytes32(0), 0);
    }

    // =======================================================================
    //  ATTACK 11: Attacker tries to call initialize from a contract
    //             pretending to be the EOA via a callback
    //
    //  Even if a contract calls the wallet during execution, it cannot
    //  call initialize() because msg.sender would be the contract, not
    //  address(this).
    // =======================================================================

    function test_attack_initializeViaCallback_reverts() public {
        _setupUninitialized();

        // Deploy a contract that will try to call initialize via a callback
        InitializeAttacker attackContract = new InitializeAttacker();

        // The attack contract calls smartAccount.initialize(itself)
        // msg.sender = attackContract address, which != address(this) = alice
        vm.expectRevert(SmartAccount7702.Unauthorized.selector);
        attackContract.attack(smartAccount);

        // Alice's account still uninitialized
        assertEq(smartAccount.entryPoint(), address(0));
    }
}

/// @dev Runs attack tests against EntryPoint v0.9.
contract AttackTests is AttackTestsBase {
    function _deployEntryPoint() internal override {
        EntryPoint ep = new EntryPoint();
        vm.etch(address(entryPoint), address(ep).code);
    }
}

/// @dev Helper contract that tries to call initialize() on the victim wallet.
contract InitializeAttacker {
    function attack(SmartAccount7702 victim) external {
        victim.initialize(address(this));
    }
}
