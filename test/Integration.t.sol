// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { VmSafe } from "forge-std/Vm.sol";

import { PSMVariant1Actions } from "src/PSMVariant1Actions.sol";

interface PotLike {
    function drip() external returns (uint256);
    function pie(address) external view returns (uint256);
    function Pie() external view returns (uint256);
}

interface VatLike {

    struct Ilk {
        uint256 Art;   // Total Normalised Debt     [wad]
        uint256 rate;  // Accumulated Rates         [ray]
        uint256 spot;  // Price with Safety Margin  [ray]
        uint256 line;  // Debt Ceiling              [rad]
        uint256 dust;  // Urn Debt Floor            [rad]
    }

    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }

    function dai(address) external view returns (uint256);
    function gem(bytes32, address) external view returns (uint256);

    function ilks(bytes32) external view returns (Ilk memory);
    function urns(bytes32, address) external view returns (Urn memory);

}

contract PSMVariant1ActionsIntegrationTestsBase is Test {

    address constant DAI_JOIN = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    address constant POT      = 0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7;
    address constant PSM      = 0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A;
    address constant PSM_JOIN = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address constant VAT      = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;
    address constant VOW      = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 constant ILK = 0x50534d2d555344432d4100000000000000000000000000000000000000000000;

    uint256 constant DAI_TOTAL_SUPPLY  = 3_277_005_671.384947469248718868e18;
    uint256 constant POT_PIE_SDAI      = 1_087_191_769.339009779766668186e18;
    uint256 constant USDC_BAL_PSM_JOIN = 397_230_762.715481e6;
    uint256 constant SDAI_TOTAL_ASSETS = 1_179_749_273.044498397455042877e18;
    uint256 constant VAT_DAI_VOW       = 86_172_120.142476059205430167309035155786174506543745474e45;
    uint256 constant VAT_DAI_POT       = 1_920_648_463.946930438663372526251818820658316413154467601e45;
    uint256 constant VAT_DAI_SDAI      = 0.000000000000012822794354009192623673159194387e45;
    uint256 constant VAT_ILK_ART       = 397_230_663.706936e18;

    IERC20 constant dai  = IERC20(DAI);
    IERC20 constant usdc = IERC20(USDC);

    IERC4626 constant sdai = IERC4626(SDAI);

    PotLike constant pot = PotLike(POT);
    VatLike constant vat = VatLike(VAT);

    PSMVariant1Actions actions;

    function setUp() public virtual {
        vm.createSelectFork(getChain('mainnet').rpcUrl, 19961500);  // May 27, 2024

        actions = new PSMVariant1Actions(PSM, SDAI);

        vm.label(POT, "POT");
        vm.label(PSM, "PSM");
        vm.label(DAI_JOIN, "DAI_JOIN");
        vm.label(PSM_JOIN, "PSM_JOIN");
        vm.label(VAT, "VAT");
        vm.label(DAI, "DAI");
        vm.label(SDAI, "SDAI");
        vm.label(USDC, "USDC");
        vm.label(address(actions), "ACTIONS");
        vm.label(address(this), "THIS");

        // Added because of log state using implementation instead of proxy
        vm.label(0x43506849D7C04F9138D1A2050bbF3A0c054402dd, "USDC_IMPL");
    }

    function _getCurrentPotDaiAccumulated() internal returns (uint256 potDaiAccumulated) {
        uint256 snapshotId = vm.snapshot();
        potDaiAccumulated = (pot.drip() * pot.Pie()) - vat.dai(POT);
        vm.revertTo(snapshotId);
    }

}

