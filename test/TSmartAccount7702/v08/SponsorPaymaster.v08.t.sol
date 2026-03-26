// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SponsorPaymaster} from "../../../buidl-wallet-contracts/src/paymaster/v1/permissioned/SponsorPaymaster.sol";
import {TSmartAccount7702} from "../../../src/TSmartAccount7702.sol";
import {SmartWalletTestBase} from "../SmartWalletTestBase.sol";
import {UseEntryPointV08} from "../entrypoint/UseEntryPointV08.sol";
import {MockTarget} from "../../mocks/MockTarget.sol";

/// @dev Validates that a UserOp sponsored by buidl-wallet-contracts SponsorPaymaster
///      executes through EntryPoint v0.8 and charges gas to the paymaster deposit.
contract TestSponsorPaymasterV08 is SmartWalletTestBase, UseEntryPointV08 {
    using MessageHashUtils for bytes32;

    uint128 internal constant VERIFICATION_GAS_LIMIT = 500_000;
    uint128 internal constant CALL_GAS_LIMIT = 500_000;
    uint128 internal constant PAYMASTER_VERIFICATION_GAS_LIMIT = 120_000;
    uint128 internal constant PAYMASTER_POST_OP_GAS_LIMIT = 60_000;

    SponsorPaymaster internal sponsorPaymaster;
    MockTarget internal target;

    uint256 internal paymasterSignerPrivateKey;
    address internal paymasterSigner;
    address internal paymasterOwner;

    function setUp() public override {
        super.setUp();

        target = new MockTarget();
        (paymasterSigner, paymasterSignerPrivateKey) = makeAddrAndKey("paymasterSigner");
        paymasterOwner = makeAddr("paymasterOwner");

        vm.deal(paymasterOwner, 20 ether);

        sponsorPaymaster = _deploySponsorPaymaster();

        vm.startPrank(paymasterOwner);
        sponsorPaymaster.deposit{value: 10 ether}();
        sponsorPaymaster.addStake{value: 1 ether}(1);
        vm.stopPrank();
    }

    function test_handleOps_v08_sponsoredByBuidlSponsorPaymaster() public {
        bytes memory payload = abi.encodePacked("sponsored-v08-op");
        PackedUserOperation memory op = _buildSponsoredUserOp(payload);

        uint256 paymasterDepositBefore = sponsorPaymaster.getDeposit();
        uint256 accountBalanceBefore = address(account).balance;

        _sendUserOperation(op);

        assertEq(target.datahash(), keccak256(payload), "target call should execute");
        assertLt(sponsorPaymaster.getDeposit(), paymasterDepositBefore, "paymaster deposit should be charged");
        assertEq(address(account).balance, accountBalanceBefore, "account should not pay gas in sponsored mode");
    }

    function _buildSponsoredUserOp(bytes memory payload) internal view returns (PackedUserOperation memory op) {
        bytes memory callData =
            abi.encodeCall(TSmartAccount7702.execute, (address(target), 0, abi.encodeCall(target.setData, (payload))));
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        uint48 validAfter = uint48(block.timestamp - 1);

        op = PackedUserOperation({
            sender: address(account),
            nonce: entryPoint.getNonce(address(account), 0),
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(VERIFICATION_GAS_LIMIT) << 128 | uint256(CALL_GAS_LIMIT)),
            preVerificationGas: 50_000,
            gasFees: bytes32(uint256(uint128(1 gwei)) << 128 | uint256(uint128(30 gwei))),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 paymasterHash = _sponsorGetHash(
            op, PAYMASTER_VERIFICATION_GAS_LIMIT, PAYMASTER_POST_OP_GAS_LIMIT, validUntil, validAfter
        );
        (uint8 pv, bytes32 pr, bytes32 ps) = vm.sign(paymasterSignerPrivateKey, paymasterHash.toEthSignedMessageHash());
        op.paymasterAndData = abi.encodePacked(
            address(sponsorPaymaster),
            PAYMASTER_VERIFICATION_GAS_LIMIT,
            PAYMASTER_POST_OP_GAS_LIMIT,
            abi.encode(validUntil, validAfter),
            abi.encodePacked(pr, ps, pv)
        );
        op.signature = _sign(op);
    }

    function _deploySponsorPaymaster() internal returns (SponsorPaymaster) {
        SponsorPaymaster impl = new SponsorPaymaster(IEntryPoint(address(entryPoint)));
        address[] memory signers = new address[](1);
        signers[0] = paymasterSigner;
        bytes memory initData = abi.encodeCall(SponsorPaymaster.initialize, (paymasterOwner, signers));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        return SponsorPaymaster(payable(address(proxy)));
    }

    function _sponsorGetHash(
        PackedUserOperation memory op,
        uint128 paymasterVerificationGasLimit,
        uint128 paymasterPostOpGasLimit,
        uint48 validUntil,
        uint48 validAfter
    ) internal view returns (bytes32) {
        (bool ok, bytes memory ret) = address(sponsorPaymaster).staticcall(
            abi.encodeWithSignature(
                "getHash((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes),uint128,uint128,uint48,uint48)",
                op,
                paymasterVerificationGasLimit,
                paymasterPostOpGasLimit,
                validUntil,
                validAfter
            )
        );
        require(ok, "SponsorPaymaster.getHash failed");
        return abi.decode(ret, (bytes32));
    }
}
