// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    uint256 private constant UNIT = 10 ** 7;
    uint256 private constant SUPPLY = 10_000_000 * UNIT;
    address private constant TREASURY = 0x20a2Fb1bb9e6C1443C11703cCecB3685cd99b7C5;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0xCAFE);

    LaunchToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new LaunchToken();
    }

    function testMetadataAndFixedSupply() public view {
        assertEq(token.name(), "drIMD");
        assertEq(token.symbol(), "DRIM");
        assertEq(token.decimals(), 7);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(TREASURY), 0);
        assertEq(token.FEE_RECIPIENT(), TREASURY);
        assertEq(token.FEE_BPS(), 500);
    }

    function testConstructorMintsWholeSupplyToItsImmediateDeployer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        LaunchToken another = new LaunchToken();

        assertEq(another.balanceOf(ALICE), SUPPLY);
        assertEq(another.balanceOf(address(this)), 0);
        assertEq(another.balanceOf(TREASURY), 0);
        assertEq(another.totalSupply(), SUPPLY);
    }

    function testTransferDeductsGrossAndEmitsFeeThenNet() public {
        uint256 gross = 100 * UNIT;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), TREASURY, 5 * UNIT);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 95 * UNIT);

        assertTrue(token.transfer(ALICE, gross));
        assertEq(token.balanceOf(address(this)), SUPPLY - gross);
        assertEq(token.balanceOf(ALICE), 95 * UNIT);
        assertEq(token.balanceOf(TREASURY), 5 * UNIT);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testEntireSupplyCanBeTransferred() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 9_500_000 * UNIT);
        assertEq(token.balanceOf(TREASURY), 500_000 * UNIT);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountSucceedsAndEmitsOneEvent() public {
        vm.recordLogs();
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(ALICE))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(BOB))));
        assertEq(abi.decode(logs[0].data, (uint256)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(TREASURY), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFeeRoundingAtSmallestUnitBoundaries() public {
        assertTrue(token.transfer(ALICE, 19));
        assertEq(token.balanceOf(ALICE), 19);
        assertEq(token.balanceOf(TREASURY), 0);

        assertTrue(token.transfer(ALICE, 20));
        assertEq(token.balanceOf(ALICE), 38);
        assertEq(token.balanceOf(TREASURY), 1);

        assertTrue(token.transfer(ALICE, 39));
        assertEq(token.balanceOf(ALICE), 76);
        assertEq(token.balanceOf(TREASURY), 2);

        assertTrue(token.transfer(ALICE, 40));
        assertEq(token.balanceOf(ALICE), 114);
        assertEq(token.balanceOf(TREASURY), 4);
        assertEq(token.balanceOf(address(this)), SUPPLY - 118);
    }

    function testSelfTransferChargesFee() public {
        assertTrue(token.transfer(address(this), 100 * UNIT));
        assertEq(token.balanceOf(address(this)), SUPPLY - 5 * UNIT);
        assertEq(token.balanceOf(TREASURY), 5 * UNIT);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferToTreasuryCreditsBothLegs() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), TREASURY, 5 * UNIT);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), TREASURY, 95 * UNIT);
        assertTrue(token.transfer(TREASURY, 100 * UNIT));

        assertEq(token.balanceOf(TREASURY), 100 * UNIT);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 * UNIT);
    }

    function testTreasuryTransferRetainsItsOwnFee() public {
        token.transfer(TREASURY, 100 * UNIT);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(TREASURY, TREASURY, 5 * UNIT);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(TREASURY, ALICE, 95 * UNIT);
        vm.prank(TREASURY);
        assertTrue(token.transfer(ALICE, 100 * UNIT));

        assertEq(token.balanceOf(TREASURY), 5 * UNIT);
        assertEq(token.balanceOf(ALICE), 95 * UNIT);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTreasurySelfTransferPreservesItsBalance() public {
        token.transfer(TREASURY, 100 * UNIT);
        vm.prank(TREASURY);
        assertTrue(token.transfer(TREASURY, 100 * UNIT));
        assertEq(token.balanceOf(TREASURY), 100 * UNIT);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferRequiresFullGrossBalance() public {
        vm.expectRevert(_insufficientBalance(address(this), SUPPLY, SUPPLY + 1));
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(TREASURY), 0);
    }

    function testTreasuryTransferRequiresFullGrossBalance() public {
        token.transfer(TREASURY, 1000);
        // The net is only 998, but the treasury must still hold the requested gross 1050.
        vm.expectRevert(_insufficientBalance(TREASURY, 1000, 1050));
        vm.prank(TREASURY);
        token.transfer(ALICE, 1050);
        assertEq(token.balanceOf(TREASURY), 1000);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTreasurySelfTransferRequiresFullGrossBalance() public {
        token.transfer(TREASURY, 1000);
        vm.expectRevert(_insufficientBalance(TREASURY, 1000, 1001));
        vm.prank(TREASURY);
        token.transfer(TREASURY, 1001);
        assertEq(token.balanceOf(TREASURY), 1000);
    }

    function testApproveEmitsAndCanReplaceOrRevokeAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 40));
        assertEq(token.allowance(address(this), SPENDER), 40);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(TREASURY), 0);

        vm.expectRevert(_insufficientAllowance(SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function testTransferFromConsumesGrossAllowanceAndChargesSameFee() public {
        token.approve(SPENDER, 110 * UNIT);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), TREASURY, 5 * UNIT);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 95 * UNIT);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 100 * UNIT));

        assertEq(token.allowance(address(this), SPENDER), 10 * UNIT);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 * UNIT);
        assertEq(token.balanceOf(ALICE), 95 * UNIT);
        assertEq(token.balanceOf(TREASURY), 5 * UNIT);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function testMaximumAllowanceRemainsUnchangedAcrossTransfers() public {
        token.approve(SPENDER, type(uint256).max);
        vm.startPrank(SPENDER);
        token.transferFrom(address(this), ALICE, 100 * UNIT);
        token.transferFrom(address(this), BOB, 100 * UNIT);
        vm.stopPrank();

        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 95 * UNIT);
        assertEq(token.balanceOf(BOB), 95 * UNIT);
        assertEq(token.balanceOf(TREASURY), 10 * UNIT);
    }

    function testDelegatedSelfTransferConsumesGrossAllowance() public {
        token.approve(SPENDER, 100 * UNIT);
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), 100 * UNIT);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5 * UNIT);
        assertEq(token.balanceOf(TREASURY), 5 * UNIT);
    }

    function testDelegatedTreasuryTransferConsumesGrossAllowance() public {
        token.transfer(TREASURY, 100 * UNIT);
        vm.prank(TREASURY);
        token.approve(SPENDER, 100 * UNIT);
        vm.prank(SPENDER);
        token.transferFrom(TREASURY, ALICE, 100 * UNIT);
        assertEq(token.allowance(TREASURY, SPENDER), 0);
        assertEq(token.balanceOf(TREASURY), 5 * UNIT);
        assertEq(token.balanceOf(ALICE), 95 * UNIT);
    }

    function testZeroTransferFromRequiresNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(TREASURY), 0);
    }

    function testTransferFromRejectsMissingAllowance() public {
        vm.expectRevert(_insufficientAllowance(SPENDER, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(TREASURY), 0);
    }

    function testTransferFromRequiresGrossAllowanceRatherThanNet() public {
        token.approve(SPENDER, 95);
        vm.expectRevert(_insufficientAllowance(SPENDER, 95, 100));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 100);
        assertEq(token.allowance(address(this), SPENDER), 95);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(TREASURY), 0);
    }

    function testTransferFromDoesNotBypassAllowanceWhenCallerIsOwner() public {
        vm.expectRevert(_insufficientAllowance(address(this), 0, 100));
        token.transferFrom(address(this), ALICE, 100);
    }

    function testTransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        token.transfer(address(0), 100);
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(TREASURY), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromToZeroRollsBackAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(TREASURY), 0);
    }

    function testTransferFromZeroSenderReverts() public {
        // OpenZeppelin validates the allowance owner before reaching the transfer itself.
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidApprover(address)", address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
    }

    function testTransferByZeroSenderReverts() public {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidSender(address)", address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidSpender(address)", address(0)));
        token.approve(address(0), 100);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testApproveFromZeroReverts() public {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidApprover(address)", address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 100);
    }

    function testMaximumTransferAmountRevertsWithoutArithmeticPanic() public {
        vm.expectRevert(_insufficientBalance(address(this), SUPPLY, type(uint256).max));
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(TREASURY), 0);
    }

    function testNoMintPauseBurnFeeAdminOrUpgradeEntryPoints() public {
        bytes[] memory calls = new bytes[](17);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", ALICE, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("pause()");
        calls[4] = abi.encodeWithSignature("unpause()");
        calls[5] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[6] = abi.encodeWithSignature("burnFrom(address,uint256)", address(this), 1);
        calls[7] = abi.encodeWithSignature("setFee(uint256)", 0);
        calls[8] = abi.encodeWithSignature("setFeeRecipient(address)", ALICE);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", ALICE);
        calls[10] = abi.encodeWithSignature("setMinter(address)", ALICE);
        calls[11] = abi.encodeWithSignature("initialize(address)", ALICE);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", ALICE);
        calls[13] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", ALICE, bytes(""));
        calls[14] = abi.encodeWithSignature("setFeeBps(uint256)", 0);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[16] = abi.encodeWithSignature("setFeeExempt(address,bool)", ALICE, true);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess, "deployer reached an unwanted entry point");
            vm.prank(ALICE);
            (bool holderSuccess,) = address(token).call(calls[i]);
            assertFalse(holderSuccess, "public caller reached an unwanted entry point");
        }

        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertTrue(token.transfer(ALICE, 100));
        assertEq(token.balanceOf(ALICE), 95);
        assertEq(token.balanceOf(TREASURY), 5);
    }

    function testRejectsEther() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
    }

    function testFuzzTransferRoundsFeeDownAndConservesSupply(uint256 gross) public {
        gross = bound(gross, 0, SUPPLY);
        uint256 fee = gross * 5 / 100;
        assertTrue(token.transfer(ALICE, gross));
        assertEq(token.balanceOf(address(this)), SUPPLY - gross);
        assertEq(token.balanceOf(ALICE), gross - fee);
        assertEq(token.balanceOf(TREASURY), fee);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInsufficientBalanceRollsBackDelegatedAllowance(uint256 funding, uint256 gross) public {
        funding = bound(funding, 0, SUPPLY);
        token.transfer(ALICE, funding);
        uint256 balance = token.balanceOf(ALICE);
        uint256 treasuryBefore = token.balanceOf(TREASURY);
        gross = bound(gross, balance + 1, type(uint256).max);

        vm.prank(ALICE);
        token.approve(SPENDER, gross);
        vm.expectRevert(_insufficientBalance(ALICE, balance, gross));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, gross);

        assertEq(token.allowance(ALICE, SPENDER), gross);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(TREASURY), treasuryBefore);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzMixedTransfersMatchConservationModel(uint256 seed, uint8 requestedSteps) public {
        address[5] memory actors = [address(this), ALICE, BOB, TREASURY, address(0xD00D)];
        uint256[5] memory balances;
        balances[0] = SUPPLY;
        uint256 steps = bound(requestedSteps, 1, 32);

        for (uint256 i; i < steps; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 from = entropy % actors.length;
            uint256 to = (entropy >> 32) % actors.length;
            uint256 gross = (entropy >> 64) % (balances[from] + 1);
            uint256 fee = gross * 5 / 100;

            if ((entropy & (1 << 255)) == 0) {
                vm.prank(actors[from]);
                assertTrue(token.transfer(actors[to], gross));
            } else {
                vm.prank(actors[from]);
                token.approve(SPENDER, gross);
                vm.prank(SPENDER);
                assertTrue(token.transferFrom(actors[from], actors[to], gross));
                assertEq(token.allowance(actors[from], SPENDER), 0);
            }

            balances[from] -= gross;
            balances[to] += gross - fee;
            balances[3] += fee;
            uint256 accounted;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.balanceOf(actors[j]), balances[j]);
                accounted += balances[j];
            }
            assertEq(accounted, SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function _insufficientBalance(address sender, uint256 balance, uint256 required)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", sender, balance, required);
    }

    function _insufficientAllowance(address spender, uint256 allowance, uint256 required)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)", spender, allowance, required
        );
    }
}
