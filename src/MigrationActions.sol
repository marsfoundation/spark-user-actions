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
 * @notice Actions for migrating from DAI/sDAI to USDS/sUSDS.
 * @dev    Also contains 1 downgrade path from USDS to DAI for convenience.
 */
contract MigrationActions {

    IERC20   public immutable dai;
    IERC20   public immutable usds;
    IERC4626 public immutable sdai;
    IERC4626 public immutable susds;

    VatLike  public immutable vat;
    JoinLike public immutable daiJoin;
    JoinLike public immutable usdsJoin;

    constructor(
        address _sdai,
        address _susds,
        address _daiJoin,
        address _usdsJoin
    ) {
        sdai  = IERC4626(_sdai);
        susds = IERC4626(_susds);

        dai  = IERC20(sdai.asset());
        usds = IERC20(susds.asset());

        daiJoin  = JoinLike(_daiJoin);
        usdsJoin = JoinLike(_usdsJoin);
        vat      = daiJoin.vat();

        // Infinite approvals
        dai.approve(_daiJoin,   type(uint256).max);
        usds.approve(_usdsJoin, type(uint256).max);
        usds.approve(_susds,    type(uint256).max);

        // Vat permissioning
        vat.hope(_daiJoin);
        vat.hope(_usdsJoin);
    }

    /**
     * @notice Migrate `assetsIn` of `dai` to `usds`.
     * @param  receiver The receiver of `usds`.
     * @param  assetsIn The amount of `dai` to migrate.
     */
    function migrateDAIToUSDS(address receiver, uint256 assetsIn) public {
        dai.transferFrom(msg.sender, address(this), assetsIn);
        _migrateDAIToUSDS(receiver, assetsIn);
    }

    /**
     * @notice Migrate `assetsIn` of `dai` to `susds`.
     * @param  receiver  The receiver of `susds`.
     * @param  assetsIn  The amount of `dai` to migrate.
     * @return sharesOut The amount of `susds` shares received.
     */
    function migrateDAIToSUSDS(address receiver, uint256 assetsIn) external returns (uint256 sharesOut) {
        migrateDAIToUSDS(address(this), assetsIn);
        sharesOut = susds.deposit(assetsIn, receiver);
    }

    /**
     * @notice Migrate `assetsIn` of `sdai` to `usds`.
     * @param  receiver The receiver of `usds`.
     * @param  assetsIn The amount of `sdai` to migrate in assets.
     */
    function migrateSDAIAssetsToUSDS(address receiver, uint256 assetsIn) public {
        sdai.withdraw(assetsIn, address(this), msg.sender);
        _migrateDAIToUSDS(receiver, assetsIn);
    }

    /**
     * @notice Migrate `sharesIn` of `sdai` to `usds`.
     * @param  receiver  The receiver of `usds`.
     * @param  sharesIn  The amount of `sdai` to migrate in shares.
     * @return assetsOut The amount of `usds` assets received.
     */
    function migrateSDAISharesToUSDS(address receiver, uint256 sharesIn) public returns (uint256 assetsOut) {
        assetsOut = sdai.redeem(sharesIn, address(this), msg.sender);
        _migrateDAIToUSDS(receiver, assetsOut);
    }

    /**
     * @notice Migrate `assetsIn` of `sdai` (denominated in `dai`) to `susds`.
     * @param  receiver  The receiver of `susds`.
     * @param  assetsIn  The amount of `sdai` to migrate (denominated in `dai`).
     * @return sharesOut The amount of `susds` shares received.
     */
    function migrateSDAIAssetsToSUSDS(address receiver, uint256 assetsIn) external returns (uint256 sharesOut) {
        migrateSDAIAssetsToUSDS(address(this), assetsIn);
        sharesOut = susds.deposit(assetsIn, receiver);
    }

    /**
     * @notice Migrate `sharesIn` of `sdai` to `susds`.
     * @param  receiver  The receiver of `susds`.
     * @param  sharesIn  The amount of `sdai` to migrate in shares.
     * @return sharesOut The amount of `susds` shares received.
     */
    function migrateSDAISharesToSUSDS(address receiver, uint256 sharesIn) external returns (uint256 sharesOut) {
        uint256 assets = migrateSDAISharesToUSDS(address(this), sharesIn);
        sharesOut = susds.deposit(assets, receiver);
    }

    /**
     * @notice Downgrade `assetsIn` of `usds` to `dai`.
     * @param  receiver The receiver of `dai`.
     * @param  assetsIn The amount of `usds` to downgrade.
     */
    function downgradeUSDSToDAI(address receiver, uint256 assetsIn) external {
        usds.transferFrom(msg.sender, address(this), assetsIn);
        usdsJoin.join(address(this), assetsIn);
        daiJoin.exit(receiver,       assetsIn);
    }

    /**********************************************************************************************/
    /*** Internal helper functions                                                              ***/
    /**********************************************************************************************/

    function _migrateDAIToUSDS(address receiver, uint256 amount) internal {
        daiJoin.join(address(this), amount);
        usdsJoin.exit(receiver,      amount);
    }

}
