// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import "forge-std/Test.sol";

import { MigrationActions } from "src/MigrationActions.sol";

interface VatLike {

    function debt() external view returns (uint256);

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

    VatLike vat = VatLike(VAT);

    MigrationActions actions;

    function setUp() public virtual {
        vm.createSelectFork(
            "https://virtual.mainnet.rpc.tenderly.co/cc1fdd8b-c3a7-4092-8dc4-b07fbac3a5ba",
            19871405
        );

        actions = new MigrationActions(SDAI, SNST, DAI_JOIN, NST_JOIN);
    }

    function test_firstTest() public {
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.totalSupply(), DAI_SUPPLY);
        _getDai(address(this), 1000);
        assertEq(dai.balanceOf(address(this)), 1000);
        assertEq(dai.totalSupply(), DAI_SUPPLY);
    }

    // Using this instead of `deal` because totalSupply is important for this testing
    function _getDai(address receiver, uint256 amount) internal {
        vm.prank(DAI_WHALE);
        dai.transfer(receiver, amount);
    }

}
