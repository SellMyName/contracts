// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {SellMyName} from "../src/SellMyName.sol";

contract SellMyNameTest is Test {
    SellMyName public smn;

    function setUp() public {
        smn = new SellMyName();
    }
}
