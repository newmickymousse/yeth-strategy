// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {CustomStrategyTriggerBase} from "@periphery/ReportTrigger/CustomStrategyTriggerBase.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurvePool} from "./interfaces/ICurvePool.sol";
import {IYEthStaker} from "./interfaces/IYEthStaker.sol";
import {IYEthPool} from "./interfaces/IYEthPool.sol";
import {IDepositFacility} from "./interfaces/IDepositFacility.sol";
import {ICommonReportTrigger} from "./interfaces/ICommonReportTrigger.sol";

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

contract YEthStakerStrategy is
    BaseStrategy, //review: use BaseHealthCheck
    CustomStrategyTriggerBase,
    TradeFactorySwapper
{
    using SafeERC20 for ERC20;

    ICurvePool public constant curvepool =
        ICurvePool(0x69ACcb968B19a53790f43e57558F5E443A91aF22); // 0 is WETH, 1 is yETH
    ERC20 public constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant yETH =
        ERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IYEthStaker public constant styETH =
        IYEthStaker(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);
    IYEthPool public constant yETHPool =
        IYEthPool(0x2cced4ffA804ADbe1269cDFc22D7904471aBdE63);
    ICommonReportTrigger public constant COMMON_REPORT_TRIGGER =
        ICommonReportTrigger(0xD98C652f02E7B987e0C258a43BCa9999DF5078cF);

    int128 internal constant WETH_INDEX; // review: 0 is default
    int128 internal constant YETH_INDEX = 1;
    uint256 internal constant MAX_BPS = 10000;
    uint256 internal constant WAD = 1e18;

    address immutable GOV;

    IDepositFacility public depositFacility;
    uint256 public maxSingleWithdraw = 100 * 1e18;
    uint256 public swapSlippage = 50;

    event DepositFacilitySet(address facility);
    event MaxSingleWithdrawSet(uint256 max);
    event SwapSlippageSet(uint256 slippage);

    constructor(
        address _asset,
        string memory _name,
        address _gov
    ) BaseStrategy(_asset, _name) {
        // review: require always at the top to avoid wasting gas if you screw it up :)
        require(_asset == address(WETH), "Asset!=WETH");
        require(_gov != address(0), "GOV=0x0");

        GOV = _gov;
        WETH.approve(address(curvepool), type(uint256).max);
        yETH.approve(address(curvepool), type(uint256).max);
        yETH.approve(address(styETH), type(uint256).max);
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
        if (_amount < WAD) {
            // no need to swap dust
            // review: 1 eth is dust? that's a lot.
            return;
        }

        // review: This is sandwitcheable and deployFunds can be forced
        // Not sure if this is better than just flagging where to go through
        uint256 amountOut = curvepool.get_dy(WETH_INDEX, YETH_INDEX, _amount);

        // review: here you are comparing amountOut (yETH) vs _amount (weth)
        // I would add a comment saying:
        // we are assuming weth==yeth, if we get more than 1:1, we should go through curve.
        if (amountOut > _amount) {
            // use curve pool
            amountOut = curvepool.exchange(
                WETH_INDEX,
                YETH_INDEX,
                _amount,
                _amount
            );
            styETH.deposit(amountOut);
        } else {
            // use deposit facility if there is available capacity
            // review: why creating a new var?
            IDepositFacility facility = depositFacility;

            // review I would require() facility to be set
            // and I would set it up in the constructor.
            if (address(facility) == address(0)) {
                return;
            }
            uint256 deposit;
            (deposit, ) = facility.available();

            // review: again, dust 1eth is too much
            if (deposit < WAD) {
                // dont deposit dust
                return;
            }
            if (_amount < deposit) {
                deposit = _amount;
            }
            facility.deposit(deposit, true);
        }
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
        uint256 debt = TokenizedStrategy.totalAssets() -
            asset.balanceOf(address(this));

        // review: why aren't you checking available amount first?
        // if facility is full, you will have loose assets.

        // calculate equivalent share of st-yETH
        uint256 stakedAmount = (styETH.balanceOf(address(this)) * _amount) /
            debt;
        // redeem for yETH
        if (stakedAmount > 0) {
            // review: you are overriding the _amount here? why?
            _amount = styETH.redeem(stakedAmount);
        }

        // first try withdrawing from the facility
        IDepositFacility facility = depositFacility;
        // review: again, make the facility address a requirement and reduce code
        if (address(facility) != address(0)) {
            uint256 withdrawAmount;
            (, withdrawAmount) = facility.available();
            if (withdrawAmount > 0) {
                if (withdrawAmount > _amount) {
                    withdrawAmount = _amount;
                }

                // review: plz, do not override _amount the _ means read only
                _amount -= withdrawAmount;
                facility.withdraw(withdrawAmount);
                //slither-disable-next-line incorrect-equality
                if (_amount == 0) {
                    return;
                }
            }
        }

        // use curve for any remaining amount
        // calculate minimum out amount based on EMA oracle and a configurable slippage
        uint256 minAmountOut = (_amount *
            curvepool.ema_price() *
            (MAX_BPS - swapSlippage)) /
            MAX_BPS /
            WAD;
        curvepool.exchange(YETH_INDEX, WETH_INDEX, _amount, minAmountOut);
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
        if (!TokenizedStrategy.isShutdown()) {
            uint256 balance = asset.balanceOf(address(this));
            if (balance > 0) {
                _deployFunds(balance);
            }
        }

        // review: since depositFacility might have no liquidity and curve pool
        // be unbalanced, there is a case where you still have loose assets.
        // you need to add asset.balanceOf(address(this))
        _totalAssets = estimatedTotalAssest();
    }

    /**
     * @notice Returns wether or not report() should be called by a keeper.
     * @dev Check if the strategy is not shutdown and if there is asset to deploy
     * @return . Should return true if report() should be called by keeper or false if not.
     */
    function reportTrigger(
        address _strategy
    ) external view override returns (bool, bytes memory) {
        if (TokenizedStrategy.isShutdown()) return (false, bytes("Shutdown"));

        // don't trigger for dust
        uint256 assetBalance = asset.balanceOf(address(this));
        if (assetBalance > WAD) {
            // check if the curve pool has enough liquidity
            uint256 swapAmountOut = curvepool.get_dy(
                WETH_INDEX,
                YETH_INDEX,
                assetBalance
            );
            if (swapAmountOut > assetBalance) {
                return (
                    true,
                    abi.encodeWithSelector(TokenizedStrategy.report.selector)
                );
            }

            // check if the deposit facility has enough capacity
            if (address(depositFacility) != address(0)) {
                (uint256 deposit, ) = depositFacility.available();
                if (deposit > WAD) {
                    // it is ok deposit even just WAD
                    return (
                        true,
                        abi.encodeWithSelector(
                            TokenizedStrategy.report.selector
                        )
                    );
                }
            }
        }

        if (!COMMON_REPORT_TRIGGER.isCurrentBaseFeeAcceptable()) {
            return (false, bytes("Base fee is too high"));
        }

        return (
            // Return true is the full profit unlock time has passed since the last report.
            block.timestamp - TokenizedStrategy.lastReport() >
                TokenizedStrategy.profitMaxUnlockTime(),
            abi.encodeWithSelector(TokenizedStrategy.report.selector)
        );
    }

    /**
     * @notice Internal function to calculate the value of different assets
     * in asset value.
     *
     * @return estimated total value in asset value
     */

     // review: typo, Assest
    function estimatedTotalAssest() public view returns (uint256) {
        // amount of yETH in strategy
        uint256 yethAmount = styETH.maxWithdraw(address(this));
        // estimate based on max withdraw size
        // review: in a bank run this will make estimateTotalAssets be very optimistic.
        uint256 swapAmountIn = maxSingleWithdraw;
        uint256 swapAmountOut = curvepool.get_dy(
            YETH_INDEX,
            WETH_INDEX,
            swapAmountIn
        );
        return
            (yethAmount * swapAmountOut) /
            swapAmountIn +
            asset.balanceOf(address(this));
    }

    /// @notice Sets the address of the deposit and withdrawal facility, allowing 1:1 exchange
    /// @param _facility Address of new facility
    function setDepositFacility(address _facility) external onlyManagement {
        address previous = address(depositFacility);
        depositFacility = IDepositFacility(_facility);

        // revoke previous allowance
        if (previous != address(0)) {
            // review: don't you need safeApprove?
            // actually, the newest SafeERC20 have some force methods
            WETH.approve(previous, 0);
            yETH.approve(previous, 0);
        }

        // set new allowance
        if (_facility != address(0)) {
            WETH.approve(_facility, type(uint256).max);
            yETH.approve(_facility, type(uint256).max);
        }
        emit DepositFacilitySet(_facility);
    }

    /// @notice Sets the maximum size of a single withdrawal
    /// @param _max Maximum withdrawal size
    // review: not sure what maxSingleWithdraw is protecting from
    // you can loop and you get the same behavior as if there wasn't a max single wd
    function setMaxSingleWithdraw(uint256 _max) external onlyManagement {
        require(_max >= WAD, "max<WAD");
        maxSingleWithdraw = _max;
        emit MaxSingleWithdrawSet(_max);
    }

    /// @notice Sets the slippage allowed on a swap during a withdrawal
    /// @param _slippage Allowed slippage (bps)
    function setSwapSlippage(uint256 _slippage) external onlyManagement {
        require(_slippage <= MAX_BPS, "slippage>MAX");
        swapSlippage = _slippage;
        emit SwapSlippageSet(_slippage);
    }

    function rebalanceDepositFacility(uint256 _amount) external onlyManagement {
        require(address(depositFacility) != address(0), "!facility");
        // review: what's this? why would you withdraw for stYeth directly?
        // add comments to this method
        styETH.withdraw(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

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
        // review:
        // you can do:
        /*
          uint256 fromDepositFacility;
          if (address(depositFacility) != address(0)) {
              (, fromDepositFacility) = depositFacility.available();
          }
          return asset.balanceOf(address(this)) + fromDepositFacility + maxSingleWithdraw
        */

        if (address(depositFacility) != address(0)) {
            (, uint256 withdraw) = depositFacility.available();
            return
                asset.balanceOf(address(this)) + maxSingleWithdraw + withdraw;
        }
        return asset.balanceOf(address(this)) + maxSingleWithdraw;
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
        uint256 balance = styETH.balanceOf(address(this));
        if (balance > 0) {
            styETH.redeem(balance);
        }

        // withdraw yeth to all LSTs to minimize losses
        balance = yETH.balanceOf(address(this));
        if (balance > 0) {
            uint256 num = yETHPool.num_assets();
            yETHPool.remove_liquidity(balance, new uint256[](num));
        }
        // LSTs should be sweeped and swapped to WETH through the trade factory
    }

    /// @notice Sweep token, only governance can call it
    function sweep(address _token) external {
        require(msg.sender == GOV, "!GOV");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    /**
     * @notice Set the trade factory contract address.
     * @dev For disabling set address(0).
     * @param _tradeFactory The address of the trade factory contract.
     */
    function setTradeFactory(address _tradeFactory) external {
        require(msg.sender == GOV, "!GOV");
        _setTradeFactory(_tradeFactory, address(asset));
    }

    /**
     * @notice Add a reward token for swapping using TradeFactorySwapper.
     * @dev Only management can call it.
     * @param _from The address of the token to swap from. Reward token.
     * @param _to The address of the token to swap to. Asset token, yETH or st_yETH.
     */
    function addRewardTokenForSwapping(
        address _from,
        address _to
    ) external onlyManagement {
        require(
            _from != address(asset) &&
                _from != address(yETH) &&
                _from != address(styETH),
            "!from token"
        );
        require(
            _to == address(asset) ||
                _to == address(yETH) ||
                _to == address(styETH),
            "!to token"
        );
        _addToken(_from, _to);
    }

    /**
     * @notice Remove a reward token for swapping using TradeFactorySwapper.
     * @dev Only management can call it.
     * @param _from The address of the token to swap from. Reward token.
     * @param _to The address of the token to swap to. Asset token, yETH or st_yETH.
     */
    function removeRewardTokenForSwapping(
        address _from,
        address _to
    ) external onlyManagement {
        _removeToken(_from, _to);
    }

    /// must override function from TradeFactorySwapper
    function _claimRewards() internal override {
        // There are no rewards to claim
    }
}
