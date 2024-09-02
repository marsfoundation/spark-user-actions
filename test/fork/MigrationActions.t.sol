// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { MigrationActions } from "src/MigrationActions.sol";

interface PotLike {
    function drip() external returns (uint256);
}

interface VatLike {
    function dai(address) external view returns (uint256);
    function debt() external view returns (uint256);
}

interface SavingsTokenLike is IERC20 {
    function convertToAssets(uint256 shares) external view returns(uint256 assets);
    function convertToShares(uint256 assets) external view returns(uint256 shares);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function drip() external;
    function totalAssets() external view returns(uint256);
}

contract MigrationActionsIntegrationTestBase is Test {

    address constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDS  = 0xd2983525E903Ef198d5dD0777712EB66680463bc;
    address constant SDAI  = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant SUSDS = 0xCd9BC6cE45194398d12e27e1333D5e1d783104dD;

    address constant DAI_JOIN  = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    address constant USDS_JOIN = 0x8786A226918A4c6Cd7B3463ca200f156C964031f;
    address constant POT       = 0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7;
    address constant VAT       = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;

    address constant DAI_WHALE = 0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B;

    uint256 constant DAI_SUPPLY = 3_073_155_804.411575584359575254e18;

    IERC20 constant dai  = IERC20(DAI);
    IERC20 constant usds = IERC20(USDS);

    SavingsTokenLike constant sdai  = SavingsTokenLike(SDAI);
    SavingsTokenLike constant susds = SavingsTokenLike(SUSDS);

    PotLike constant pot = PotLike(POT);
    VatLike constant vat = VatLike(VAT);

    MigrationActions actions;

    address user = address(this);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("TENDERLY_STAGING_URL"), 20627496);

        actions = new MigrationActions(SDAI, SUSDS, DAI_JOIN, USDS_JOIN);
    }

    modifier assertDebtStateDoesNotChange() {
        // Assert that the total internal debt does not change, as well as the sum of the
        // ERC20 supply of DAI and USDS
        uint256 debt      = vat.debt();
        uint256 sumSupply = _getSumSupply();
        _;
        assertEq(vat.debt(),      debt);
        assertEq(_getSumSupply(), sumSupply);
    }

    // Using this instead of `deal` because totalSupply is important for this testing
    function _getDai(address receiver, uint256 amount) internal {
        vm.prank(DAI_WHALE);
        dai.transfer(receiver, amount);
    }

    function _getSumSupply() internal view returns (uint256) {
        // NOTE: sUSDS holds custody of USDS. In order to have a real time representation of all the
        //       outstanding value in the system, totalAssets of sUSDS should be used, and the
        //       custodied balance of USDS in sUSDS should be subtracted.
        return
            dai.totalSupply() +
            usds.totalSupply() +
            sdai.totalAssets() +
            susds.totalAssets() -
            usds.balanceOf(SUSDS);
    }

}

