# Spark User Actions

<!-- ![Foundry CI](https://github.com/{org}/{repo}/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/{org}/{repo}/blob/master/LICENSE) -->

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

Common user actions in the Maker ecosystem related to DAI, sDAI, NST, sNST, USDC. USDT is unsupported because of a lack of first-class support in Maker at this time. USDT can be supported if Maker infrastructure is added in the future. Users wanting to enter or exit via USDT need to use DEX aggregators such as Cowswap.

These contracts are not meant to exhaustively cover all use cases, but group common actions where there is more than 1 transaction required. For example, swapping from USDC to sDAI is covered, but not DAI to sDAI because there is already a `deposit(...)` function on the sDAI contract. 

These contracts are designed to revert when edge cases present themselves such as the PSM being empty or at max debt capacity. Users should feel confident that at most their transaction will fail instead of losing part of their principal.

These contracts will be deployed at well-known addresses to be used across the Maker ecosystem.

## Top Level Actions Mapping

### Ethereum (pre-NST launch)

DAI <-> sDAI: sDAI ERC-4626 interface
USDC <-> DAI: Use PSM directly
USDC <-> sDAI: PSMVariantXActions (1 and 2 depending on version of PSM active)

### Ethereum (post-NST launch)

NST <-> sNST: PullUp provides this?
USDC <-> NST: Will PSM be upgraded? If so, use PSM directly.
USDC <-> sNST: PSMVariant2Actions

NST <-> NGT Farm: Directly deposit
USDC <-> NGT Farm: PSMVariant2Actions
NST <-> SPK Farm: Directly deposit
USDC <-> SPK Farm: PSMVariant2Actions

### Non-Ethereum chains

A three-way PSM will be provided here: https://github.com/marsfoundation/spark-psm. This can be used directly by UIs.

NST <-> sNST: Swap in PSM
USDC <-> NST: Swap in PSM
USDC <-> sNST: PSMVariant3Actions (to deal with dust)

NST <-> NGT Farm: Directly deposit
USDC <-> NGT Farm: PSMVariant3Actions
NST <-> SPK Farm: Directly deposit
USDC <-> SPK Farm: PSMVariant3Actions

## Contracts Available

### PSMVariant1Actions

Intended to be used with the first version of the USDC PSM at `0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A` and sDAI. This contract will not support NST, sNST. It is expected that the upgrade to the second verison of the USDC PSM will be done before the launch of these tokens.

The code is written in a general way, but it is expected for this to be used with the USDC PSM and sDAI. Please note that all values are measured in either USDC or DAI and not sDAI shares. This keeps the UI simple in that you can specify `100e18` of sDAI to mean "100 DAI worth of sDAI" instead of doing the share conversion.

Supported actions:

```
function swapAndDeposit(
    address receiver,
    uint256 amountIn,
    uint256 minAmountOut
) external returns (uint256 amountOut);
```

Deposit `amountIn` USDC and swap it for at least `minAmountOut` sDAI (measured in DAI units). Send the sDAI to the `receiver`.

Example:

```
// Use exact approvals for safety
usdc.approve(address(actions), 100e6);
actions.swapAndDeposit(address(this), 100e6, 100e18);
// User has 100 DAI worth of sDAI
```

```
function withdrawAndSwap(
    address receiver,
    uint256 amountOut,
    uint256 maxAmountIn
) external returns (uint256 amountIn);
```

There are two types of "withdrawals". The first is when you want an exact output measured in USDC. You can also use this to send another account an exact payment. In this case it is important not to send dust to the user.

Sends at most `maxAmountIn` sDAI (measured in DAI units) and swap it for exactly `amountOut` USDC. Send the USDC to the `receiver`.

Example:

```
// Use exact approvals for safety
// +1 is to prevent rounding errors
sDAI.approve(address(actions), sDAI.convertToShares(100e18) + 1);
actions.withdrawAndSwap(address(this), 100e6, 100e18);
// User has 100 USDC
```

```
function redeemAndSwap(
    address receiver,
    uint256 shares,
    uint256 minAmountOut
) external returns (uint256 amountOut);
```

This is the second type of "withdrawal" where a user wants to withdraw all of their sDAI balance to USDC. This method is better because it will not leave dust like in the previous function.

Sends `shares` sDAI (measured in sDAI shares) and swap it for at least `minAmountOut` USDC. Send the USDC to the `receiver`.

Example:

```
// Use exact approvals for safety
uint256 bal = sDAI.balanceOf(address(this));
sDAI.approve(address(actions), bal);
actions.redeemAndSwap(address(this), bal, sDAI.convertToAssets(bal));
// User has withdrawn as much USDC as possible
```

### PSMVariant2Actions

TODO. Intended to be used with the second version of the USDC PSM located at https://github.com/makerdao/dss-lite-psm. This contract will expand support to include NST and sNST.

Supported actions:

 * TBD

### PSMVariant3Actions

TODO. Intended to be used with the third version of the USDC PSM located at https://github.com/marsfoundation/spark-psm. This is intented to only be used with USDC, NST and sNST.

Supported actions:

 * USDC <-> NGT Farms
 * USDC <-> SPK Farms

## Usage

```bash
forge build
```

## Test

```bash
forge test
```

***
*The IP in this repository was assigned to Mars SPC Limited in respect of the MarsOne SP*
