// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralisedStablecoin} from "./DecentralisedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSCEngine
 * @author howellsy
 *
 * The system is designed to be as minimal as possible, have the tokens maintain a 1:1 peg with
 * USD and be governed by this contract.
 *
 * The stablecoin has the properties:
 * - Collateral: Exogenous (wETH and wBTC)
 * - Minting: Algorithmic
 * - Relative Stability: Pegged to USD
 *
 * The DSC system should ALWAYS be overcollateralised. At no point, should the value of all
 * collateral be less than the value of all DSC tokens.
 *
 * It is similar to DAI - if DAI had no governance, no fees and was only backed by wETH and wBTC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting
 * and redeeming DSC tokens, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256)) private s_collateralBalances;

    DecentralisedStablecoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_dsc = DecentralisedStablecoin(dscAddress);
    }

    /**
     * @param tokenCollateral The address of the collateral token
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateral, uint256 amount)
        external
        moreThanZero(amount)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        s_collateralBalances[msg.sender][tokenCollateral] += amount;
        emit CollateralDeposited(msg.sender, tokenCollateral, amount);
        bool success = IERC20(tokenCollateral).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function depositCollateralAndMintDsc() external {}

    function redeemCollateral() external {}

    function redeemCollateralForDsc() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
