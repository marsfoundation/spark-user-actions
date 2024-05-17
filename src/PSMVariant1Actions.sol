// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import { IERC20 }   from "lib/forge-std/src/interfaces/IERC20.sol";
import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

interface PSMVariant1Like {
    function dai() external view returns (address);
    function gemJoin() external view returns (GemJoinLike);
    function buyGem(address usr, uint256 gemAmt) external;
    function sellGem(address usr, uint256 gemAmt) external;
    function tout() external view returns (uint256);
}

interface GemJoinLike {
    function gem() external view returns (address);
}

contract PSMVariant1Actions {

    uint256 private immutable GEM_CONVERSION_FACTOR;

    PSMVariant1Like public immutable psm;
    IERC20          public immutable dai;
    IERC20          public immutable gem;
    IERC4626        public immutable savingsToken;

    constructor(address _psm, address _savingsToken) {
        psm          = PSMVariant1Like(_psm);
        dai          = IERC20(psm.dai());
        gem          = IERC20(psm.gemJoin().gem());
        savingsToken = IERC4626(_savingsToken);

        GEM_CONVERSION_FACTOR = 10 ** (dai.decimals() - gem.decimals());

        // Infinite approvals
        gem.approve(address(psm.gemJoin()), type(uint256).max);  // For psm.sellGem()
        dai.approve(address(psm),           type(uint256).max);  // For psm.buyGem()
        dai.approve(address(savingsToken),  type(uint256).max);  // For savingsToken.deposit()
    }
    
    /**
     * @notice Swap in the PSM and deposit in the `savingsToken`.
     * @dev    Please note that `minAmountOut` is measured in `dai` due to increasing value of the `savingsToken`.
     *         `minAmountOut` is used to protect in the case PSM fees change.
     * @param amountIn     The amount of the `gem` to swap.
     * @param minAmountOut The minimum amount of `dai` to receive.
     */
    function swapAndDeposit(
        address receiver,
        uint256 amountIn,
        uint256 minAmountOut
    ) external {
        gem.transferFrom(msg.sender, address(this), amountIn);
        
        // There may be a balance in this contract, so we determine the difference
        uint256 balanceBefore = dai.balanceOf(address(this));
        psm.sellGem(address(this), amountIn);
        uint256 amountOut = dai.balanceOf(address(this)) - balanceBefore;
        require(amountOut >= minAmountOut, "PSMVariant1Actions/amount-out-too-low");

        savingsToken.deposit(amountOut, receiver);
    }
    
    /**
     * @notice Withdraw from the `savingsToken` and swap in the PSM.
     *         Use this if you want an exact amount of `gem` tokens out. IE pay someone 10k exactly.
     * @dev    Please note that `maxAmountIn` is measured in `dai` due to increasing value of the `savingsToken`.
     *         `maxAmountIn` is used to protect in the case PSM fees change.
     * @param amountOut   The amount of `gem` you want to receive.
     * @param maxAmountIn The maximum amount of `dai` to pay for this swap.
     */
    function withdrawAndSwap(
        address receiver,
        uint256 amountOut,
        uint256 maxAmountIn
    ) external {
        savingsToken.withdraw(amountOut * GEM_CONVERSION_FACTOR, address(this), msg.sender);
        
        // There may be a balance in this contract, so we determine the difference
        uint256 balanceBefore = dai.balanceOf(address(this));
        psm.buyGem(receiver, amountOut);
        uint256 amountIn = dai.balanceOf(address(this)) - balanceBefore;
        require(amountIn <= maxAmountIn, "PSMVariant1Actions/amount-in-too-high");
    }
    
    /**
     * @notice Redeem from the `savingsToken` and swap in the PSM.
     *         Use this if you want to withdraw everything.
     * @dev    Please note that this will leave any dust due to rounding error in this contract.
     * @param shares       The amount of shares to redeem.
     * @param minAmountOut The minimum amount of `gem` to receive.
     */
    function redeemAndSwap(
        address receiver,
        uint256 shares,
        uint256 minAmountOut
    ) external {
        uint256 assets = savingsToken.redeem(shares, address(this), msg.sender);

        // Calculate the exact amount of gems we expect to receive given this amount of assets
        // TODO this leaves a dust amount in the contract, maybe we don't care?
        uint256 amountOut = assets - (assets * psm.tout() / 1e18);
        require(amountOut >= minAmountOut, "PSMVariant1Actions/amount-out-too-low");
        
        // There may be a balance in this contract, so we determine the difference
        uint256 balanceBefore = gem.balanceOf(receiver);
        psm.buyGem(receiver, amountOut);
        uint256 amountIn = gem.balanceOf(receiver) - balanceBefore;
    }

}