contract PSMVariant1Actions_SwapAndDepositIntegrationTests is PSMVariant1ActionsIntegrationTestsBase {

    function _runSwapAndDepositTest(address receiver) internal {
        uint256 potDaiAccumulated = _getCurrentPotDaiAccumulated();

        assertEq(potDaiAccumulated, 3_318.530728803752113169892229145877765319795805405e45);

        deal(USDC, address(this), 1_000_000e6);

        usdc.approve(address(actions), 1_000_000e6);

        assertEq(usdc.allowance(address(this), address(actions)), 1_000_000e6);

        assertEq(usdc.balanceOf(address(this)), 1_000_000e6);
        assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN);

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);
        assertEq(vat.dai(POT),  VAT_DAI_POT);
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI);

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART);  // Ink should equal art for PSM in this scenario
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART);  // Ink should equal art for PSM in this scenario
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART);

        assertEq(pot.pie(SDAI), POT_PIE_SDAI);

        assertEq(dai.totalSupply(), DAI_TOTAL_SUPPLY);

        assertEq(sdai.balanceOf(address(this)), 0);
        assertEq(sdai.totalAssets(),            SDAI_TOTAL_ASSETS);

        uint256 amountDeposited = actions.swapAndDeposit(receiver, 1_000_000e6, 1_000_000e18);

        assertEq(amountDeposited, 1_000_000e18);

        assertEq(usdc.allowance(address(this), address(actions)), 0);

        assertEq(usdc.balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN + 1_000_000e6);

        // 8.2e-19 dust amount from converting to shares then back to dai in pot.join call
        uint256 sDaiDustAmount = 0.000000000000000000827851769141817336099518530e45;

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);  // No fees
        assertEq(vat.dai(POT),  VAT_DAI_POT + potDaiAccumulated + 1_000_000e45 - sDaiDustAmount);
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI + sDaiDustAmount);

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART + 1_000_000e18);  // Ink should equal art for PSM in this scenario
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART + 1_000_000e18);  // Ink should equal art for PSM in this scenario
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART + 1_000_000e18);

        uint256 expectedSDaiBalance = 921_544.767332950511118705e18;

        assertEq(sdai.previewDeposit(1_000_000e18), expectedSDaiBalance);  // Amount of shares minted in sDai

        assertEq(pot.pie(SDAI), POT_PIE_SDAI + expectedSDaiBalance);  // Shares increase in pot same as sDai shares increase

        assertEq(dai.totalSupply(), DAI_TOTAL_SUPPLY);  // No net change in ERC20 supply

        assertEq(sdai.balanceOf(receiver), expectedSDaiBalance);
        assertEq(sdai.totalAssets(),       SDAI_TOTAL_ASSETS + 1_000_000e18 - 1);  // Rounding
    }

    function test_swapAndDeposit_sameReceiver() public {
        _runSwapAndDepositTest(address(this));
    }

    function test_swapAndDeposit_differentReceiver() public {
        _runSwapAndDepositTest(makeAddr("receiver"));
    }

}

