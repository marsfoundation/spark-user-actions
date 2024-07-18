// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

interface VatLike {

    function debt() external view returns (uint256);
}

contract MigrationActionsIntegrationTestBase is Test {

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;

    function setUp() public virtual {
        vm.createSelectFork(
            "https://virtual.mainnet.rpc.tenderly.co/cc1fdd8b-c3a7-4092-8dc4-b07fbac3a5ba",
            19871405
        );
    }

    function test_firstTest() public {

    }


}
