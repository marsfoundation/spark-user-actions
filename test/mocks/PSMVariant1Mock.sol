// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

contract GemJoin {

    address public gem;

    constructor(address _gem) {
        gem = _gem;
    }

    function join(uint256 amount, address msgSender) external {

    }

}

contract PSMVariant1Mock {

    address public dai;
    address public gem;

    uint256 public tin;
    uint256 public tout;

    uint256 private to18ConversionFactor;

    constructor(ERC20 _dai, ERC20 _gem) {
        dai = _dai;
        gem = _gem;

        to18ConversionFactor = 10 ** (18 - IERC20(gem).decimals());
    }

    function sellGem(address usr, uint256 gemAmt) external {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        uint256 fee = gemAmt18 * tin / 1e18;
        uint256 daiAmt = gemAmt18 - fee;
        dai.mint(usr, daiAmt);
        gem.transferFrom(msg.sen)
    }

    function buyGem(address usr, uint256 gemAmt) external {
        uint256 gemAmt18 = mul(gemAmt, to18ConversionFactor);
        uint256 fee = mul(gemAmt18, tout) / WAD;
        uint256 daiAmt = add(gemAmt18, fee);
        require(dai.transferFrom(msg.sender, address(this), daiAmt), "DssPsm/failed-transfer");
        daiJoin.join(address(this), daiAmt);
        vat.frob(ilk, address(this), address(this), address(this), -int256(gemAmt18), -int256(gemAmt18));
        gemJoin.exit(usr, gemAmt);
        vat.move(address(this), vow, mul(fee, RAY));
    }

    function __setTin(uint256 _tin) external {
        tin = _tin;
    }

    function __setTout(uint256 _tout) external {
        tout = _tout;
    }

}
