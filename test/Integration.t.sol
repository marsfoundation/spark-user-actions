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

        potDaiAccumulated = (pot.drip() * pot.Pie()) - VAT_DAI_POT;

        vm.revertTo(snapshotId);

    }

    /**********************************************************************************************/
    /*** State diff functions and modifiers                                                     ***/
    /**********************************************************************************************/

    modifier logStateDiff() {
        // vm.startStateDiffRecording();

        _;

        // VmSafe.AccountAccess[] memory records = vm.stopAndReturnStateDiff();

        // console.log("--- STATE DIFF ---");

        // for (uint256 i = 0; i < records.length; i++) {
        //     for (uint256 j; j < records[i].storageAccesses.length; j++) {
        //         if (!records[i].storageAccesses[j].isWrite) continue;

        //         if (
        //             records[i].storageAccesses[j].newValue ==
        //             records[i].storageAccesses[j].previousValue
        //         ) continue;

        //         _logStorageModification(records[i], j);
        //     }
        // }
    }

    function _logStorageModification(VmSafe.AccountAccess memory record, uint256 index)
        internal view
    {
        console.log("");
        console2.log("account:  %s", vm.getLabel(record.account));
        console2.log("accessor: %s", vm.getLabel(record.accessor));
        console2.log("slot:     %s", vm.toString(record.storageAccesses[index].slot));

        _logAddressOrUint("oldValue:", record.storageAccesses[index].previousValue);
        _logAddressOrUint("newValue:", record.storageAccesses[index].newValue);
    }

    function _logAddressOrUint(string memory key, bytes32 _bytes) internal view {
        if (isAddress(_bytes)) {
            console.log(key, vm.toString(bytes32ToAddress(_bytes)));
        } else {
            console.log(key, vm.toString(uint256(_bytes)));
        }
    }

    function isAddress(bytes32 _bytes) public pure returns (bool) {
        if (_bytes == 0) return false;

        address extractedAddress = address(uint160(uint256(_bytes)));

        // Check if the address equals the original bytes32 value when padded back to bytes32
        return extractedAddress != address(0) && bytes32(bytes20(extractedAddress)) == _bytes;
    }

    function bytes32ToAddress(bytes32 _bytes) public pure returns (address) {
        require(isAddress(_bytes), "bytes32ToAddress/invalid-address");
        return address(uint160(uint256(_bytes)));
    }

}

contract PSMVariant1Actions_SwapAndDepositIntegrationTests is PSMVariant1ActionsIntegrationTestsBase {

    function test_logBalances() public {
        console.log("usdc.balanceOf(PSM_JOIN): %s", usdc.balanceOf(PSM_JOIN));
        console.log("vat.dai(PSM_JOIN))        %s", vat.dai(PSM_JOIN));
        console.log("vat.dai(PSM))             %s", vat.dai(PSM));
        console.log("vat.dai(SDAI))            %s", vat.dai(SDAI));
        console.log("usdc.balanceOf(SDAI)      %s", usdc.balanceOf(SDAI));
        console.log("dai.balanceOf(SDAI)       %s", dai.balanceOf(SDAI));
        console.log("pot.pie(SDAI)             %s", pot.pie(SDAI));
        console.log("vat.dai(POT)              %s", vat.dai(POT));
        console.log("dai.totalSupply()         %s", dai.totalSupply());
    }

    function _runSwapAndDepositTest(uint256 amount, address receiver) internal {
        uint256 amount18 = amount * 1e12;

        uint256 potDaiAccumulated = _getCurrentPotDaiAccumulated();

        assertEq(potDaiAccumulated, 3_318.530728803752113169892229145877765319795805405e45);

        deal(USDC, address(this), amount);

        usdc.approve(address(actions), amount);

        assertEq(usdc.allowance(address(this), address(actions)), amount);

        assertEq(usdc.balanceOf(address(this)), amount);
        assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN);

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);
        assertEq(vat.dai(POT),  VAT_DAI_POT);
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI);

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART);  // Ink should equal art for PSM
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART);  // Ink should equal art for PSM
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART);

        assertEq(dai.totalSupply(), DAI_TOTAL_SUPPLY);

        assertEq(sdai.balanceOf(address(this)), 0);
        assertEq(sdai.totalAssets(),            SDAI_TOTAL_ASSETS);

        uint256 amountDeposited = actions.swapAndDeposit(receiver, amount, amount18);

        assertEq(amountDeposited, amount18);

        assertEq(usdc.allowance(address(this), address(actions)), 0);

        assertEq(usdc.balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN + amount);

        // 8.2e-19 dust amount from converting to shares then back to dai in pot.join call
        uint256 sDaiDustAmount = 0.000000000000000000827851769141817336099518530e45;

        assertEq(vat.dai(VOW),  VAT_DAI_VOW);  // No fees
        assertEq(vat.dai(POT),  VAT_DAI_POT + potDaiAccumulated + 1_000_000e45 - sDaiDustAmount);
        assertEq(vat.dai(SDAI), VAT_DAI_SDAI + sDaiDustAmount);

        assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART + amount18);  // Ink should equal art for PSM
        assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART + amount18);  // Ink should equal art for PSM
        assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART + amount18);

        assertEq(dai.totalSupply(), DAI_TOTAL_SUPPLY);  // No net change in ERC20 supply

        uint256 expectedSDaiBalance = 921_544.767332950511118705e18;

        assertEq(sdai.previewDeposit(amount18), expectedSDaiBalance);

        assertEq(sdai.balanceOf(receiver), expectedSDaiBalance);

        assertApproxEqAbs(sdai.totalAssets(), SDAI_TOTAL_ASSETS + amount18, 1);  // Rounding
    }

    function test_swapAndDeposit_sameReceiver() public {
        _runSwapAndDepositTest(1_000_000e6, address(this));
    }

    function test_swapAndDeposit_differentReceiver() public {
        _runSwapAndDepositTest(1_000_000e6, makeAddr("receiver"));
    }

    // TODO: Figure out issue here
    // function testFuzz_swapAndDeposit_sameReceiver(uint256 amount) public {
    //     // 1 trillion max
    //     _runSwapAndDepositTest(_bound(amount, 0, 1e12 * 1e6), address(this));
    // }

}

