// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { MigrationActions } from "src/MigrationActions.sol";

interface PotLike {
    function drip() external returns (uint256);
    function pie(address) external view returns(uint256);
}

interface VatLike {
    function dai(address) external view returns (uint256);
    function debt() external view returns (uint256);
}

interface SavingsTokenLike is IERC20 {
    function convertToAssets(uint256 shares) external view returns(uint256 assets);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function drip() external;
    function totalAssets() external view returns(uint256);
}

contract MigrationActionsIntegrationTestBase is Test {

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant NST  = 0x798f111c92E38F102931F34D1e0ea7e671BDBE31;
    address constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant SNST = 0xeA8AE08513f8230cAA8d031D28cB4Ac8CE720c68;

    address constant DAI_JOIN = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    address constant NST_JOIN = 0xbc71F5687CFD36f64Ae6B4549186EE3A6eE259a4;
    address constant POT      = 0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7;
    address constant VAT      = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;

    address constant DAI_WHALE = 0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B;

    uint256 constant DAI_SUPPLY = 3_073_155_804.411575584359575254e18;

    IERC20 constant dai = IERC20(DAI);
    IERC20 constant nst = IERC20(NST);

    SavingsTokenLike constant sdai = SavingsTokenLike(SDAI);
    SavingsTokenLike constant snst = SavingsTokenLike(SNST);

    PotLike constant pot = PotLike(POT);
    VatLike constant vat = VatLike(VAT);

    MigrationActions actions;

    address user = address(this);

    function setUp() public virtual {
        vm.createSelectFork(
            "https://virtual.mainnet.rpc.tenderly.co/cc1fdd8b-c3a7-4092-8dc4-b07fbac3a5ba",
            19871405  // July 18, 2024
        );

        actions = new MigrationActions(SDAI, SNST, DAI_JOIN, NST_JOIN);
    }

    modifier assertDebtStateDoesNotChange() {
        // Assert that the total internal debt does not change, as well as the sum of the
        // ERC20 supply of DAI and NST
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
        return dai.totalSupply() + nst.totalSupply();  // TODO: Update to sNST and sDAI totalAssets
    }

}

