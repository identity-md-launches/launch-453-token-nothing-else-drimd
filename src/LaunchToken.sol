// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title drIMD (DRIM)
/// @notice Fixed supply with an immutable 5% fee deducted from every transfer's gross amount.
contract LaunchToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 10_000_000 * 10 ** 7;
    uint256 public constant FEE_BPS = 500;
    address public constant FEE_RECIPIENT = 0x20a2Fb1bb9e6C1443C11703cCecB3685cd99b7C5;

    /// @dev The deploying account or factory receives the entire supply; issuance is not taxed.
    constructor() ERC20("drIMD", "DRIM") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 7;
    }

    /// @dev Both ERC-20 transfer entry points reach this function. There are no fee exemptions.
    /// Fee rounds down in minor units; amount / 20 is exactly floor(amount * 5 / 100).
    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // Validate the gross amount before credits, including when accounts coincide.
        uint256 balance = balanceOf(from);
        if (balance < amount) {
            revert ERC20InsufficientBalance(from, balance, amount);
        }

        uint256 fee = amount / (10_000 / FEE_BPS);
        if (fee != 0) {
            super._update(from, FEE_RECIPIENT, fee);
        }
        super._update(from, to, amount - fee);
    }
}
