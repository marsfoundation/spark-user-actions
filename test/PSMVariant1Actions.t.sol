// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

import { ERC4626Mock }     from "./mocks/ERC4626Mock.sol";
import { PSMVariant1Mock } from "./mocks/PSMVariant1Mock.sol";

import { PSMVariant1Actions } from "src/PSMVariant1Actions.sol";

contract PSMVariant1ActionsTest is Test {

    // 1 trillion max of each
    uint256 constant MAX_DAI_AMOUNT = 1e12 * 1e18;
    uint256 constant MAX_GEM_AMOUNT = 1e12 * 1e6;

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

    function test_swapAndDeposit_amountOutTooLowWithFee_boundary() public {
        psm.__setTin(0.005e18);  // 0.5% fee
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);

        vm.expectRevert("PSMVariant1Actions/amount-out-too-low");
        actions.swapAndDeposit(address(this), 100e6, 99.5e18 + 1);

        actions.swapAndDeposit(address(this), 100e6, 99.5e18);
    }

    function test_swapAndDeposit_amountOutTooLowExistingBalance_boundary() public {
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);
        gem.mint(address(actions), 1e6);  // Mint some dust into the actions

        // Dust should not effect the boundary numbers
        vm.expectRevert("PSMVariant1Actions/amount-out-too-low");
        actions.swapAndDeposit(address(this), 100e6, 100e18 + 1);

        actions.swapAndDeposit(address(this), 100e6, 100e18);
    }

    function test_swapAndDeposit_differentReceiver() public {
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);

        _assertBalances({
            u:                   address(this),
            gemBalance:          100e6,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
        _assertZeroBalances(address(receiver));
        _assertZeroBalances(address(actions));

        actions.swapAndDeposit(receiver, 100e6, 100e18);

        _assertZeroBalances(address(this));
        _assertBalances({
            u:                   receiver,
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: 80e18  // 100 dai / 1.25
        });
        _assertZeroBalances(address(actions));
    }

    function test_swapAndDeposit_sameReceiver() public {
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);

        _assertBalances({
            u:                   address(this),
            gemBalance:          100e6,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
        _assertZeroBalances(address(actions));

        actions.swapAndDeposit(address(this), 100e6, 100e18);

        _assertBalances({
            u:                   address(this),
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: 80e18
        });
        _assertZeroBalances(address(actions));
    }

    function test_swapAndDeposit_fee() public {
        psm.__setTin(0.005e18);  // 0.5% fee
        gem.approve(address(actions), 100e6);
        gem.mint(address(this), 100e6);

        _assertBalances({
            u:                   address(this),
            gemBalance:          100e6,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
        _assertZeroBalances(address(actions));

        actions.swapAndDeposit(address(this), 100e6, 99.5e18);

        _assertBalances({
            u:                   address(this),
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: 79.6e18  // 99.5 dai / 1.25
        });
        _assertZeroBalances(address(actions));
    }

    function testFuzz_swapAndDeposit(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 fee
    ) public {
        amountIn = bound(amountIn, 0, MAX_GEM_AMOUNT);
        fee      = bound(fee, 0, 1e18);

        uint256 expectedAmountOut = amountIn * 1e12 - (amountIn * 1e12 * fee / 1e18);
        minAmountOut = bound(minAmountOut, 0, expectedAmountOut);

        psm.__setTin(fee);
        gem.approve(address(actions), type(uint256).max);
        gem.mint(address(this), amountIn);

        _assertBalances({
            u:                   address(this),
            gemBalance:          amountIn,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
        _assertZeroBalances(address(actions));

        actions.swapAndDeposit(address(this), amountIn, minAmountOut);

        _assertBalances({
            u:                   address(this),
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: expectedAmountOut * 1e18 / 1.25e18
        });
        _assertZeroBalances(address(actions));
    }

    function test_withdrawAndSwap_insufficientBalance_boundary() public {
        _deposit(address(this), 100e6);

        savingsToken.approve(address(actions), 80e18);
        savingsToken.burn(address(this), 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.withdrawAndSwap(address(this), 100e6, 100e18);

        savingsToken.mint(address(this), 1);

        actions.withdrawAndSwap(address(this), 100e6, 100e18);
    }

    function test_withdrawAndSwap_insufficientApproval_boundary() public {
        _deposit(address(this), 100e6);

        savingsToken.approve(address(actions), 80e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.withdrawAndSwap(address(this), 100e6, 100e18);

        savingsToken.approve(address(actions), 80e18);

        actions.withdrawAndSwap(address(this), 100e6, 100e18);
    }

    function test_withdrawAndSwap_amountInTooHigh_boundary() public {
        _deposit(address(this), 100e6);
        savingsToken.approve(address(actions), 80e18);

        vm.expectRevert("PSMVariant1Actions/amount-in-too-high");
        actions.withdrawAndSwap(address(this), 100e6, 100e18 - 1);

        actions.withdrawAndSwap(address(this), 100e6, 100e18);
    }

    function test_withdrawAndSwap_amountInTooHighWithFee_boundary() public {
        _deposit(address(this), 100.5e6);  // Mint 0.5% more to pay for the fee
        psm.__setTout(0.005e18);  // 0.5% fee
        savingsToken.approve(address(actions), type(uint256).max);

        vm.expectRevert("PSMVariant1Actions/amount-in-too-high");
        actions.withdrawAndSwap(address(this), 100e6, 100.5e18 - 1);

        actions.withdrawAndSwap(address(this), 100e6, 100.5e18);
    }

    function test_withdrawAndSwap_amountInTooHighExistingBalance_boundary() public {
        _deposit(address(this), 100e6);
        savingsToken.approve(address(actions), 80e18);
        dai.mint(address(actions), 1e18);  // Mint some dust into the actions

        // Dust should not effect the boundary numbers
        vm.expectRevert("PSMVariant1Actions/amount-in-too-high");
        actions.withdrawAndSwap(address(this), 100e6, 100e18 - 1);

        actions.withdrawAndSwap(address(this), 100e6, 100e18);
    }

    function test_withdrawAndSwap_differentReceiver() public {
        _deposit(address(this), 100e6);
        savingsToken.approve(address(actions), type(uint256).max);

        _assertBalances({
            u:                   address(this),
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: 80e18
        });
        _assertZeroBalances(address(receiver));
        _assertZeroBalances(address(actions));

        actions.withdrawAndSwap(receiver, 100e6, 100e18);

        _assertZeroBalances(address(this));
        _assertBalances({
            u:                   receiver,
            gemBalance:          100e6,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
        _assertZeroBalances(address(actions));
    }

    function test_withdrawAndSwap_sameReceiver() public {
        _deposit(address(this), 100e6);
        savingsToken.approve(address(actions), type(uint256).max);

        _assertBalances({
            u:                   address(this),
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: 80e18
        });
        _assertZeroBalances(address(actions));

        actions.withdrawAndSwap(address(this), 100e6, 100e18);

        _assertBalances({
            u:                   address(this),
            gemBalance:          100e6,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
        _assertZeroBalances(address(actions));
    }

    function test_withdrawAndSwap_fee() public {
        _deposit(address(this), 100.5e6);
        psm.__setTout(0.005e18);
        savingsToken.approve(address(actions), type(uint256).max);

        _assertBalances({
            u:                   address(this),
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: 80.4e18
        });
        _assertZeroBalances(address(actions));

        actions.withdrawAndSwap(address(this), 100e6, 100.5e18);

        _assertBalances({
            u:                   address(this),
            gemBalance:          100e6,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
        _assertZeroBalances(address(actions));
    }

    function testFuzz_withdrawAndSwap(
        uint256 amountOut,
        uint256 maxAmountIn,
        uint256 fee
    ) public {
        amountOut = bound(amountOut, 0, MAX_GEM_AMOUNT);
        fee       = bound(fee, 0, 1e18);

        uint256 expectedAmountIn = amountOut * 1e12 + (amountOut * 1e12 * fee / 1e18);
        maxAmountIn = bound(maxAmountIn, expectedAmountIn, type(uint256).max);

        psm.__setTout(fee);
        savingsToken.approve(address(actions), type(uint256).max);
        _deposit(address(this), expectedAmountIn / 1e12 + 1);  // Add one extra to deal with shares rounding

        assertEq(gem.balanceOf(address(this)),                   0);
        assertEq(dai.balanceOf(address(this)),                   0);
        assertApproxEqAbs(savingsToken.balanceOf(address(this)), expectedAmountIn * 1e18 / 1.25e18, 1e12);
        _assertZeroBalances(address(actions));

        actions.withdrawAndSwap(address(this), amountOut, maxAmountIn);

        assertEq(gem.balanceOf(address(this)),                   amountOut);
        assertEq(dai.balanceOf(address(this)),                   0);
        assertApproxEqAbs(savingsToken.balanceOf(address(this)), 0, 1e12);
        _assertZeroBalances(address(actions));
    }

    function test_redeemAndSwap_insufficientBalance_boundary() public {
        _deposit(address(this), 100e6);

        savingsToken.approve(address(actions), 80e18);
        savingsToken.burn(address(this), 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.redeemAndSwap(address(this), 80e18, 100e6);

        savingsToken.mint(address(this), 1);

        actions.redeemAndSwap(address(this), 80e18, 100e6);
    }

    function test_redeemAndSwap_insufficientApproval_boundary() public {
        _deposit(address(this), 100e6);

        savingsToken.approve(address(actions), 80e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.redeemAndSwap(address(this), 80e18, 100e6);

        savingsToken.approve(address(actions), 80e18);

        actions.redeemAndSwap(address(this), 80e18, 100e6);
    }

    function test_redeemAndSwap_amountOutTooLow_boundary() public {
        _deposit(address(this), 100e6);
        savingsToken.approve(address(actions), type(uint256).max);

        vm.expectRevert("PSMVariant1Actions/amount-out-too-low");
        actions.redeemAndSwap(address(this), 80e18, 100e6 + 1);

        actions.redeemAndSwap(address(this), 80e18, 100e6);
    }

    function test_redeemAndSwap_amountOutTooLowWithFee_boundary() public {
        _deposit(address(this), 100.5e6);  // Mint 0.5% more to pay for the fee
        psm.__setTout(0.005e18);  // 0.5% fee
        savingsToken.approve(address(actions), type(uint256).max);

        vm.expectRevert("PSMVariant1Actions/amount-out-too-low");
        actions.redeemAndSwap(address(this), 80.4e18, 100e6 + 1);

        actions.redeemAndSwap(address(this), 80.4e18, 100e6);
    }

    /******************************************************************************************************************/
    /*** Helper functions                                                                                           ***/
    /******************************************************************************************************************/

    function _assertBalances(address u, uint256 gemBalance, uint256 daiBalance, uint256 savingsTokenBalance) internal view {
        assertEq(gem.balanceOf(u),          gemBalance);
        assertEq(dai.balanceOf(u),          daiBalance);
        assertEq(savingsToken.balanceOf(u), savingsTokenBalance);
    }

    function _assertZeroBalances(address u) internal view {
        _assertBalances({
            u:                   u,
            gemBalance:          0,
            daiBalance:          0,
            savingsTokenBalance: 0
        });
    }

    function _deposit(address _receiver, uint256 amount) internal {
        gem.mint(address(this), amount);
        gem.approve(address(actions), amount);
        actions.swapAndDeposit(_receiver, amount, 0);
    }
    
}
