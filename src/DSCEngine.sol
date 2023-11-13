// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralisedStablecoin} from "./DecentralisedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIATION_PRECISION = 100;
    uint256 private constant LIQUIATION_THRESHOLD = 50; // 200% overcollateralised
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant PRECISION = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256)) private s_collateralBalances;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collareralTokens;

    DecentralisedStablecoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
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
            s_collareralTokens.push(tokenAddresses[i]);
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

    /**
     * @param amountDscToMint The amount of DSC tokens to mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // Do not allow minting if it could lead to liquidation
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /**
     * Loops through each collateral token and gets the value of all collateral in USD.
     */
    function getAccountCollateralValue() public view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;

        for (uint256 i = 0; i < s_collareralTokens.length; i++) {
            address token = s_collareralTokens[i];
            uint256 balance = s_collateralBalances[msg.sender][token];
            totalCollateralValueInUsd += getUsdValue(token, balance);
        }

        return totalCollateralValueInUsd;
    }

    /**
     * Gets the USD value of a token.
     * @param token The address of the token
     * @param amount The amount of the token
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue();
    }

    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, then they can be liquidated.
     * @param user The address of the user
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = collateralValueInUsd * LIQUIATION_THRESHOLD / LIQUIATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
}