contract MigrateDaiToUsdsIntegrationTest is MigrationActionsIntegrationTestBase {

    function _runMigrateDAIToUSDSTest(uint256 amount) internal {
        dai.approve(address(actions), amount);

        assertEq(dai.balanceOf(user),  amount);
        assertEq(usds.balanceOf(user), 0);

        actions.migrateDAIToUSDS(user, amount);

        assertEq(dai.balanceOf(user),  0);
        assertEq(usds.balanceOf(user), amount);
    }

    function test_migrateDAIToUSDS() public assertDebtStateDoesNotChange {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateDAIToUSDSTest(amount);
    }

    function testFuzz_migrateDAIToUSDS(uint256 amount) public assertDebtStateDoesNotChange {
        amount = _bound(amount, 0, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateDAIToUSDSTest(amount);
    }

    function testFuzz_migrateDAIToUSDS_upToWholeSupply(uint256 amount)
        public assertDebtStateDoesNotChange
    {
        amount = _bound(amount, 0, DAI_SUPPLY);

        deal(DAI, user, amount);  // Use `deal` to get a higher DAI amount

        _runMigrateDAIToUSDSTest(amount);
    }

}

contract MigrateDaiToSUsdsIntegrationTest is MigrationActionsIntegrationTestBase {

    // Starting balance of USDS in the SUSDS contract
    uint256 startingBalance = 1349.352634383042498711e18;

    function _runMigrateDAIToSUSDSTest(uint256 amount) internal {
        // Get the expected amount to be sucked from the vat on `drip` in deposit call in sUSDS
        uint256 snapshot    = vm.snapshot();
        uint256 usdsBalance = usds.balanceOf(SUSDS);
        susds.drip();
        uint256 usdsDripAmount = usds.balanceOf(SUSDS) - usdsBalance;
        vm.revertTo(snapshot);

        dai.approve(address(actions), amount);

        assertEq(dai.balanceOf(user),   amount);
        assertEq(usds.balanceOf(SUSDS), startingBalance);

        assertEq(susds.convertToAssets(susds.balanceOf(user)), 0);

        uint256 debt      = vat.debt();
        uint256 sumSupply = _getSumSupply();

        actions.migrateDAIToSUSDS(user, amount);

        assertEq(dai.balanceOf(user),   0);
        assertEq(usds.balanceOf(SUSDS), startingBalance + usdsDripAmount + amount);

        // Assert within 2 wei diff, rounding down
        assertLe(amount - susds.convertToAssets(susds.balanceOf(user)), 2);

        assertEq(vat.debt(), debt + usdsDripAmount * 1e27);

        // Two rounding events in usds.totalAssets()
        assertApproxEqAbs(_getSumSupply(), sumSupply, 2);
    }

    function test_migrateDAIToSUSDS() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateDAIToSUSDSTest(amount);
    }

    function testFuzz_migrateDAIToSUSDS(uint256 amount) public {
        amount = _bound(amount, 0, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateDAIToSUSDSTest(amount);
    }

    function testFuzz_migrateDAIToSUSDS_upToWholeSupply(uint256 amount) public {
        amount = _bound(amount, 0, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateDAIToSUSDSTest(amount);
    }

}

contract MigrateSDaiAssetsToUsdsIntegrationTest is MigrationActionsIntegrationTestBase {

    function _runMigrateSDAIAssetsToUSDSTest(uint256 amount) internal {
        // Deposit into sDAI
        dai.approve(SDAI, amount);
        sdai.deposit(amount, address(this));

        // Warp to accrue value in both sDAI and sUSDS after drip is called on sDAI deposit
        skip(2 hours);

        // Get the expected amount to be sucked from the vat on `drip` in withdraw call in sDAI
        uint256 snapshot      = vm.snapshot();
        uint256 preDripPotDai = vat.dai(POT);
        pot.drip();
        uint256 daiDripAmount = vat.dai(POT) - preDripPotDai;
        vm.revertTo(snapshot);

        sdai.approve(address(actions), sdai.convertToShares(amount) + 1);  // Approve corresponding shares

        // Cache all starting state
        uint256 userAssets = sdai.convertToAssets(sdai.balanceOf(user));
        uint256 debt       = vat.debt();
        uint256 sumSupply  = _getSumSupply();

        actions.migrateSDAIAssetsToUSDS(user, amount);

        uint256 newUserAssets = sdai.convertToAssets(sdai.balanceOf(user));

        assertApproxEqAbs(usds.balanceOf(user), amount,               0);  // User gets specified amount of USDS (exact)
        assertApproxEqAbs(newUserAssets,        userAssets - amount,  2);  // Users sDAI position reflected (conversion rounding x2)
        assertApproxEqAbs(vat.debt(),           debt + daiDripAmount, 0);  // Vat accounting constant outside of sDAI accrual (exact)
        assertApproxEqAbs(_getSumSupply(),      sumSupply,            2);  // Total supply of ERC-20 assets constant (conversion rounding x2)
    }

    function test_migrateSDAIAssetsToUSDS() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateSDAIAssetsToUSDSTest(amount);
    }

    function testFuzz_migrateSDAIAssetsToUSDS(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateSDAIAssetsToUSDSTest(amount);
    }

    function testFuzz_migrateSDAIAssetsToUSDS_upToWholeSupply(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateSDAIAssetsToUSDSTest(amount);
    }

}

contract MigrateSDaiSharesToUsdsIntegrationTest is MigrationActionsIntegrationTestBase {

    function _runMigrateSDAISharesToUSDSTest(uint256 amount) internal {
        // Deposit into sDAI
        dai.approve(SDAI, amount);
        sdai.deposit(amount, address(this));

        // Warp to accrue value in both sDAI and sUSDS after drip is called on sDAI deposit
        skip(2 hours);

        // Get the expected amount to be sucked from the vat on `drip` in withdraw call in sDAI
        uint256 snapshot      = vm.snapshot();
        uint256 preDripPotDai = vat.dai(POT);
        pot.drip();
        uint256 daiDripAmount = vat.dai(POT) - preDripPotDai;
        vm.revertTo(snapshot);

        uint256 userAssets = sdai.convertToAssets(sdai.balanceOf(user));

        sdai.approve(address(actions), sdai.balanceOf(user));

        // Cache all starting state
        uint256 debt      = vat.debt();
        uint256 sumSupply = _getSumSupply();

        actions.migrateSDAISharesToUSDS(user, sdai.balanceOf(user));

        uint256 newUserAssets = sdai.convertToAssets(sdai.balanceOf(user));

        assertApproxEqAbs(usds.balanceOf(user), userAssets,           0);  // User gets specified amount of USDS (exact)
        assertApproxEqAbs(newUserAssets,        0,                    1);  // Users sDAI position reflected (conversion rounding x1)
        assertApproxEqAbs(vat.debt(),           debt + daiDripAmount, 0);  // Vat accounting constant outside of sDAI accrual (exact)
        assertApproxEqAbs(_getSumSupply(),      sumSupply,            2);  // Total supply of ERC-20 assets constant (conversion rounding x2)
    }

    function test_migrateSDAISharesToUSDS() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateSDAISharesToUSDSTest(amount);
    }

    function testFuzz_migrateSDAISharesToUSDS(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateSDAISharesToUSDSTest(amount);
    }

    function testFuzz_migrateSDAISharesToUSDS_upToWholeSupply(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateSDAISharesToUSDSTest(amount);
    }

}

