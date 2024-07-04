// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

import { VatMock }     from "./mocks/VatMock.sol";
import { JoinMock }    from "./mocks/JoinMock.sol";
import { ERC4626Mock } from "./mocks/ERC4626Mock.sol";

import { MigrationActions } from "src/MigrationActions.sol";

abstract contract MigrationActionsBase is Test {

    MockERC20   public dai;
    ERC4626Mock public sdai;
    MockERC20   public nst;
    ERC4626Mock public snst;

    VatMock  public vat;
    JoinMock public daiJoin;
    JoinMock public nstJoin;

    MigrationActions public actions;

    address receiver = makeAddr("receiver");

    function setUp() public {
        dai  = new MockERC20("DAI", "DAI", 18);
        nst  = new MockERC20("NST", "NST", 18);
        sdai = new ERC4626Mock(dai, "sDAI", "sDAI", 18);
        snst = new ERC4626Mock(nst, "sNST", "sNST", 18);

        vat     = new VatMock();
        daiJoin = new JoinMock(vat, dai);
        nstJoin = new JoinMock(vat, nst);

        // Set the different exchange rates for different asset/share conversion
        sdai.__setShareConversionRate(2e18);
        snst.__setShareConversionRate(1.25e18);

        // Give some existing balance to represent existing ERC20s
        vat.__setDaibalance(address(daiJoin), 1_000_000e45);
        vat.__setDaibalance(address(nstJoin), 1_000_000e45);

        actions = new MigrationActions(
            address(sdai),
            address(snst),
            address(daiJoin),
            address(nstJoin)
        );
    }

}

contract MigrationActionsConstructorTests is MigrationActionsBase {

    function test_constructor() public {
        // For coverage
        actions = new MigrationActions(
            address(sdai),
            address(snst),
            address(daiJoin),
            address(nstJoin)
        );

        assertEq(address(actions.dai()),     address(dai));
        assertEq(address(actions.sdai()),    address(sdai));
        assertEq(address(actions.nst()),     address(nst));
        assertEq(address(actions.snst()),    address(snst));
        assertEq(address(actions.vat()),     address(vat));
        assertEq(address(actions.daiJoin()), address(daiJoin));
        assertEq(address(actions.nstJoin()), address(nstJoin));

        assertEq(dai.allowance(address(actions), address(daiJoin)), type(uint256).max);
        assertEq(nst.allowance(address(actions), address(nstJoin)), type(uint256).max);
        assertEq(nst.allowance(address(actions), address(snst)),    type(uint256).max);

        assertEq(vat.can(address(actions), address(daiJoin)), 1);
        assertEq(vat.can(address(actions), address(nstJoin)), 1);
    }

}

contract MigrationActionsMigrateDAIToNSTTests is MigrationActionsBase {

    function test_migrateDAIToNST_insufficientBalance_boundary() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToNST(receiver, 100e18);

        dai.mint(address(this), 1);

        actions.migrateDAIToNST(receiver, 100e18);
    }

    function test_migrateDAIToNST_insufficientApproval_boundary() public {
        dai.approve(address(actions), 100e18 - 1);
        dai.mint(address(this), 100e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToNST(receiver, 100e18);

        dai.approve(address(actions), 100e18);

        actions.migrateDAIToNST(receiver, 100e18);
    }

    function test_migrateDAIToNST() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18);

        assertEq(dai.balanceOf(address(this)), 100e18);
        assertEq(nst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),      0);
        assertEq(nst.balanceOf(receiver),      0);

        actions.migrateDAIToNST(receiver, 100e18);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(nst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),      0);
        assertEq(nst.balanceOf(receiver),      100e18);
    }

}

contract MigrationActionsMigrateDAIToSNSTTests is MigrationActionsBase {

    function test_migrateDAIToSNST_insufficientBalance_boundary() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToSNST(receiver, 100e18);

        dai.mint(address(this), 1);

        actions.migrateDAIToSNST(receiver, 100e18);
    }

    function test_migrateDAIToSNST_insufficientApproval_boundary() public {
        dai.approve(address(actions), 100e18 - 1);
        dai.mint(address(this), 100e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToSNST(receiver, 100e18);

        dai.approve(address(actions), 100e18);

        actions.migrateDAIToSNST(receiver, 100e18);
    }

    function test_migrateDAIToSNST() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18);

        assertEq(dai.balanceOf(address(this)),  100e18);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(snst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(snst.balanceOf(receiver),      0);

        uint256 sharesOut = actions.migrateDAIToSNST(receiver, 100e18);

        assertEq(sharesOut,                     80e18);
        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(snst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(snst.balanceOf(receiver),      80e18);
    }

}

