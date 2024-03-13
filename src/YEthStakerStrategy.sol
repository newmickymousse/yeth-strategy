// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICurvePool} from "./interfaces/ICurvePool.sol";
import {IYEthStaker} from "./interfaces/IYEthStaker.sol";
import {IYEthPool} from "./interfaces/IYEthPool.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract YEthStakerStrategy is BaseStrategy {
    using SafeERC20 for ERC20;

    ICurvePool public curvepool =
        ICurvePool(0x69ACcb968B19a53790f43e57558F5E443A91aF22); // 0 is WETH, 1 is yETH
    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant yETH =
        ERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IYEthStaker public constant styETH =
        IYEthStaker(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);
    IYEthPool public constant yETHPool =
        IYEthPool(0x2cced4ffA804ADbe1269cDFc22D7904471aBdE63);

    int128 internal constant WETH_INDEX = 0;
    int128 internal constant yETH_INDEX = 1;
    uint256 internal constant MAX_BPS = 10000;

    address immutable GOV;

    /// @notice Value in BPS how much are WETH and yETH pagged.
    /// 10000 is equal to 1:1
    uint256 public peg = 9900;

    constructor(
        address _asset,
        string memory _name,
        address _gov
    ) BaseStrategy(_asset, _name) {
        require(_asset == address(WETH), "Asset!=WETH");
        WETH.approve(address(curvepool), type(uint256).max);
        yETH.approve(address(curvepool), type(uint256).max);
        yETH.approve(address(styETH), type(uint256).max);
        require(_gov != address(0), "GOV=0x0");
        GOV = _gov;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        uint256 minAmountOut = (_amount * peg) / MAX_BPS; // TODO: change this calculation
        curvepool.exchange(WETH_INDEX, yETH_INDEX, _amount, minAmountOut); //TODO: determine correct min_dy

        // stakes any idle yeth not only the output from exchanging eth
        styETH.deposit(yETH.balanceOf(address(this)));
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        uint256 _amountInYETH = curvepool.get_dy(
            yETH_INDEX,
            WETH_INDEX,
            _amount
        );

        styETH.withdraw(_amountInYETH);
        uint256 yETHInput = Math.min(
            _amountInYETH,
            yETH.balanceOf(address(this))
        );
        curvepool.exchange(
            yETH_INDEX,
            WETH_INDEX,
            yETHInput,
            (yETHInput * peg) / MAX_BPS
        );
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // TODO: Implement harvesting logic and accurate accounting EX:
        //
        if (!TokenizedStrategy.isShutdown()) {
            uint256 balance = asset.balanceOf(address(this));
            if (balance > 0) {
                _deployFunds(balance);
            }
        }
        _totalAssets = estimateTotalAssets();
    }

    /**
     * @notice Internal function to calculate the value of different assets
     * in asset value.
     *
     * @return estimated total value in asset value
     */
    function estimateTotalAssets() public view returns (uint256) {
        // idle yETH + staked yETH
        uint256 yethInEth = yETH.balanceOf(address(this)) +
            styETH.convertToAssets(styETH.balanceOf(address(this)));
        if (yethInEth > 0) {
            // get swap output, curve reverts for 0 values
            yethInEth = curvepool.get_dy(yETH_INDEX, WETH_INDEX, yethInEth);
        }
        return yethInEth + asset.balanceOf(address(this));
    }

    /// @notice Sets the peg value for WETH and yETH
    /// @param _peg The peg value in BPS
    function setPeg(uint256 _peg) external onlyManagement {
        require(_peg <= MAX_BPS, "peg>MAX_BPS");
        peg = _peg;
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function _tendTrigger() internal view override returns (bool) {}
    */

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement deposit limit logic and any needed state variables .
        
        EX:    
            uint256 totalAssets = TokenizedStrategy.totalAssets();
            return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }
    */

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(address(this));;
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        return estimateTotalAssets();
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        // withdraw all styeth to yeth
        styETH.withdraw(styETH.balanceOf(address(this)));
        // withdraw yeth to all LSTs to minimize losses
        uint256 num = yETHPool.num_assets();
        yETHPool.remove_liquidity(
            yETH.balanceOf(address(this)),
            new uint256[](num)
        );
        // LSTs should be sweeped and swapped to WETH
    }

    /// @notice Sweep token, only governance can call it
    function sweep(address _token) external {
        require(msg.sender == GOV, "!GOV");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }
}
