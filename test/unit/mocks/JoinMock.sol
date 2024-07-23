// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

import { VatMock } from "./VatMock.sol";

contract JoinMock {

    VatMock   public vat;
    MockERC20 public dai;

    constructor(VatMock _vat, MockERC20 _dai) {
        vat = _vat;
        dai = _dai;
    }

    function join(address usr, uint wad) external {
        vat.move(address(this), usr, wad * 1e27);
        dai.burn(msg.sender, wad);
    }

    function exit(address usr, uint wad) external {
        vat.move(msg.sender, address(this), wad * 1e27);
        dai.mint(usr, wad);
    }

}
