// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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
contract DSCEngine {
    function depositCollateral() external {}

    function depositCollateralAndMintDsc() external {}

    function redeemCollateral() external {}

    function redeemCollateralForDsc() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