contract MigrateSDaiAssetsToSUsdsIntegrationTest is MigrationActionsIntegrationTestBase {

    function _runMigrateSDAIAssetsToSUSDSTest(uint256 amount) internal {
        // Deposit into sDAI
        dai.approve(SDAI, amount);
        sdai.deposit(amount, address(this));

        // Warp to accrue value in both sDAI and sUSDS after drip is called on sDAI deposit
        skip(2 hours);

        // Get the expected amount to be sucked from the vat on `drip` in withdraw
        // and deposit calls in sDAI and sUSDS respectively
        uint256 snapshot      = vm.snapshot();
        uint256 usdsBalance   = usds.balanceOf(SUSDS);
        uint256 preDripPotDai = vat.dai(POT);
        susds.drip();
        pot.drip();
        uint256 usdsDripAmount = usds.balanceOf(SUSDS) - usdsBalance;
        uint256 daiDripAmount  = vat.dai(POT) - preDripPotDai;
        vm.revertTo(snapshot);

        sdai.approve(address(actions), amount);

        // Cache all starting state
        uint256 userSDaiAssets = sdai.convertToAssets(sdai.balanceOf(user));
        uint256 debt           = vat.debt();
        uint256 sumSupply      = _getSumSupply();

        actions.migrateSDAIAssetsToSUSDS(user, amount);

        uint256 newUserSDaiAssets = sdai.convertToAssets(sdai.balanceOf(user));
        uint256 userSUsdsAssets   = susds.convertToAssets(susds.balanceOf(user));
        uint256 expectedDebt      = debt + daiDripAmount + usdsDripAmount * 1e27;

        assertApproxEqAbs(userSUsdsAssets,   amount,                  2);  // User gets specified amount of sUSDS (conversion rounding x2)
        assertApproxEqAbs(newUserSDaiAssets, userSDaiAssets - amount, 2);  // Users sDAI position reflected (conversion rounding x2)
        assertApproxEqAbs(vat.debt(),        expectedDebt,            0);  // Vat accounting constant outside of sDAI and nUSDS accrual (exact)]
        assertApproxEqAbs(_getSumSupply(),   sumSupply,               4);  // Total supply of ERC-20 assets constant (conversion rounding x4, totalAssets twice)
    }

    function test_migrateSDAIAssetsToSUSDS() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateSDAIAssetsToSUSDSTest(amount);
    }

    function testFuzz_migrateSDAIAssetsToSUSDS(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = bound(amount, 1e18, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateSDAIAssetsToSUSDSTest(amount);
    }

    function testFuzz_migrateSDAIAssetsToSUSDS_upToWholeSupply(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateSDAIAssetsToSUSDSTest(amount);
    }

}