contract MigrateDaiToNstIntegrationTest is MigrationActionsIntegrationTestBase {

    function _runMigrateDAIToNSTTest(uint256 amount) internal {
        dai.approve(address(actions), amount);

        assertEq(dai.balanceOf(user), amount);
        assertEq(nst.balanceOf(user), 0);

        actions.migrateDAIToNST(user, amount);

        assertEq(dai.balanceOf(user), 0);
        assertEq(nst.balanceOf(user), amount);
    }

    function test_migrateDAIToNST() public assertDebtStateDoesNotChange {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateDAIToNSTTest(amount);
    }

    function testFuzz_migrateDAIToNST(uint256 amount) public assertDebtStateDoesNotChange {
        amount = _bound(amount, 0, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateDAIToNSTTest(amount);
    }

    function testFuzz_migrateDAIToNST_upToWholeSupply(uint256 amount)
        public assertDebtStateDoesNotChange
    {
        amount = _bound(amount, 0, DAI_SUPPLY);

        deal(DAI, user, amount);  // Use `deal` to get a higher DAI amount

        _runMigrateDAIToNSTTest(amount);
    }

}

contract MigrateDaiToSNstIntegrationTest is MigrationActionsIntegrationTestBase {

    // Starting balance of NST in the SNST contract
    uint256 startingBalance = 1051.297887154176590368e18;

    function _runMigrateDAIToSNSTTest(uint256 amount) internal {
        // Get the expected amount to be sucked from the vat on `drip` in deposit call in sNST
        uint256 snapshot = vm.snapshot();

        uint256 nstBalance = nst.balanceOf(SNST);
        snst.drip();
        uint256 nstDripAmount = nst.balanceOf(SNST) - nstBalance;

        vm.revertTo(snapshot);

        dai.approve(address(actions), amount);

        assertEq(dai.balanceOf(user), amount);
        assertEq(nst.balanceOf(SNST), startingBalance);

        assertEq(snst.convertToAssets(snst.balanceOf(user)), 0);

        uint256 debt      = vat.debt();
        uint256 sumSupply = _getSumSupply();

        actions.migrateDAIToSNST(user, amount);

        assertEq(dai.balanceOf(user), 0);
        assertEq(nst.balanceOf(SNST), startingBalance + nstDripAmount + amount);

        // Assert within 2 wei diff, rounding down
        assertLe(amount - snst.convertToAssets(snst.balanceOf(user)), 2);

        assertEq(vat.debt(),      debt + nstDripAmount * 1e27);
        assertEq(_getSumSupply(), sumSupply + nstDripAmount);
    }

    function test_migrateDAIToSNST() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateDAIToSNSTTest(amount);
    }

    function testFuzz_migrateDAIToSNST(uint256 amount) public {
        amount = _bound(amount, 0, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateDAIToSNSTTest(amount);
    }

    function testFuzz_migrateDAIToSNST_upToWholeSupply(uint256 amount) public {
        amount = _bound(amount, 0, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateDAIToSNSTTest(amount);
    }

}

contract MigrateSDaiAssetsToNstIntegrationTest is MigrationActionsIntegrationTestBase {

    function _runMigrateSDAIAssetsToNSTTest(uint256 amount) internal {
        // Deposit into sDAI
        dai.approve(SDAI, amount);
        sdai.deposit(amount, address(this));

        // Warp to accrue value in both sDAI adn sNST after drip is called on sDAI deposit
        skip(2 hours);

        // Get the expected amount to be sucked from the vat on `drip` in withdraw call in sDAI
        uint256 snapshot = vm.snapshot();
        uint256 preDripPotDai = vat.dai(POT);
        pot.drip();
        uint256 daiDripAmount = vat.dai(POT) - preDripPotDai;
        vm.revertTo(snapshot);

        sdai.approve(address(actions), amount);

        // Cache all starting state
        uint256 userAssets = sdai.convertToAssets(sdai.balanceOf(user));
        uint256 debt       = vat.debt();
        uint256 sumSupply  = sdai.totalAssets() + nst.totalSupply() + dai.totalSupply();

        actions.migrateSDAIAssetsToNST(user, amount);

        uint256 newUserAssets = sdai.convertToAssets(sdai.balanceOf(user));
        uint256 newSumSupply  = sdai.totalAssets() + nst.totalSupply() + dai.totalSupply();

        assertApproxEqAbs(nst.balanceOf(user), amount,               0);  // User gets specified amount of NST (exact)
        assertApproxEqAbs(newUserAssets,       userAssets - amount,  2);  // Users sDAI position reflected (conversion rounding x2)
        assertApproxEqAbs(vat.debt(),          debt + daiDripAmount, 0);  // Vat accounting constant outside of sDAI accrual (exact)
        assertApproxEqAbs(newSumSupply,        sumSupply,            2);  // Total supply of ERC-20 assets constant (conversion rounding x2)
    }

    function test_migrateSDAIAssetsToNST() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateSDAIAssetsToNSTTest(amount);
    }

    function testFuzz_migrateSDAIAssetsToNST(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateSDAIAssetsToNSTTest(amount);
    }

    function testFuzz_migrateSDAIAssetsToNST_upToWholeSupply(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = _bound(amount, 1e18, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateSDAIAssetsToNSTTest(amount);
    }

}

// TODO: migrateSDAIAssetsToNST migrateSDAIAssetsToNST

contract MigrateSDaiAssetsToSNstIntegrationTest is MigrationActionsIntegrationTestBase {

    // Starting balance of NST in the SNST contract
    uint256 startingNstBalance = 1051.297887154176590368e18;

    uint256 startingPotDai = 2_158_688_889.647549145888863863451729044902322402389261760e45;

    function _runMigrateSDAIAssetsToSNSTTest(uint256 amount) internal {
        // Deposit into sDAI
        dai.approve(SDAI, amount);
        sdai.deposit(amount, address(this));

        // Warp to accrue value in both sDAI adn sNST after drip is called on sDAI deposit
        skip(2 hours);

        // Get the expected amount to be sucked from the vat on `drip` in withdraw
        // and deposit calls in sDAI and sNST respectively
        uint256 snapshot = vm.snapshot();

        uint256 nstBalance = nst.balanceOf(SNST);
        // uint256 potPie     = pot.pie(SDAI);  // TODO: Why is this different from sDai.totalAssets()?
        snst.drip();
        pot.drip();
        uint256 nstDripAmount = nst.balanceOf(SNST) - nstBalance;
        uint256 daiDripAmount = vat.dai(POT) - startingPotDai;
        // uint256 sDaiDripAmount = pot.pie(SDAI) - potPie;

        vm.revertTo(snapshot);

        // assertEq(snst.convertToAssets(snst.balanceOf(user)), 0);

        // Cache all starting state
        uint256 debt = vat.debt();
        // uint256 sDaiDaiBalance = pot.pie(SDAI);  TODO: Bring back
        // uint256 totalAssets    = sdai.totalAssets();
        // uint256 sumSupply      = dai.totalSupply() + totalAssets + nst.totalSupply();
        // uint256 userAssets     = sdai.convertToAssets(sdai.balanceOf(user));

        sdai.approve(address(actions), amount);

        actions.migrateSDAIAssetsToSNST(user, amount);

        // assertLe((userAssets - amount) - sdai.convertToAssets(sdai.balanceOf(user)), 2);

        // 2 wei tolerance rounding down
        // assertLe(amount - snst.convertToAssets(snst.balanceOf(user)), 2);

        // assertEq(pot.pie(SDAI), sDaiDaiBalance + sDaiDripAmount - amount);  TODO: Figure out how to add back

        // Assert equal within 2 wei diff, rounding down
        // assertLe((totalAssets        + sDaiDripAmount - amount) - sdai.totalAssets(),  2);
        // assertLe((startingNstBalance + nstDripAmount  + amount) - nst.balanceOf(SNST), 2);

        uint256 diff = (debt + nstDripAmount * 1e27 + daiDripAmount) - vat.debt();

        console.log("diff            ", diff);
        console.log("diff (wad)      ", diff / 1e27);
        console.log("amount deposited", amount);
        console.log("");
        console.log("debt         ", debt);
        console.log("vat.debt     ", vat.debt());
        console.log("nstDripAmount", nstDripAmount * 1e27);
        console.log("daiDripAmount", daiDripAmount);

        // [LOOK HERE] Equality isn't satisfied
        assertEq(vat.debt(), debt + nstDripAmount * 1e27 + daiDripAmount);

        // // TODO: Update this to factor in pot.pie
        // assertEq(
        //     dai.totalSupply() + sdai.totalAssets() + nst.totalSupply(),
        //     sumSupply + sDaiDripAmount + nstDripAmount
        // );
    }

    function test_migrateSDAIAssetsToSNST_test1() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateSDAIAssetsToSNSTTest(amount);
    }

    function test_migrateSDAIAssetsToSNST_test2() public {
        uint256 amount = 1001 ether;

        _getDai(user, amount);

        _runMigrateSDAIAssetsToSNSTTest(amount);
    }

    function testFuzz_migrateSDAIAssetsToSNST(uint256 amount) public {
        // Add lower bound to minimize issues from rounding down for assets deposited
        // then withdrawn - use enough value so accrual is more than 1 wei
        amount = bound(amount, 1e18, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateSDAIAssetsToSNSTTest(amount);
    }

    // function testFuzz_migrateDAIToSNST_upToWholeSupply(uint256 amount) public {
    //     amount = _bound(amount, 0, DAI_SUPPLY);

    //     deal(DAI, user, amount);

    //     _runMigrateSDAIAssetsToSNSTTest(amount);
    // }

}