contract MigrationActionsMigrateSDAIAssetsToNSTTests is MigrationActionsBase {

    function test_migrateSDAIAssetsToNST_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToNST(receiver, 100e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAIAssetsToNST(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToNST_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToNST(receiver, 100e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAIAssetsToNST(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToNST() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 50e18);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(sdai.balanceOf(receiver),      0);

        actions.migrateSDAIAssetsToNST(receiver, 100e18);

        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       100e18);
        assertEq(sdai.balanceOf(receiver),      0);
    }

}

contract MigrationActionsMigrateSDAISharesToNSTTests is MigrationActionsBase {

    function test_migrateSDAISharesToNST_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToNST(receiver, 50e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAISharesToNST(receiver, 50e18);
    }

    function test_migrateSDAISharesToNST_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToNST(receiver, 50e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAISharesToNST(receiver, 50e18);
    }

    function test_migrateSDAISharesToNST() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 50e18);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(sdai.balanceOf(receiver),      0);

        uint256 assetsOut = actions.migrateSDAISharesToNST(receiver, 50e18);

        assertEq(assetsOut,                     100e18);
        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       100e18);
        assertEq(sdai.balanceOf(receiver),      0);
    }

}

contract MigrationActionsMigrateSDAIAssetsToSNSTTests is MigrationActionsBase {

    function test_migrateSDAIAssetsToSNST_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToSNST(receiver, 100e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAIAssetsToSNST(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToSNST_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToSNST(receiver, 100e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAIAssetsToSNST(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToSNST() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 50e18);
        assertEq(snst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(sdai.balanceOf(receiver),      0);
        assertEq(snst.balanceOf(receiver),      0);

        uint256 sharesOut = actions.migrateSDAIAssetsToSNST(receiver, 100e18);

        assertEq(sharesOut,                     80e18);
        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 0);
        assertEq(snst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(sdai.balanceOf(receiver),      0);
        assertEq(snst.balanceOf(receiver),      80e18);
    }

}

contract MigrationActionsMigrateSDAISharesToSNSTTests is MigrationActionsBase {

    function test_migrateSDAISharesToSNST_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToSNST(receiver, 50e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAISharesToSNST(receiver, 50e18);
    }

    function test_migrateSDAISharesToSNST_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToSNST(receiver, 50e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAISharesToSNST(receiver, 50e18);
    }

    function test_migrateSDAISharesToSNST() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 50e18);
        assertEq(snst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(sdai.balanceOf(receiver),      0);
        assertEq(snst.balanceOf(receiver),      0);

        uint256 sharesOut = actions.migrateSDAISharesToSNST(receiver, 50e18);

        assertEq(sharesOut,                     80e18);
        assertEq(dai.balanceOf(address(this)),  0);
        assertEq(nst.balanceOf(address(this)),  0);
        assertEq(sdai.balanceOf(address(this)), 0);
        assertEq(snst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),       0);
        assertEq(nst.balanceOf(receiver),       0);
        assertEq(sdai.balanceOf(receiver),      0);
        assertEq(snst.balanceOf(receiver),      80e18);
    }

}

contract MigrationActionsDowngradeNSTToDAITests is MigrationActionsBase {

    function test_downgradeNSTToDAI_insufficientBalance_boundary() public {
        nst.approve(address(actions), 100e18);
        nst.mint(address(this), 100e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.downgradeNSTToDAI(receiver, 100e18);

        nst.mint(address(this), 1);

        actions.downgradeNSTToDAI(receiver, 100e18);
    }

    function test_downgradeNSTToDAI_insufficientApproval_boundary() public {
        nst.approve(address(actions), 100e18 - 1);
        nst.mint(address(this), 100e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.downgradeNSTToDAI(receiver, 100e18);

        nst.approve(address(actions), 100e18);

        actions.downgradeNSTToDAI(receiver, 100e18);
    }

    function test_downgradeNSTToDAI() public {
        nst.approve(address(actions), 100e18);
        nst.mint(address(this), 100e18);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(nst.balanceOf(address(this)), 100e18);
        assertEq(dai.balanceOf(receiver),      0);
        assertEq(nst.balanceOf(receiver),      0);

        actions.downgradeNSTToDAI(receiver, 100e18);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(nst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(receiver),      100e18);
        assertEq(nst.balanceOf(receiver),      0);
    }

}
