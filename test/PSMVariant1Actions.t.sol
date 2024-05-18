// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

import { ERC4626Mock }     from "./mocks/ERC4626Mock.sol";
import { PSMVariant1Mock } from "./mocks/PSMVariant1Mock.sol";

import { PSMVariant1Actions } from "src/PSMVariant1Actions.sol";

contract PSMVariant1ActionsTest is Test {

    MockERC20 dai;
    MockERC20 gem;

    ERC4626Mock     savingsToken;
    PSMVariant1Mock psm;
    
    PSMVariant1Actions actions;

    function setUp() public {
        dai = new MockERC20('DAI',  'DAI',  18);
        gem = new MockERC20('USDC', 'USDC', 6);

        savingsToken = new ERC4626Mock(dai, 'Savings DAI', 'sDAI', 18);
        psm          = new PSMVariant1Mock(dai, gem);

        actions = new PSMVariant1Actions(
            address(psm),
            address(savingsToken)
        );
    }

    function test_constructor() public {
        // For coverage
        actions = new PSMVariant1Actions(
            address(psm),
            address(savingsToken)
        );

        assertEq(address(actions.psm()),          address(psm));
        assertEq(address(actions.dai()),          address(dai));
        assertEq(address(actions.gem()),          address(gem));
        assertEq(address(actions.savingsToken()), address(savingsToken));
    }
    
}
