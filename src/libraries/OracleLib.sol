// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author howellsy
 * @notice This library checks the Chainlink Oracle for stale data.
 * If a price is stale, the function will revert and render the DSCEngine unusable.
 */
library OracleLib {
    uint256 private constant TIMEOUT = 3 hours;

    error OracleLib__StalePrice();

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getTimeout() public pure returns (uint256) {
        return TIMEOUT;
    }
}
