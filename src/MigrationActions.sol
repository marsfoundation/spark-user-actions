// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import { IERC20 }   from "lib/forge-std/src/interfaces/IERC20.sol";
import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

interface JoinLike {
    function vat() external view returns (VatLike);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface VatLike {
    function hope(address) external;
}

/**
 * @notice Actions for migrating from DAI/sDAI to NST/sNST.
 * @dev    Also contains 1 downgrade path from NST to DAI for convenience.
 */
contract MigrationActions {

    IERC20   public immutable dai;
    IERC4626 public immutable sdai;
    IERC20   public immutable nst;
    IERC4626 public immutable snst;

    VatLike  public immutable vat;
    JoinLike public immutable daiJoin;
    JoinLike public immutable nstJoin;

    constructor(
        address _sdai,
        address _snst,
        address _daiJoin,
        address _nstJoin
    ) {
        sdai = IERC4626(_sdai);
        dai  = IERC20(sdai.asset());
        snst = IERC4626(_snst);
        nst  = IERC20(snst.asset());

        daiJoin = JoinLike(_daiJoin);
        nstJoin = JoinLike(_nstJoin);
        vat     = daiJoin.vat();

        // Infinite approvals
        dai.approve(_daiJoin, type(uint256).max);
        nst.approve(_nstJoin, type(uint256).max);
        nst.approve(_snst,    type(uint256).max);

        // Vat permissioning
        vat.hope(_daiJoin);
        vat.hope(_nstJoin);
    }

    /**
     * @notice Migrate `amount` of `dai` to `nst`.
     * @param  receiver The receiver of the `nst`.
     * @param  amount   The amount of the `dai` to migrate.
     */
    function migrateDAIToNST(address receiver, uint256 amount) external {
        dai.transferFrom(msg.sender, address(this), amount);
        daiJoin.join(address(this), amount);
        nstJoin.exit(receiver, amount);
    }

    /**
     * @notice Migrate `amount` of `dai` to `snst`.
     * @param  receiver  The receiver of the `snst`.
     * @param  amount    The amount of the `dai` to migrate.
     * @return sharesOut The amount of `snst` shares received.
     */
    function migrateDAIToSNST(address receiver, uint256 amount) external returns (uint256 sharesOut) {
        dai.transferFrom(msg.sender, address(this), amount);
        daiJoin.join(address(this), amount);
        nstJoin.exit(address(this), amount);
        sharesOut = snst.deposit(amount, receiver);
    }

    /**
     * @notice Migrate `assetsIn` of `sdai` to `nst`.
     * @param  receiver The receiver of the `nst`.
     * @param  assetsIn The amount of the `sdai` to migrate in assets.
     */
    function migrateSDAIAssetsToNST(address receiver, uint256 assetsIn) external {
        sdai.withdraw(assetsIn, address(this), msg.sender);
        daiJoin.join(address(this), assetsIn);
        nstJoin.exit(receiver, assetsIn);
    }

    /**
     * @notice Migrate `sharesIn` of `sdai` to `nst`.
     * @param  receiver  The receiver of the `nst`.
     * @param  sharesIn  The amount of the `sdai` to migrate in shares.
     * @return assetsOut The amount of `nst` assets received.
     */
    function migrateSDAISharesToNST(address receiver, uint256 sharesIn) external returns (uint256 assetsOut) {
        assetsOut = sdai.redeem(sharesIn, address(this), msg.sender);
        daiJoin.join(address(this), assetsOut);
        nstJoin.exit(receiver, assetsOut);
    }

    /**
     * @notice Migrate `assetsIn` of `sdai` to `snst`.
     * @param  receiver  The receiver of the `snst`.
     * @param  assetsIn  The amount of the `sdai` to migrate in assets.
     * @return sharesOut The amount of `snst` shares received.
     */
    function migrateSDAIAssetsToSNST(address receiver, uint256 assetsIn) external returns (uint256 sharesOut) {
        sdai.withdraw(assetsIn, address(this), msg.sender);
        daiJoin.join(address(this), assetsIn);
        nstJoin.exit(address(this), assetsIn);
        sharesOut = snst.deposit(assetsIn, receiver);
    }

    /**
     * @notice Migrate `sharesIn` of `sdai` to `snst`.
     * @param  receiver  The receiver of the `snst`.
     * @param  sharesIn  The amount of the `sdai` to migrate in shares.
     * @return sharesOut The amount of `snst` shares received.
     */
    function migrateSDAISharesToSNST(address receiver, uint256 sharesIn) external returns (uint256 sharesOut) {
        uint256 assets = sdai.redeem(sharesIn, address(this), msg.sender);
        daiJoin.join(address(this), assets);
        nstJoin.exit(address(this), assets);
        sharesOut = snst.deposit(assets, receiver);
    }

    /**
     * @notice Downgrade `amount` of `nst` to `dai`.
     * @param  receiver The receiver of the `dai`.
     * @param  amount   The amount of the `nst` to downgrade.
     */
    function downgradeNSTToDAI(address receiver, uint256 amount) external {
        nst.transferFrom(msg.sender, address(this), amount);
        nstJoin.join(address(this), amount);
        daiJoin.exit(receiver, amount);
    }

}