contract MigrateSDaiSharesToSUsdsIntegrationTest is MigrationActionsIntegrationTestBase {

    function _runMigrateSDAISharesToSUSDSTest(uint256 amount) internal {
        // Deposit into sDAI
        dai.approve(SDAI, amount);
        sdai.deposit(amount, address(this));

        // Warp to accrue value in both sDAI and sUSDS after drip is called on sDAI deposit
        skip(2 hours);

        // Get the expected amount to be sucked from the vat on `drip` in withdraw
        // and deposit calls in sDAI and sUSDS respectively
        uint256 snapshot      = vm.snapshot();
        uint256 usdsBalance   = usds.balanceOf(SUSDS);
        uint256 preDripPotDai = vat.dai(POT);
        susds.drip();
        pot.drip();
        uint256 usdsDripAmount = usds.balanceOf(SUSDS) - usdsBalance;
        uint256 daiDripAmount  = vat.dai(POT) - preDripPotDai;
        vm.revertTo(snapshot);

        uint256 userSDaiAssets = sdai.convertToAssets(sdai.balanceOf(user));

        sdai.approve(address(actions), userSDaiAssets);

        // Cache all starting state
        uint256 debt      = vat.debt();
        uint256 sumSupply = _getSumSupply();

        actions.migrateSDAISharesToSUSDS(user, sdai.balanceOf(user));

        uint256 newUserSDaiAssets = sdai.convertToAssets(sdai.balanceOf(user));
        uint256 userSUsdsAssets   = susds.convertToAssets(susds.balanceOf(user));
        uint256 expectedDebt      = debt + daiDripAmount + usdsDripAmount * 1e27;

        assertApproxEqAbs(userSUsdsAssets,   userSDaiAssets, 2);  // User gets specified amount of sUSDS (conversion rounding x1)
        assertApproxEqAbs(newUserSDaiAssets, 0,              2);  // Users sDAI position reflected (conversion rounding x2)
        assertApproxEqAbs(vat.debt(),        expectedDebt,   0);  // Vat accounting constant outside of sDAI and nUSDS accrual (exact)]
        assertApproxEqAbs(_getSumSupply(),   sumSupply,      4);  // Total supply of ERC-20 assets constant (conversion rounding x4, totalAssets twice)
    }

    function test_migrateSDAISharesToSUSDS() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateSDAISharesToSUSDSTest(amount);
    }

    function testFuzz_migrateSDAISharesToSUSDS(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = bound(amount, 1e18, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateSDAISharesToSUSDSTest(amount);
    }

    function testFuzz_migrateSDAISharesToSUSDS_upToWholeSupply(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateSDAISharesToSUSDSTest(amount);
    }

}


contract DowngradeUSDSToDAIIntegrationTest is MigrationActionsIntegrationTestBase {

    function _getUsds(address receiver, uint256 amount) internal {
        vm.prank(DAI_WHALE);
        dai.transfer(address(this), amount);

        dai.approve(address(actions), amount);
        actions.migrateDAIToUSDS(receiver, amount);
    }

    function _runDowngradeUSDSToDAITest(uint256 amount) internal {
        usds.approve(address(actions), amount);

        assertEq(usds.balanceOf(user), amount);
        assertEq(dai.balanceOf(user),  0);

        actions.downgradeUSDSToDAI(user, amount);

        assertEq(usds.balanceOf(user), 0);
        assertEq(dai.balanceOf(user),  amount);
    }

    function test_downgradeUSDSToDAI() public assertDebtStateDoesNotChange {
        uint256 amount = 1000 ether;

        _getUsds(user, amount);

        _runDowngradeUSDSToDAITest(amount);
    }

    function testFuzz_downgradeUSDSToDAI(uint256 amount) public assertDebtStateDoesNotChange {
        amount = _bound(amount, 0, dai.balanceOf(DAI_WHALE));

        _getUsds(user, amount);

        _runDowngradeUSDSToDAITest(amount);
    }

    function testFuzz_downgradeUSDSToDAI_upToWholeSupply(uint256 amount)
        public assertDebtStateDoesNotChange
    {
        amount = _bound(amount, 0, DAI_SUPPLY);

        deal(DAI, user, amount);  // Use `deal` to get a higher DAI amount

        dai.approve(address(actions), amount);
        actions.migrateDAIToUSDS(address(this), amount);

        _runDowngradeUSDSToDAITest(amount);
    }

}
