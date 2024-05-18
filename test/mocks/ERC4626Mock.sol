// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

contract ERC4626Mock is MockERC20 {

    MockERC20 public asset;

    uint256 public shareConversionRate = 1e18;

    constructor(
        MockERC20 _asset,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) MockERC20(name, symbol, decimals) {
        asset = _asset;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = assets * 1e18 / shareConversionRate;
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = _divup(assets * 1e18, shareConversionRate);
        _decreaseAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = shares * shareConversionRate / 1e18;
        _decreaseAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }

    function __setShareConversionRate(uint256 rate) external {
        shareConversionRate = rate;
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

}
