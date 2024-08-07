// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { PSMVariant1Actions } from "src/PSMVariant1Actions.sol";

interface PSMLiteLike {
    function pocket() external view returns (address);
}

// Testing the actual deploy of PSMVariant1Actions pointed at the PSM Lite
contract PSMVariant2ActionsIntegrationTest is Test {

    address constant PSM_LITE = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 constant PSM_DAI_START  = 20_126_331.49636e18;
    uint256 constant PSM_USDC_START = 19_873_668.503640e6;

    IERC20   dai  = IERC20(DAI);
    IERC20   usdc = IERC20(USDC);
    IERC4626 sdai = IERC4626(SDAI);

    address pocket;

    PSMVariant1Actions actions = PSMVariant1Actions(0x5803199F1085d52D1Bb527f24Dc1A2744e80A979);

    function setUp() public virtual {
        vm.createSelectFork(getChain('mainnet').rpcUrl, 20426716);  // Jul 31, 2024

        pocket = PSMLiteLike(PSM_LITE).pocket();
    }

    function test_deploy() public view {
        assertEq(address(actions.psm()),          PSM_LITE);
        assertEq(address(actions.dai()),          DAI);
        assertEq(address(actions.gem()),          USDC);
        assertEq(address(actions.savingsToken()), SDAI);
    }

    function test_swapAndDeposit() public {
        deal(USDC, address(this), 100e6);
        usdc.approve(address(actions), 100e6);

        assertEq(dai.balanceOf(PSM_LITE),                             PSM_DAI_START);
        assertEq(usdc.balanceOf(pocket),                              PSM_USDC_START);
        assertEq(usdc.balanceOf(address(this)),                       100e6);
        assertEq(sdai.convertToAssets(sdai.balanceOf(address(this))), 0);

        actions.swapAndDeposit(address(this), 100e6, 100e18);

        assertEq(dai.balanceOf(PSM_LITE),                             PSM_DAI_START - 100e18);
        assertEq(usdc.balanceOf(pocket),                              PSM_USDC_START + 100e6);
        assertEq(usdc.balanceOf(address(this)),                       0);
        assertEq(sdai.convertToAssets(sdai.balanceOf(address(this))), 99.999999999999999999e18);  // Rounding
    }

    function test_withdrawAndSwap() public {
        uint256 shares = sdai.convertToShares(100e18);
        deal(SDAI, address(this), shares);
        sdai.approve(address(actions), shares);

        assertEq(dai.balanceOf(PSM_LITE),                             PSM_DAI_START);
        assertEq(usdc.balanceOf(pocket),                              PSM_USDC_START);
        assertEq(usdc.balanceOf(address(this)),                       0);
        assertEq(sdai.convertToAssets(sdai.balanceOf(address(this))), 99.999999999999999999e18);  // Rounding

        // Make slightly lower than 100e6 to account for rounding errors
        actions.withdrawAndSwap(address(this), 99e6, 100e18);

        assertEq(dai.balanceOf(PSM_LITE),                             PSM_DAI_START + 99e18);
        assertEq(usdc.balanceOf(pocket),                              PSM_USDC_START - 99e6);
        assertEq(usdc.balanceOf(address(this)),                       99e6);
        assertEq(sdai.convertToAssets(sdai.balanceOf(address(this))), 0.999999999999999998e18);  // Some dust left over
    }

    function test_redeemAndSwap() public {
        uint256 shares = sdai.convertToShares(100e18);
        deal(SDAI, address(this), shares);
        sdai.approve(address(actions), shares);

        assertEq(dai.balanceOf(PSM_LITE),                             PSM_DAI_START);
        assertEq(usdc.balanceOf(pocket),                              PSM_USDC_START);
        assertEq(usdc.balanceOf(address(this)),                       0);
        assertEq(sdai.convertToAssets(sdai.balanceOf(address(this))), 99.999999999999999999e18);  // Rounding

        // Make slightly lower than 100e6 to account for rounding errors
        actions.redeemAndSwap(address(this), shares, 99e6);

        assertEq(dai.balanceOf(PSM_LITE),                             PSM_DAI_START + 99.999999e18);
        assertEq(usdc.balanceOf(pocket),                              PSM_USDC_START - 99.999999e6);
        assertEq(usdc.balanceOf(address(this)),                       99.999999e6);
        assertEq(sdai.convertToAssets(sdai.balanceOf(address(this))), 0);
    }

}
