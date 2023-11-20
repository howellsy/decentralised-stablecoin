// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000 ether;

    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    function testGetTimeout() public {
        uint256 expectedTimeout = 3 hours;
        assertEq(OracleLib.getTimeout(), expectedTimeout);
    }

    function testStaleCheckRevertsWhenPriceIsStale() public {
        uint256 oracleLibTimeout = OracleLib.getTimeout();

        // simulate a stale price
        vm.warp(block.timestamp + oracleLibTimeout + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    function testStaleCheckReturnsDataWhenPriceIsNotStale() public {
        uint256 oracleLibTimeout = OracleLib.getTimeout();

        // simulate a non-stale price
        vm.warp(block.timestamp + oracleLibTimeout - 1 seconds);
        vm.roll(block.number + 1);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertEq(startedAt, 1);
        assertEq(updatedAt, 1);
        assertEq(answeredInRound, 1);
    }
}
