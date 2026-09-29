// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @notice Repeated authorization changes and adversarial inputs around the token's public entry points.
/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 10_000_000 * 10 ** 7;
    address private constant TREASURY = 0x20a2Fb1bb9e6C1443C11703cCecB3685cd99b7C5;
    address private constant RECIPIENT = address(0xA11CE);
    address private constant SPENDER = address(0xB0B);
    address private constant OTHER_SPENDER = address(0xCAFE);

    LaunchToken private token;

    function setUp() public {
        token = new LaunchToken();
    }

    function testFuzzSpentAllowanceCannotBeReused(uint256 allowance, uint256 firstGross) public {
        allowance = bound(allowance, 1, SUPPLY / 2);
        firstGross = bound(firstGross, 0, allowance);
        uint256 secondGross = allowance - firstGross;
        token.approve(SPENDER, allowance);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), RECIPIENT, firstGross));
        assertEq(token.allowance(address(this), SPENDER), secondGross);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), RECIPIENT, secondGross));
        assertEq(token.allowance(address(this), SPENDER), 0);

        // The owner still has funds, so a third call must fail specifically on authorization.
        vm.expectRevert(_insufficientAllowance(SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), RECIPIENT, 1);
        uint256 fee = firstGross * 5 / 100 + secondGross * 5 / 100;
        assertEq(token.balanceOf(address(this)), SUPPLY - allowance);
        assertEq(token.balanceOf(RECIPIENT), allowance - fee);
        assertEq(token.balanceOf(TREASURY), fee);

        // Explicit renewed authorization permits exactly one more smallest unit.
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), RECIPIENT, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - allowance - 1);
        assertEq(token.balanceOf(RECIPIENT), allowance - fee + 1);
        assertEq(token.balanceOf(TREASURY), fee);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzAllowanceReplacementAndRevocationAreIsolated(uint256 original, uint256 replacement, uint256 spent)
        public
    {
        original = bound(original, 1, SUPPLY / 4);
        replacement = bound(replacement, 0, SUPPLY / 4);
        spent = bound(spent, 0, original);
        token.approve(SPENDER, original);
        token.approve(OTHER_SPENDER, 1);
        vm.prank(SPENDER);
        token.transferFrom(address(this), RECIPIENT, spent);

        token.approve(SPENDER, replacement);
        assertEq(token.allowance(address(this), SPENDER), replacement);
        vm.expectRevert(_insufficientAllowance(SPENDER, replacement, replacement + 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), RECIPIENT, replacement + 1);
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.allowance(address(this), OTHER_SPENDER), 1);

        token.approve(SPENDER, 0);
        vm.expectRevert(_insufficientAllowance(SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), RECIPIENT, 1);
        vm.prank(OTHER_SPENDER);
        assertTrue(token.transferFrom(address(this), RECIPIENT, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.allowance(address(this), OTHER_SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent - 1);
        assertEq(token.balanceOf(RECIPIENT), spent - spent * 5 / 100 + 1);
        assertEq(token.balanceOf(TREASURY), spent * 5 / 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzDirectAndDelegatedTransfersAgreeForOverlappingAddresses(
        address owner,
        address recipient,
        address spender,
        uint256 gross,
        uint8 aliases
    ) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        gross = bound(gross, 0, SUPPLY);
        // Exercise equality cases deliberately; independent random addresses rarely coincide.
        if ((aliases & 1) != 0) owner = TREASURY;
        uint8 recipientMode = (aliases >> 1) % 3;
        if (recipientMode == 1) recipient = owner;
        if (recipientMode == 2) recipient = TREASURY;
        uint8 spenderMode = (aliases >> 3) % 4;
        if (spenderMode == 1) spender = owner;
        if (spenderMode == 2) spender = recipient;
        if (spenderMode == 3) spender = TREASURY;

        vm.prank(owner);
        LaunchToken direct = new LaunchToken();
        vm.prank(owner);
        LaunchToken delegated = new LaunchToken();
        vm.prank(owner);
        assertTrue(direct.transfer(recipient, gross));
        vm.prank(owner);
        assertTrue(delegated.approve(spender, gross));
        vm.prank(spender);
        assertTrue(delegated.transferFrom(owner, recipient, gross));

        assertEq(delegated.allowance(owner, spender), 0);
        assertEq(delegated.balanceOf(owner), direct.balanceOf(owner));
        assertEq(delegated.balanceOf(recipient), direct.balanceOf(recipient));
        assertEq(delegated.balanceOf(spender), direct.balanceOf(spender));
        assertEq(delegated.balanceOf(TREASURY), direct.balanceOf(TREASURY));
        assertEq(direct.totalSupply(), SUPPLY);
        assertEq(delegated.totalSupply(), SUPPLY);

        // Count each potentially overlapping holder only once.
        uint256 accounted = delegated.balanceOf(owner);
        if (recipient != owner) accounted += delegated.balanceOf(recipient);
        if (TREASURY != owner && TREASURY != recipient) accounted += delegated.balanceOf(TREASURY);
        assertEq(accounted, SUPPLY);
    }

    function testMaximumDelegatedAmountRevertsWithoutChangingInfiniteAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientBalance(address,uint256,uint256)", address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), RECIPIENT, type(uint256).max);

        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(RECIPIENT), 0);
        assertEq(token.balanceOf(TREASURY), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testValueAttachedToValidCallsRevertsWithoutChangingTokenState() public {
        token.approve(address(this), 100);
        vm.deal(address(this), 3);
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(token.transfer, (RECIPIENT, 100));
        calls[1] = abi.encodeCall(token.approve, (SPENDER, 100));
        calls[2] = abi.encodeCall(token.transferFrom, (address(this), RECIPIENT, 100));

        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success, "token accepted ETH with a nonpayable token operation");
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(RECIPIENT), 0);
            assertEq(token.balanceOf(TREASURY), 0);
            assertEq(token.allowance(address(this), address(this)), 100);
            assertEq(token.allowance(address(this), SPENDER), 0);
        }

        assertEq(address(token).balance, 0);
        assertEq(address(this).balance, 3);
        // The calldata was otherwise valid: without value all three calls succeed.
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call(calls[i]);
            assertTrue(success);
        }
        assertEq(token.balanceOf(RECIPIENT), 190);
        assertEq(token.balanceOf(TREASURY), 10);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function _insufficientAllowance(address spender, uint256 available, uint256 required)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)", spender, available, required
        );
    }
}
