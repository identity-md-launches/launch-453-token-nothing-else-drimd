// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev Only these actions are targeted. Expected reverts are consumed here, so
/// fail_on_revert catches unexpected reverts and failed handler assertions.
contract DrimHandler is Test {
    uint256 private constant SUPPLY = 100_000_000_000_000;
    address private constant TREASURY = 0x20a2Fb1bb9e6C1443C11703cCecB3685cd99b7C5;

    LaunchToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new LaunchToken();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCAFE), TREASURY];
        // Initialize from the specification, never by copying observed balances.
        expectedBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < 4; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / 5));
            _recordTransfer(address(this), actors[i], SUPPLY / 5);
        }
        // Some allowances predate the random sequence; later approvals can replace
        // or revoke them, and transferFrom never silently grants its own allowance.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % actors.length], type(uint256).max);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 gross = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, gross));
        _recordTransfer(from, to, gross);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 amount;
        if (amountSeed % 3 == 0) amount = type(uint256).max;
        else if (amountSeed % 3 == 1) amount = 0;
        else amount = bound(amountSeed, 0, SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _recipient(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 gross = _amount(amountSeed, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, gross));
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= gross;
        _recordTransfer(owner, to, gross);
    }

    function rejectOverdraw(uint256 ownerSeed, uint256 toSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address to = _recipient(toSeed);
        uint256 balance = expectedBalance[owner];
        uint256 gross = bound(amountSeed, balance + 1, type(uint256).max);
        address spender = _actor(toSeed);
        if (delegated) _approve(owner, spender, gross);

        vm.expectRevert(
            abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", owner, balance, gross)
        );
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, to, gross);
        else token.transfer(to, gross);
        // The unchanged ghost ledger also verifies fee and allowance rollback.
    }

    function rejectUnderapproved(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // An empty holder still must fail at authorization. A funded holder also
        // tests that having tokens cannot substitute for the missing permission.
        uint256 gross = bound(amountSeed, 1, expectedBalance[owner] + 1);
        uint256 allowed = gross - 1;
        _approve(owner, spender, allowed);
        address to = _recipient(toSeed);

        vm.expectRevert(
            abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", spender, allowed, gross)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, gross);
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 gross = _amount(amountSeed, expectedBalance[owner]);
        if (delegated) _approve(owner, spender, gross);
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), gross);
        else token.transfer(address(0), gross);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidSpender(address)", address(0)));
        vm.prank(_actor(ownerSeed));
        token.approve(address(0), amount);
    }

    function forbiddenAdminCall(uint256 callerSeed, uint256 operationSeed) external {
        address caller = _actor(callerSeed);
        bytes memory data;
        uint256 operation = operationSeed % 6;
        if (operation == 0) data = abi.encodeWithSignature("mint(address,uint256)", caller, SUPPLY);
        else if (operation == 1) data = abi.encodeWithSignature("pause()");
        else if (operation == 2) data = abi.encodeWithSignature("burn(uint256)", uint256(1));
        else if (operation == 3) data = abi.encodeWithSignature("setFee(uint256)", uint256(0));
        else if (operation == 4) data = abi.encodeWithSignature("setFeeRecipient(address)", caller);
        else data = abi.encodeWithSignature("upgradeTo(address)", caller);

        vm.prank(caller);
        (bool success,) = address(token).call(data);
        assertFalse(success, "unexpected administrative entry point");

        // Exercise transfer liveness immediately after the attempted admin call.
        uint256 gross = expectedBalance[caller] < 20 ? expectedBalance[caller] : 20;
        vm.prank(caller);
        assertTrue(token.transfer(caller, gross));
        _recordTransfer(caller, caller, gross);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _recordTransfer(address from, address to, uint256 gross) private {
        // Independent specification ledger: 5% of each gross transfer, rounded
        // down to minor units. Sequential deltas naturally combine all aliases.
        uint256 fee = gross * 5 / 100;
        expectedBalance[from] -= gross;
        expectedBalance[to] += gross - fee;
        expectedBalance[TREASURY] += fee;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _recipient(uint256 seed) private view returns (address) {
        // Tokens may be sent to the token contract, but it cannot originate
        // transactions. Track it as a destination, never impersonate it.
        return seed % 6 == 5 ? address(token) : _actor(seed % 6);
    }

    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        uint256 edge = seed % 8;
        uint256 amount;
        if (edge == 0) amount = 0;
        else if (edge == 1) amount = 1;
        else if (edge == 2) amount = 19;
        else if (edge == 3) amount = 20;
        else if (edge == 4) amount = 21;
        else if (edge == 5) return limit;
        else return bound(seed, 0, limit);
        return amount < limit ? amount : limit;
    }
}

/// @notice Stateful properties of the task's fixed-supply, 5% fee token.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 100_000_000_000_000;
    DrimHandler private handler;
    LaunchToken private token;

    function setUp() public {
        handler = new DrimHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = DrimHandler.transfer.selector;
        selectors[1] = DrimHandler.approve.selector;
        selectors[2] = DrimHandler.transferFrom.selector;
        selectors[3] = DrimHandler.rejectOverdraw.selector;
        selectors[4] = DrimHandler.rejectUnderapproved.selector;
        selectors[5] = DrimHandler.rejectZeroReceiver.selector;
        selectors[6] = DrimHandler.rejectZeroSpender.selector;
        selectors[7] = DrimHandler.forbiddenAdminCall.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyEqualsAllBalances() public view {
        uint256 total = token.balanceOf(address(token));
        for (uint256 i; i < 5; ++i) {
            total += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY, "post-launch supply changed");
        assertEq(total, SUPPLY, "tokens created, destroyed, or sent outside the ledger");
        assertEq(token.balanceOf(address(0)), 0, "zero address acquired tokens");
    }

    function invariant_balancesFollowFivePercentFeeLedger() public view {
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder/treasury accounting mismatch");
        }
        assertEq(token.balanceOf(address(token)), handler.expectedBalance(address(token)), "token custody mismatch");
    }

    function invariant_allowancesFollowApprovalsAndGrossSpending() public view {
        for (uint256 i; i < 5; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0, "zero spender gained approval");
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "allowance mismatch"
                );
            }
        }
    }
}