contract PSMVariant1Actions_WithdrawAndSwapIntegrationTests is PSMVariant1ActionsIntegrationTestsBase {

    // Values updated from constants
    uint256 vatDaiPotUpdated;
    uint256 daiSupplyUpdated;

    function setUp() public override {
        super.setUp();

        deal(DAI, address(this), 1_000_000e18);
        dai.approve(address(SDAI), 1_000_000e18);
        sdai.deposit(1_000_000e18, address(this));  // Pot drip happens here

        vatDaiPotUpdated = vat.dai(POT);
        daiSupplyUpdated = dai.totalSupply();

        assertEq(vatDaiPotUpdated, 1_921_651_782.477659242415485695316196197394264396850754476e45);
        assertEq(daiSupplyUpdated, 3_276_005_671.384947469248718868e18);
    }

    function _runWithdrawAndSwapTest(address receiver) internal {
        uint256 expectedSDaiBalance = 921_544.767332950511118705e18;

        assertEq(sdai.previewDeposit(1_000_000e18), expectedSDaiBalance);  // Amount of shares minted in sDai

        // Simulate non-atomic withdrawAndSwap after deposit
        // Doing after previewDeposit because that changes over time
        skip(10 minutes);

        // Accumulated in 10min since deposit
        uint256 potDaiAccumulated = _getCurrentPotDaiAccumulated();

        assertEq(potDaiAccumulated, 2_813.782917739392486833695985337516761927773654622e45);

        sdai.approve(address(actions), 1_000_000e18);

        assertEq(usdc.balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN);

        // 8.2e-19 dust amount from converting to shares then back to dai in pot.join call
        // Same as in swapAndDeposit because its the same amount of DAI
        uint256 sDaiDustAmount1 = 0.000000000000000000827851769141817336099518530e45;

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);  // No fees
        assertEq(vat.dai(POT),  vatDaiPotUpdated);  // Updated pot value includes dust amount
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI + sDaiDustAmount1);

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART);  // Ink should equal art for PSM in this scenario
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART);  // Ink should equal art for PSM in this scenario
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART);

        assertEq(pot.pie(SDAI), POT_PIE_SDAI + expectedSDaiBalance);  // Shares increase in pot same as sDai shares increase

        assertEq(dai.totalSupply(), daiSupplyUpdated);

        assertEq(sdai.balanceOf(address(this)), expectedSDaiBalance);

        // Using a diff approach in this test because of accrued value to totalAssets
        uint256 totalAssets = sdai.totalAssets();

        uint256 amountIn = actions.withdrawAndSwap(receiver, 1_000_000e6, 1_000_000e18);

        assertEq(amountIn, 1_000_000e18);

        assertEq(usdc.balanceOf(receiver), 1_000_000e6);
        assertEq(usdc.balanceOf(PSM_JOIN), USDC_BAL_PSM_JOIN - 1_000_000e6);

        // 1e-18 dust amount from converting to shares then back to dai in pot.exit call
        uint256 sDaiDustAmount2 = 0.000000000000000001026428135379172868996806790e45;

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);  // No fees
        assertEq(vat.dai(POT),  vatDaiPotUpdated + potDaiAccumulated - 1_000_000e45 - sDaiDustAmount2);  // Updated pot value includes dust amount
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI + sDaiDustAmount1 + sDaiDustAmount2);

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART - 1_000_000e18);  // Ink should equal art for PSM in this scenario
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART - 1_000_000e18);  // Ink should equal art for PSM in this scenario
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART - 1_000_000e18);

        uint256 expectedRemainingBalance = 1.349372009568968235e18;

        assertEq(expectedSDaiBalance - sdai.previewWithdraw(1_000_000e18), expectedRemainingBalance);

        // Shares increase from before deposit but have decreased since withdraw
        assertEq(pot.pie(SDAI), POT_PIE_SDAI + expectedRemainingBalance);

        assertEq(dai.totalSupply(), daiSupplyUpdated);  // No net change in ERC20 supply

        assertEq(sdai.balanceOf(address(this)), expectedRemainingBalance);
        assertEq(sdai.totalAssets(),            totalAssets - 1_000_000e18 - 1);  // Rounding
    }

    function test_withdrawAndSwap_sameReceiver() public {
        _runWithdrawAndSwapTest(address(this));
    }

    function test_withdrawAndSwap_differentReceiver() public {
        _runWithdrawAndSwapTest(makeAddr("receiver"));
    }

}

