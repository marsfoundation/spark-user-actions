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
    MockERC20   public usds;
    ERC4626Mock public sdai;
    ERC4626Mock public susds;

    VatMock  public vat;
    JoinMock public daiJoin;
    JoinMock public usdsJoin;

    MigrationActions public actions;

    address receiver = makeAddr("receiver");

    function setUp() public {
        dai   = new MockERC20("DAI",  "DAI",  18);
        usds  = new MockERC20("USDS", "USDS", 18);
        sdai  = new ERC4626Mock(dai,  "sDAI",  "sDAI",  18);
        susds = new ERC4626Mock(usds, "sUSDS", "sUSDS", 18);

        vat      = new VatMock();
        daiJoin  = new JoinMock(vat, dai);
        usdsJoin = new JoinMock(vat, usds);

        // Set the different exchange rates for different asset/share conversion
        sdai.__setShareConversionRate(2e18);
        susds.__setShareConversionRate(1.25e18);

        // Give some existing balance to represent existing ERC20s
        vat.__setDaiBalance(address(daiJoin), 1_000_000e45);
        vat.__setDaiBalance(address(usdsJoin), 1_000_000e45);

        actions = new MigrationActions(
            address(sdai),
            address(susds),
            address(daiJoin),
            address(usdsJoin)
        );
    }

    function _assertBalances(
        address user,
        uint256 daiBalance,
        uint256 sdaiBalance,
        uint256 usdsBalance,
        uint256 susdsBalance
    ) internal view {
        assertEq(dai.balanceOf(user),  daiBalance);
        assertEq(sdai.balanceOf(user), sdaiBalance);
        assertEq(usds.balanceOf(user),  usdsBalance);
        assertEq(susds.balanceOf(user), susdsBalance);
    }

}

contract MigrationActionsConstructorTests is MigrationActionsBase {

    function test_constructor() public {
        // For coverage
        actions = new MigrationActions(
            address(sdai),
            address(susds),
            address(daiJoin),
            address(usdsJoin)
        );

        assertEq(address(actions.dai()),      address(dai));
        assertEq(address(actions.sdai()),     address(sdai));
        assertEq(address(actions.usds()),     address(usds));
        assertEq(address(actions.susds()),    address(susds));
        assertEq(address(actions.vat()),      address(vat));
        assertEq(address(actions.daiJoin()),  address(daiJoin));
        assertEq(address(actions.usdsJoin()), address(usdsJoin));

        assertEq(dai.allowance(address(actions),  address(daiJoin)),  type(uint256).max);
        assertEq(usds.allowance(address(actions), address(usdsJoin)), type(uint256).max);
        assertEq(usds.allowance(address(actions), address(susds)),    type(uint256).max);

        assertEq(vat.can(address(actions), address(daiJoin)),  1);
        assertEq(vat.can(address(actions), address(usdsJoin)), 1);
    }

}

contract MigrationActionsMigrateDAIToUSDSTests is MigrationActionsBase {

    function test_migrateDAIToUSDS_insufficientBalance_boundary() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToUSDS(receiver, 100e18);

        dai.mint(address(this), 1);

        actions.migrateDAIToUSDS(receiver, 100e18);
    }

    function test_migrateDAIToUSDS_insufficientApproval_boundary() public {
        dai.approve(address(actions), 100e18 - 1);
        dai.mint(address(this), 100e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToUSDS(receiver, 100e18);

        dai.approve(address(actions), 100e18);

        actions.migrateDAIToUSDS(receiver, 100e18);
    }

    function test_migrateDAIToUSDS_differentReceiver() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   100e18,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        actions.migrateDAIToUSDS(receiver, 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });
    }

    function test_migrateDAIToUSDS_sameReceiver() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   100e18,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        actions.migrateDAIToUSDS(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });
    }

}

contract MigrationActionsMigrateDAIToSUSDSTests is MigrationActionsBase {

    function test_migrateDAIToSUSDS_insufficientBalance_boundary() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToSUSDS(receiver, 100e18);

        dai.mint(address(this), 1);

        actions.migrateDAIToSUSDS(receiver, 100e18);
    }

    function test_migrateDAIToSUSDS_insufficientApproval_boundary() public {
        dai.approve(address(actions), 100e18 - 1);
        dai.mint(address(this), 100e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateDAIToSUSDS(receiver, 100e18);

        dai.approve(address(actions), 100e18);

        actions.migrateDAIToSUSDS(receiver, 100e18);
    }

    function test_migrateDAIToSUSDS_differentReceiver() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   100e18,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 sharesOut = actions.migrateDAIToSUSDS(receiver, 100e18);
        assertEq(sharesOut, 80e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 80e18
        });
    }

    function test_migrateDAIToSUSDS_sameReceiver() public {
        dai.approve(address(actions), 100e18);
        dai.mint(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   100e18,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 sharesOut = actions.migrateDAIToSUSDS(address(this), 100e18);
        assertEq(sharesOut, 80e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 80e18
        });
    }

}

