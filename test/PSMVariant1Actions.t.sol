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

    address receiver = makeAddr("receiver");

    function setUp() public {
        dai = new MockERC20('DAI',  'DAI',  18);
        gem = new MockERC20('USDC', 'USDC', 6);

        savingsToken = new ERC4626Mock(dai, 'Savings DAI', 'sDAI', 18);
        psm          = new PSMVariant1Mock(dai, gem);

        // Set the savings token to 1.25 conversion rate to keep the shares different
        savingsToken.__setShareConversionRate(1.25e18);

        // Put some existing gems into the PSM
        gem.mint(address(psm), 1000e6);

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

        assertEq(gem.allowance(address(actions), address(psm.gemJoin())), type(uint256).max);
        assertEq(dai.allowance(address(actions), address(psm)),           type(uint256).max);
        assertEq(dai.allowance(address(actions), address(savingsToken)),  type(uint256).max);
    }

    function test_swapAndDeposit_insufficientBalance_boundary() public {
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.swapAndDeposit(address(this), 100e6, 100e18);

        gem.mint(address(this), 1);

        actions.swapAndDeposit(address(this), 100e6, 100e18);
    }

    function test_swapAndDeposit_insufficientApproval_boundary() public {
        gem.approve(address(actions), 100e6 - 1);
        gem.mint(address(this), 100e6);

        vm.expectRevert(stdError.arithmeticError);
        actions.swapAndDeposit(address(this), 100e6, 100e18);

        gem.approve(address(actions), 100e6);

        actions.swapAndDeposit(address(this), 100e6, 100e18);
    }

    function test_swapAndDeposit_amountOutTooLow_boundary() public {
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);

        vm.expectRevert("PSMVariant1Actions/amount-out-too-low");
        actions.swapAndDeposit(address(this), 100e6, 100e18 + 1);

        actions.swapAndDeposit(address(this), 100e6, 100e18);
    }

    function test_swapAndDeposit_differentReceiver() public {
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);

        assertEq(gem.balanceOf(address(this)),          100e6);
        assertEq(dai.balanceOf(address(this)),          0);
        assertEq(savingsToken.balanceOf(address(this)), 0);

        assertEq(gem.balanceOf(receiver),          0);
        assertEq(dai.balanceOf(receiver),          0);
        assertEq(savingsToken.balanceOf(receiver), 0);

        assertEq(gem.balanceOf(address(actions)),          0);
        assertEq(dai.balanceOf(address(actions)),          0);
        assertEq(savingsToken.balanceOf(address(actions)), 0);

        actions.swapAndDeposit(receiver, 100e6, 100e18);

        assertEq(gem.balanceOf(address(this)),          0);
        assertEq(dai.balanceOf(address(this)),          0);
        assertEq(savingsToken.balanceOf(address(this)), 0);

        assertEq(gem.balanceOf(receiver),          0);
        assertEq(dai.balanceOf(receiver),          0);
        assertEq(savingsToken.balanceOf(receiver), 80e18);  // 100 dai / 1.25

        assertEq(gem.balanceOf(address(actions)),          0);
        assertEq(dai.balanceOf(address(actions)),          0);
        assertEq(savingsToken.balanceOf(address(actions)), 0);
    }

    function test_swapAndDeposit_sameReceiver() public {
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);

        assertEq(gem.balanceOf(address(this)),          100e6);
        assertEq(dai.balanceOf(address(this)),          0);
        assertEq(savingsToken.balanceOf(address(this)), 0);

        assertEq(gem.balanceOf(address(actions)),          0);
        assertEq(dai.balanceOf(address(actions)),          0);
        assertEq(savingsToken.balanceOf(address(actions)), 0);

        actions.swapAndDeposit(address(this), 100e6, 100e18);

        assertEq(gem.balanceOf(address(this)),          0);
        assertEq(dai.balanceOf(address(this)),          0);
        assertEq(savingsToken.balanceOf(address(this)), 80e18);  // 100 dai / 1.25

        assertEq(gem.balanceOf(address(actions)),          0);
        assertEq(dai.balanceOf(address(actions)),          0);
        assertEq(savingsToken.balanceOf(address(actions)), 0);
    }
    
}