contract PSMVariant1Actions_RedeemAndSwapIntegrationTests is PSMVariant1ActionsIntegrationTestsBase {

    // Values updated from constants
    uint256 vatDaiPotUpdated;
    uint256 daiSupplyUpdated;

    function setUp() public override {
        super.setUp();

        deal(DAI, address(this), 1_000_000e18);
        dai.approve(address(SDAI), 1_000_000e18);
        sdai.deposit(1_000_000e18, address(this));  // Pot drip happens here

        vatDaiPotUpdated = vat.dai(POT);
        daiSupplyUpdated = dai.totalSupply();

        assertEq(vatDaiPotUpdated, 1_921_651_782.477659242415485695316196197394264396850754476e45);
        assertEq(daiSupplyUpdated, 3_276_005_671.384947469248718868e18);
    }

    function _runRedeemAndSwapTest(address receiver) internal {
        uint256 expectedSDaiBalance = 921_544.767332950511118705e18;

        assertEq(sdai.previewDeposit(1_000_000e18), expectedSDaiBalance);  // Amount of shares minted in sDai

        // Simulate non-atomic redeemAndSwap after deposit
        // Doing after previewDeposit because that changes over time
        skip(10 minutes);

        // Accumulated in 10min since deposit
        uint256 potDaiAccumulated = _getCurrentPotDaiAccumulated();

        assertEq(potDaiAccumulated, 2_813.782917739392486833695985337516761927773654622e45);

        sdai.approve(address(actions), 1_000_000e18);

        assertEq(usdc.balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN);

        // 8.2e-19 dust amount from converting to shares then back to dai in pot.join call
        // Same as in swapAndDeposit because its the same amount of DAI
        uint256 sDaiDustAmount1 = 0.000000000000000000827851769141817336099518530e45;

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);  // No fees
        assertEq(vat.dai(POT),  vatDaiPotUpdated);  // Updated pot value includes dust amount
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI + sDaiDustAmount1);

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART);  // Ink should equal art for PSM in this scenario
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART);  // Ink should equal art for PSM in this scenario
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART);

        assertEq(pot.pie(SDAI), POT_PIE_SDAI + expectedSDaiBalance);  // Shares increase in pot same as sDai shares increase

        assertEq(dai.totalSupply(), daiSupplyUpdated);

        assertEq(sdai.balanceOf(address(this)), expectedSDaiBalance);

        // Using a diff approach in this test because of accrued value to totalAssets
        uint256 totalAssets = sdai.totalAssets();

        // Calculate shares to burn to get clean numbers for assertions
        uint256 sharesToBurn = sdai.previewWithdraw(1_000_000e18);

        uint256 amountOut = actions.redeemAndSwap(receiver, sharesToBurn, 1_000_000e6);

        assertEq(amountOut, 1_000_000e6);

        assertEq(usdc.balanceOf(receiver), 1_000_000e6);
        assertEq(usdc.balanceOf(PSM_JOIN), USDC_BAL_PSM_JOIN - 1_000_000e6);

        // 1e-18 dust amount from converting to shares then back to dai in pot.exit call
        uint256 sDaiDustAmount2 = 0.000000000000000001026428135379172868996806790e45;

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);  // No fees
        assertEq(vat.dai(POT),  vatDaiPotUpdated + potDaiAccumulated - 1_000_000e45 - sDaiDustAmount2);  // Updated pot value includes dust amount
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI + sDaiDustAmount1 + sDaiDustAmount2 - 1e27);  // Exactly 1e-18 rad dust removed, goes into erc20 totalSupply

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART - 1_000_000e18);  // Ink should equal art for PSM in this scenario
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART - 1_000_000e18);  // Ink should equal art for PSM in this scenario
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART - 1_000_000e18);

        uint256 expectedRemainingBalance = 1.349372009568968235e18;

        assertEq(expectedSDaiBalance - sdai.previewWithdraw(1_000_000e18), expectedRemainingBalance);

        // Shares increase from before deposit but have decreased since withdraw
        assertEq(pot.pie(SDAI), POT_PIE_SDAI + expectedRemainingBalance);

        assertEq(dai.totalSupply(), daiSupplyUpdated + 1);  // 1e-18 rad dust removed from vat internal accounting moved to totalSupply

        assertEq(sdai.balanceOf(address(this)), expectedRemainingBalance);
        assertEq(sdai.totalAssets(),            totalAssets - 1_000_000e18 - 1);
    }

    function test_redeemAndSwap_sameReceiver() public {
        _runRedeemAndSwapTest(address(this));
    }

    function test_redeemAndSwap_differentReceiver() public {
        _runRedeemAndSwapTest(makeAddr("receiver"));
    }

}
