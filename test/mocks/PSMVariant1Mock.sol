// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

contract GemJoin {

    MockERC20 public gem;

    constructor(MockERC20 _gem) {
        gem = _gem;
    }

    function join(uint256 amount, address msgSender) external {
        gem.transferFrom(msgSender, address(this), amount);
    }

    function exit(address usr, uint256 amount) external {
        gem.transfer(usr, amount);
    }

}

contract PSMVariant1Mock {

    MockERC20 public dai;
    MockERC20 public gem;
    GemJoin   public gemJoin;

    uint256 public tin;
    uint256 public tout;

    uint256 private to18ConversionFactor;

    constructor(MockERC20 _dai, MockERC20 _gem) {
        dai = _dai;
        gem = _gem;
        
        gemJoin = new GemJoin(gem);

        to18ConversionFactor = 10 ** (18 - gem.decimals());
    }

    function sellGem(address usr, uint256 gemAmt) external {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        uint256 fee = gemAmt18 * tin / 1e18;
        uint256 daiAmt = gemAmt18 - fee;
        dai.mint(usr, daiAmt);
        gemJoin.join(gemAmt, msg.sender);
    }

    function buyGem(address usr, uint256 gemAmt) external {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        uint256 fee = gemAmt18 * tout / 1e18;
        uint256 daiAmt = gemAmt18 + fee;
        dai.burn(msg.sender, daiAmt);
        gemJoin.exit(usr, gemAmt);
    }

    function __setTin(uint256 _tin) external {
        tin = _tin;
    }

    function __setTout(uint256 _tout) external {
        tout = _tout;
    }

}
