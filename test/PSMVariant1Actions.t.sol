// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { PSMVariant1Actions } from "src/PSMVariant1Actions.sol";

contract PSMVariant1ActionsTest is Test {
    
    PSMVariant1Actions actions;

    function setUp() public {
        actions = new PSMVariant1Actions();
    }
    
}
