// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

// Mock of lite psm: https://github.com/makerdao/dss-lite-psm/blob/374bb08b09a3f4798858fd841bab8e79719266c8/src/DssLitePsm.sol
contract PSMVariant2Mock {

    MockERC20 public dai;
    MockERC20 public gem;

    uint256 public tin;
    uint256 public tout;

    uint256 private to18ConversionFactor;

    constructor(MockERC20 _dai, MockERC20 _gem) {
        dai = _dai;
        gem = _gem;

        to18ConversionFactor = 10 ** (18 - gem.decimals());
    }

    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad) {
        daiOutWad = gemAmt * to18ConversionFactor;
        uint256 fee;
        if (tin > 0) {
            fee = daiOutWad * tin / 1e18;
            unchecked {
                daiOutWad -= fee;
            }
        }
        gem.transferFrom(msg.sender, address(this), gemAmt);
        dai.transfer(usr, daiOutWad);
    }

    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad) {
        daiInWad = gemAmt * to18ConversionFactor;
        uint256 fee;
        if (tout > 0) {
            fee = daiInWad * tout / 1e18;
            daiInWad += fee;
        }
        dai.transferFrom(msg.sender, address(this), daiInWad);
        gem.transfer(usr, gemAmt);
    }

    function __setTin(uint256 _tin) external {
        tin = _tin;
    }

    function __setTout(uint256 _tout) external {
        tout = _tout;
    }

    function gemJoin() external view returns (address) {
        return address(this);
    }

}
