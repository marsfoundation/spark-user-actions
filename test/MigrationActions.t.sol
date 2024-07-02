// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

import { VatMock }     from "./mocks/VatMock.sol";
import { JoinMock }    from "./mocks/JoinMock.sol";
import { ERC4626Mock } from "./mocks/ERC4626Mock.sol";

import { MigrationActions } from "src/MigrationActions.sol";

contract MigrationActionsTest is Test {

    MockERC20   public dai;
    MockERC20   public nst;
    ERC4626Mock public sdai;
    ERC4626Mock public snst;

    VatMock  public vat;
    JoinMock public daiJoin;
    JoinMock public nstJoin;

    MigrationActions public actions;

    function setUp() public {
        dai  = new MockERC20("DAI", "DAI", 18);
        nst  = new MockERC20("NST", "NST", 18);
        sdai = new ERC4626Mock(dai, "sDAI", "sDAI", 18);
        snst = new ERC4626Mock(nst, "sNST", "sNST", 18);

        vat     = new VatMock();
        daiJoin = new JoinMock(vat, dai);
        nstJoin = new JoinMock(vat, nst);

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

    function test_migrateDAIToNST() public {
        uint256 amount = 100e18;
        dai.mint(address(this), amount);
        dai.approve(address(actions), amount);
        actions.migrateDAIToNST(address(this), amount);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(nst.balanceOf(address(this)), amount);
    }

    function test_downgradeNSTToDAI() public {
        uint256 amount = 100e18;
        nst.mint(address(this), amount);
        nst.approve(address(actions), amount);
        actions.downgradeNSTToDAI(address(this), amount);
        assertEq(nst.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), amount);
    }

}
