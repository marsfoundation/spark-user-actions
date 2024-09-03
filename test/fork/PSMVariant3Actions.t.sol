// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { PSMVariant1Actions } from "src/PSMVariant1Actions.sol";

interface PSMLiteLike {
    function pocket() external view returns (address);
}

// Testing the vnet deploy of PSMVariant1Actions pointed at the USDS PSM Wrapper
contract PSMVariant3ActionsIntegrationTest is Test {

    address constant PSM_LITE         = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;
    address constant PSM_LITE_WRAPPER = 0x9581c795DBcaf408E477F6f1908a41BE43093122;

    address constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDS  = 0xd2983525E903Ef198d5dD0777712EB66680463bc;
    address constant SUSDS = 0xCd9BC6cE45194398d12e27e1333D5e1d783104dD;
    address constant USDC  = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 constant PSM_DAI_START = 202_266_582.319474e18;
    uint256 constant PSM_USDC_START = 478_621_711.210359e6;

    IERC20   dai   = IERC20(DAI);
    IERC20   usds  = IERC20(USDS);
    IERC20   usdc  = IERC20(USDC);
    IERC4626 susds = IERC4626(SUSDS);

    address pocket;

    PSMVariant1Actions actions = PSMVariant1Actions(0x28e4B8BE2748E9BD4b9cEAc4E05069E58773Af7E);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("TENDERLY_STAGING_URL"), 20627496);

        pocket = PSMLiteLike(PSM_LITE).pocket();
    }

    function test_deploy() public view {
        assertEq(address(actions.psm()),          PSM_LITE_WRAPPER);
        assertEq(address(actions.dai()),          USDS);
        assertEq(address(actions.gem()),          USDC);
        assertEq(address(actions.savingsToken()), SUSDS);
    }

    function test_swapAndDeposit() public {
        deal(USDC, address(this), 100e6);
        usdc.approve(address(actions), 100e6);

        assertEq(dai.balanceOf(PSM_LITE),                               PSM_DAI_START);
        assertEq(usdc.balanceOf(pocket),                                PSM_USDC_START);
        assertEq(usdc.balanceOf(address(this)),                         100e6);
        assertEq(susds.convertToAssets(susds.balanceOf(address(this))), 0);

        actions.swapAndDeposit(address(this), 100e6, 100e18);

        assertEq(dai.balanceOf(PSM_LITE),                               PSM_DAI_START - 100e18);
        assertEq(usdc.balanceOf(pocket),                                PSM_USDC_START + 100e6);
        assertEq(usdc.balanceOf(address(this)),                         0);
        assertEq(susds.convertToAssets(susds.balanceOf(address(this))), 99.999999999999999999e18);  // Rounding
    }

    function test_withdrawAndSwap() public {
        uint256 shares = susds.convertToShares(100e18);
        deal(SUSDS, address(this), shares);
        susds.approve(address(actions), shares);

        assertEq(dai.balanceOf(PSM_LITE),                               PSM_DAI_START);
        assertEq(usdc.balanceOf(pocket),                                PSM_USDC_START);
        assertEq(usdc.balanceOf(address(this)),                         0);
        assertEq(susds.convertToAssets(susds.balanceOf(address(this))), 99.999999999999999999e18);  // Rounding

        // Make slightly lower than 100e6 to account for rounding errors
        actions.withdrawAndSwap(address(this), 99e6, 100e18);

        assertEq(dai.balanceOf(PSM_LITE),                               PSM_DAI_START + 99e18);
        assertEq(usdc.balanceOf(pocket),                                PSM_USDC_START - 99e6);
        assertEq(usdc.balanceOf(address(this)),                         99e6);
        assertEq(susds.convertToAssets(susds.balanceOf(address(this))), 0.999999999999999998e18);  // Some dust left over
    }

    function test_redeemAndSwap() public {
        uint256 shares = susds.convertToShares(100e18);
        deal(SUSDS, address(this), shares);
        susds.approve(address(actions), shares);

        assertEq(dai.balanceOf(PSM_LITE),                               PSM_DAI_START);
        assertEq(usdc.balanceOf(pocket),                                PSM_USDC_START);
        assertEq(usdc.balanceOf(address(this)),                         0);
        assertEq(susds.convertToAssets(susds.balanceOf(address(this))), 99.999999999999999999e18);  // Rounding

        // Make slightly lower than 100e6 to account for rounding errors
        actions.redeemAndSwap(address(this), shares, 99e6);

        assertEq(dai.balanceOf(PSM_LITE),                               PSM_DAI_START + 99.999999e18);
        assertEq(usdc.balanceOf(pocket),                                PSM_USDC_START - 99.999999e6);
        assertEq(usdc.balanceOf(address(this)),                         99.999999e6);
        assertEq(susds.convertToAssets(susds.balanceOf(address(this))), 0);
    }

}