// contract PSMVariant1Actions_WithdrawAndSwapIntegrationTests is PSMVariant1ActionsIntegrationTestsBase {

//     uint256 constant override VAT_DAI_POT       = 1_920_648_463.946930438663372526251818820658316413154467601e45;

//     function setUp() public override {
//         super.setUp();

//         deal(DAI, address(this), 1_000_000e18);
//         dai.approve(address(SDAI), 1_000_000e18);
//         sdai.deposit(1_000_000e18, address(this));  // Pot drip happens here
//     }

//     function test_withdrawAndSwap_sameReceiver() public {
//         uint256 potDaiAccumulated = _getCurrentPotDaiAccumulated();

//         assertEq(potDaiAccumulated, 3_318.530728803752113169892229145877765319795805405e45);

//         deal(USDC, address(this), 1_000_000e6);

//         usdc.approve(address(actions), 1_000_000e6);

//         assertEq(usdc.allowance(address(this), address(actions)), 1_000_000e6);

//         assertEq(usdc.balanceOf(address(this)), 1_000_000e6);
//         assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN);

//         assertEq(vat.dai(VOW),  VAT_DAI_VOW);
//         assertEq(vat.dai(POT),  VAT_DAI_POT);
//         assertEq(vat.dai(SDAI), VAT_DAI_SDAI);

//         assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART);  // Ink should equal art for PSM
//         assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART);  // Ink should equal art for PSM
//         assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART);

//         assertEq(dai.totalSupply(), DAI_TOTAL_SUPPLY);

//         assertEq(sdai.balanceOf(address(this)), 0);
//         assertEq(sdai.totalAssets(),            SDAI_TOTAL_ASSETS);

//         uint256 amountDeposited = actions.swapAndDeposit(address(this), 1_000_000e6, 1_000_000e18);

//         assertEq(amountDeposited, 1_000_000e18);

//         assertEq(usdc.allowance(address(this), address(actions)), 0);

//         assertEq(usdc.balanceOf(address(this)), 0);
//         assertEq(usdc.balanceOf(PSM_JOIN),      USDC_BAL_PSM_JOIN + 1_000_000e6);

//         // 8.2e-19 dust amount from converting to shares then back to dai in pot.join call
//         uint256 sDaiDustAmount = 0.000000000000000000827851769141817336099518530e45;

//         assertEq(vat.dai(VOW),  VAT_DAI_VOW);  // No fees
//         assertEq(vat.dai(POT),  VAT_DAI_POT + potDaiAccumulated + 1_000_000e45 - sDaiDustAmount);
//         assertEq(vat.dai(SDAI), VAT_DAI_SDAI + sDaiDustAmount);

//         assertEq(vat.urns(ILK, PSM).ink, VAT_ILK_ART + 1_000_000e18);  // Ink should equal art for PSM
//         assertEq(vat.urns(ILK, PSM).art, VAT_ILK_ART + 1_000_000e18);  // Ink should equal art for PSM
//         assertEq(vat.ilks(ILK).Art,      VAT_ILK_ART + 1_000_000e18);

//         assertEq(dai.totalSupply(), DAI_TOTAL_SUPPLY);  // No net change in ERC20 supply

//         uint256 expectedSDaiBalance = 921_544.767332950511118705e18;

//         assertEq(sdai.previewDeposit(1_000_000e18), expectedSDaiBalance);

//         assertEq(sdai.balanceOf(address(this)), expectedSDaiBalance);
//         assertEq(sdai.totalAssets(),            SDAI_TOTAL_ASSETS + 1_000_000e18 - 1);  // Rounding
//     }
// }
