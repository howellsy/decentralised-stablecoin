// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DecentralisedStablecoin} from "./DecentralisedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

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
    using OracleLib for AggregatorV3Interface;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralised
    uint256 private constant LIQUIDATOR_BONUS = 10; // a 10% bonus
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256)) private s_collateralBalances;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collareralTokens;

    DecentralisedStablecoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
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
     * ==================
     * External functions
     * ==================
     */

    /**
     * @param tokenCollateralAddress The ERC20 token address of the collateral being deposited
     * @param amountCollateral The amount of collateral being deposited
     * @param amountDscToMint The amount of DSC tokens to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * Burns DSC tokens and redeems collateral in one transaction.
     * @param tokenCollateral The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC tokens to burn
     */
    function redeemCollateralForDsc(address tokenCollateral, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        // redeemCollateral() checks if health factor is broken
        redeemCollateral(tokenCollateral, amountCollateral);
    }

    /**
     * If someone is almost at the liquidation threshold, then anyone can liquidate them.
     * @param collateral The address of the collateral token
     * @param user The address of the user to liquidate. Their health factor must be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC tokens to burn to cover the debt
     * @notice You can partially liquidate a user by passing in a lower debtToCover than the total debt
     * @notice The liquidator gets a 10% bonus on the collateral they liquidate.
     * @notice This function assumes the protocol will be roughly 200% overcollateralised at all times.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralBalances[user][token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collareralTokens;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATOR_BONUS;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    /**
     * ================
     * Public functions
     * ================
     */

    /**
     * @param amount The amount of DSC tokens to burn
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        // TODO: check if health factor could ever be broken from burning DSC
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param tokenCollateral The address of the collateral token
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateral, uint256 amount)
        public
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

    /**
     * @param amountDscToMint The amount of DSC tokens to mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // Do not allow minting if it could lead to liquidation
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * Loops through each collateral token and gets the value of all collateral in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;

        for (uint256 i = 0; i < s_collareralTokens.length; i++) {
            address token = s_collareralTokens[i];
            uint256 balance = s_collateralBalances[user][token];
            totalCollateralValueInUsd += getUsdValue(token, balance);
        }

        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * Gets the USD value of a token.
     * @param token The address of the token
     * @param amount The amount of the token
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    /**
     * In order to redeem collateral, the health factor must be above 1 AFTER the collateral is removed.
     */
    function redeemCollateral(address tokenCollateral, uint256 amount) public moreThanZero(amount) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateral, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * ==================
     * Internal functions
     * ==================
     */

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, then they can be liquidated.
     * @param user The address of the user
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @dev Low-level internal function only called when checking for a broken health factor.
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) internal {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        internal
    {
        s_collateralBalances[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        // handles the case where a user has deposited collateral and not yet minted DSC
        if (totalDscMinted == 0) return type(uint256).max;

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
}