contract MigrationActionsMigrateSDAIAssetsToUSDSTests is MigrationActionsBase {

    function test_migrateSDAIAssetsToUSDS_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToUSDS(receiver, 100e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAIAssetsToUSDS(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToUSDS_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToUSDS(receiver, 100e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAIAssetsToUSDS(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToUSDS_differentReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        actions.migrateSDAIAssetsToUSDS(receiver, 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });
    }

    function test_migrateSDAIAssetsToUSDS_sameReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });

        actions.migrateSDAIAssetsToUSDS(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });
    }

}

contract MigrationActionsMigrateSDAISharesToUSDSTests is MigrationActionsBase {

    function test_migrateSDAISharesToUSDS_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToUSDS(receiver, 50e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAISharesToUSDS(receiver, 50e18);
    }

    function test_migrateSDAISharesToUSDS_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToUSDS(receiver, 50e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAISharesToUSDS(receiver, 50e18);
    }

    function test_migrateSDAISharesToUSDS_differentReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 assetsOut = actions.migrateSDAISharesToUSDS(receiver, 50e18);
        assertEq(assetsOut, 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });
    }

    function test_migrateSDAISharesToUSDS_sameReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 assetsOut = actions.migrateSDAISharesToUSDS(address(this), 50e18);
        assertEq(assetsOut, 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });
    }

}

contract MigrationActionsMigrateSDAIAssetsToSUSDSTests is MigrationActionsBase {

    function test_migrateSDAIAssetsToSUSDS_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToSUSDS(receiver, 100e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAIAssetsToSUSDS(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToSUSDS_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAIAssetsToSUSDS(receiver, 100e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAIAssetsToSUSDS(receiver, 100e18);
    }

    function test_migrateSDAIAssetsToSUSDS_differentReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 sharesOut = actions.migrateSDAIAssetsToSUSDS(receiver, 100e18);
        assertEq(sharesOut, 80e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 80e18
        });
    }

    function test_migrateSDAIAssetsToSUSDS_sameReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 sharesOut = actions.migrateSDAIAssetsToSUSDS(address(this), 100e18);
        assertEq(sharesOut, 80e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 80e18
        });
    }

}

contract MigrationActionsMigrateSDAISharesToSUSDSTests is MigrationActionsBase {

    function test_migrateSDAISharesToSUSDS_insufficientBalance_boundary() public {
        dai.mint(address(sdai), 100e18);  // Ensure dai is available in sdai
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToSUSDS(receiver, 50e18);

        sdai.mint(address(this), 1);

        actions.migrateSDAISharesToSUSDS(receiver, 50e18);
    }

    function test_migrateSDAISharesToSUSDS_insufficientApproval_boundary() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18 - 1);
        sdai.mint(address(this), 50e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.migrateSDAISharesToSUSDS(receiver, 50e18);

        sdai.approve(address(actions), 50e18);

        actions.migrateSDAISharesToSUSDS(receiver, 50e18);
    }

    function test_migrateSDAISharesToSUSDS_differentReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 sharesOut = actions.migrateSDAISharesToSUSDS(receiver, 50e18);
        assertEq(sharesOut, 80e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 80e18
        });
    }

    function test_migrateSDAISharesToSUSDS_sameReceiver() public {
        dai.mint(address(sdai), 100e18);
        sdai.approve(address(actions), 50e18);
        sdai.mint(address(this), 50e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  50e18,
            usdsBalance:  0,
            susdsBalance: 0
        });

        uint256 sharesOut = actions.migrateSDAISharesToSUSDS(address(this), 50e18);
        assertEq(sharesOut, 80e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 80e18
        });
    }

}

contract MigrationActionsDowngradeUSDSToDAITests is MigrationActionsBase {

    function test_downgradeUSDSToDAI_insufficientBalance_boundary() public {
        usds.approve(address(actions), 100e18);
        usds.mint(address(this), 100e18 - 1);

        vm.expectRevert(stdError.arithmeticError);
        actions.downgradeUSDSToDAI(receiver, 100e18);

        usds.mint(address(this), 1);

        actions.downgradeUSDSToDAI(receiver, 100e18);
    }

    function test_downgradeUSDSToDAI_insufficientApproval_boundary() public {
        usds.approve(address(actions), 100e18 - 1);
        usds.mint(address(this), 100e18);

        vm.expectRevert(stdError.arithmeticError);
        actions.downgradeUSDSToDAI(receiver, 100e18);

        usds.approve(address(actions), 100e18);

        actions.downgradeUSDSToDAI(receiver, 100e18);
    }

    function test_downgradeUSDSToDAI_differentReceiver() public {
        usds.approve(address(actions), 100e18);
        usds.mint(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });

        actions.downgradeUSDSToDAI(receiver, 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
        _assertBalances({
            user:         receiver,
            daiBalance:   100e18,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
    }

    function test_downgradeUSDSToDAI_sameReceiver() public {
        usds.approve(address(actions), 100e18);
        usds.mint(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   0,
            sdaiBalance:  0,
            usdsBalance:  100e18,
            susdsBalance: 0
        });

        actions.downgradeUSDSToDAI(address(this), 100e18);

        _assertBalances({
            user:         address(this),
            daiBalance:   100e18,
            sdaiBalance:  0,
            usdsBalance:  0,
            susdsBalance: 0
        });
    }

}
