// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DecentralisedStablecoin} from "../../src/DecentralisedStablecoin.sol";

contract DecentralisedStablecoinTest is Test {
    DecentralisedStablecoin dsc;

    function setUp() public {
        dsc = new DecentralisedStablecoin();
    }

    function testBurnAmountMustExceedBalance() public {
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__BurnAmountExceedsBalance.selector);
        dsc.burn(1);
    }

    function testMustMintMoreThanZero() public {
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__MustBeMoreThanZero.selector);
        dsc.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testCannotMintToZeroAddress() public {
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__NotZeroAddress.selector);
        dsc.mint(address(0), 1);
    }
}
