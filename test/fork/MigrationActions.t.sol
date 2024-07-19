// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { MigrationActions } from "src/MigrationActions.sol";

interface VatLike {
    function debt() external view returns (uint256);
}

interface SavingsTokenLike is IERC20 {
    function convertToAssets(uint256) external view returns(uint256);
    function drip() external;
}

contract MigrationActionsIntegrationTestBase is Test {

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant NST  = 0x798f111c92E38F102931F34D1e0ea7e671BDBE31;
    address constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant SNST = 0xeA8AE08513f8230cAA8d031D28cB4Ac8CE720c68;

    address constant DAI_JOIN = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    address constant NST_JOIN = 0xbc71F5687CFD36f64Ae6B4549186EE3A6eE259a4;
    address constant VAT      = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;

    address constant DAI_WHALE = 0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B;

    uint256 constant DAI_SUPPLY = 3_073_155_804.411575584359575254e18;

    IERC20 dai = IERC20(DAI);
    IERC20 nst = IERC20(NST);

    SavingsTokenLike sdai = SavingsTokenLike(SDAI);
    SavingsTokenLike snst = SavingsTokenLike(SNST);

    VatLike vat = VatLike(VAT);

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
        return dai.totalSupply() + nst.totalSupply();
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
        uint256 amount = _bound(amount, 0, dai.balanceOf(DAI_WHALE));

        _getDai(user, amount);

        _runMigrateDAIToNSTTest(amount);
    }

    function testFuzz_migrateDAIToNST_upToWholeSupply(uint256 amount)
        public assertDebtStateDoesNotChange
    {
        uint256 amount = _bound(amount, 0, DAI_SUPPLY);

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

        // Assert within 1 wei diff, rounding down
        assertLe(amount - snst.convertToAssets(snst.balanceOf(user)), 1);

        assertEq(vat.debt(),      debt + nstDripAmount * 1e27);
        assertEq(_getSumSupply(), sumSupply + nstDripAmount);
    }

    function test_migrateDAIToSNST() public {
        uint256 amount = 1000 ether;

        _getDai(user, amount);

        _runMigrateDAIToSNSTTest(amount);
    }

    function testFuzz_migrateDAIToSNST(uint256 amount) public {
        _getDai(user, amount);

        _runMigrateDAIToSNSTTest(amount);
    }

    function testFuzz_migrateDAIToSNST_upToWholeSupply(uint256 amount) public {
        uint256 amount = _bound(amount, 0, DAI_SUPPLY);

        deal(DAI, user, amount);

        _runMigrateDAIToSNSTTest(amount);
    }

}
