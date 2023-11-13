// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralisedStablecoin
 * @author howellsy
 * Collateral: Exogenous (wETH and wBTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract to be governed by DSCEngine. This is just the ERC20 token.
 */
contract DecentralisedStablecoin is ERC20Burnable, Ownable {
    error DecentralisedStablecoin__BurnAmountExceedsBalance();
    error DecentralisedStablecoin__MustBeMoreThanZero();
    error DecentralisedStablecoin__NotZeroAddress();

    constructor() ERC20("DecentralisedStablecoin", "DSC") {}

    /**
     * @notice Mint new DSC tokens
     * @param _to The address to mint DSC tokens to
     * @param _amount The amount of DSC tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStablecoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralisedStablecoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }

    /**
     * @notice Burn DSC tokens
     * @param _amount The amount of DSC tokens to burn
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStablecoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralisedStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
