// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {CustomStrategyTriggerBase} from "@periphery/ReportTrigger/CustomStrategyTriggerBase.sol";
import {AuctionSwapper} from "@periphery/swappers/AuctionSwapper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurvePool} from "./interfaces/ICurvePool.sol";
import {IYEthStaker} from "./interfaces/IYEthStaker.sol";
import {IYEthPool} from "./interfaces/IYEthPool.sol";
import {IDepositFacility} from "./interfaces/IDepositFacility.sol";
import {ICommonReportTrigger} from "./interfaces/ICommonReportTrigger.sol";
import {IGenericGovernance, IWeightGovernance} from "./interfaces/IGovernance.sol";

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
    BaseStrategy,
    CustomStrategyTriggerBase,
    AuctionSwapper
{
    using SafeERC20 for ERC20;

    enum DepositFlag { OFF, FORCE_ONCE, FACILITY_ONLY, ON }
    
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

    int128 internal constant WETH_INDEX = 0;
    int128 internal constant YETH_INDEX = 1;
    uint256 internal constant MAX_BPS = 10000;
    uint256 internal constant WAD = 1e18;

    address immutable GOV;

    ICurvePool public curvePool; // 0 is WETH, 1 is yETH
    IDepositFacility public depositFacility;
    uint256 public maxSingleWithdraw = 50 * WAD;
    uint256 public swapSlippage = 80;
    uint256 public minDepositAmount = 10 * WAD;
    DepositFlag public depositFlag = DepositFlag.OFF;

    event CurvePoolSet(address facility);
    event DepositFacilitySet(address facility);
    event MaxSingleWithdrawSet(uint256 max);
    event SwapSlippageSet(uint256 slippage);

    constructor(
        address _gov,
        address _curve,
        address _facility
    ) BaseStrategy(address(WETH), "yETH staker strategy") {
        GOV = _gov;

        yETH.approve(address(styETH), type(uint256).max);
        require(_curve != address(0) || _facility != address(0));

        if (_curve != address(0)) {
            curvePool = ICurvePool(_curve);
            WETH.approve(_curve, type(uint256).max);
            yETH.approve(_curve, type(uint256).max);
        }

        if (_facility != address(0)) {
            depositFacility = IDepositFacility(_facility);
            WETH.approve(_facility, type(uint256).max);
            yETH.approve(_facility, type(uint256).max);
        }
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
        _invest(_amount, false);
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
        // debt cannot be zero
        uint256 debt = TokenizedStrategy.totalAssets() -
            asset.balanceOf(address(this));
        // calculate equivalent share of st-yETH
        uint256 stakedAmount = styETH.balanceOf(address(this)) * 
            _amount / debt;
        //slither-disable-next-line incorrect-equality
        if (stakedAmount == 0) {
            return;
        }
        // redeem for yETH
        uint256 unstakedYethAmount = styETH.redeem(stakedAmount);

        // first try withdrawing from the facility
        IDepositFacility facility = depositFacility;
        if (address(facility) != address(0)) {
            (, uint256 withdrawAmount) = facility.available();
            if (withdrawAmount > 0) {
                if (withdrawAmount > unstakedYethAmount) {
                    withdrawAmount = unstakedYethAmount;
                }
                unstakedYethAmount -= withdrawAmount;
                facility.withdraw(withdrawAmount);
                //slither-disable-next-line incorrect-equality
                if (unstakedYethAmount == 0) {
                    return;
                }
            }
        }

        // use curve for any remaining amount
        require(address(curvePool) != address(0), "!liquidity");

        // calculate minimum out amount based on configured slippage
        uint256 minAmountOut = unstakedYethAmount * (MAX_BPS - swapSlippage) / MAX_BPS;
        curvePool.exchange(
            YETH_INDEX,
            WETH_INDEX,
            unstakedYethAmount,
            minAmountOut
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
        DepositFlag _flag = depositFlag;
        if (!TokenizedStrategy.isShutdown() && _flag != DepositFlag.OFF) {
            uint256 threshold = minDepositAmount - 1;
            if (_flag == DepositFlag.FORCE_ONCE) {
                // if forced manually, treat as if deposit flag is 
                //  turned on and remove deposit threshold
                _flag = DepositFlag.ON;
                depositFlag = DepositFlag.OFF;
                threshold = 0;
            }

            uint256 balance = asset.balanceOf(address(this));
            if (balance > threshold) {
                _invest(balance, _flag == DepositFlag.ON);
            }
        }
        _totalAssets = estimatedTotalAssets();
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

        DepositFlag flag = depositFlag;

        // report if forced
        if (flag == DepositFlag.FORCE_ONCE) {
            return (true, abi.encodeWithSelector(TokenizedStrategy.report.selector));
        }

        // otherwise only report if gas price is acceptable
        if (!COMMON_REPORT_TRIGGER.isCurrentBaseFeeAcceptable()) {
            return (false, bytes("BaseFee"));
        }

        // profit has been unlocked
        if (block.timestamp > TokenizedStrategy.lastReport() + TokenizedStrategy.profitMaxUnlockTime()) {
            return (true, abi.encodeWithSelector(TokenizedStrategy.report.selector));
        }

        if (flag == DepositFlag.OFF) {
            return (false, bytes("Off"));
        }

        // don't trigger for dust
        uint256 assetBalance = asset.balanceOf(address(this));
        if (assetBalance < minDepositAmount) {
            return (false, bytes("Dust"));
        }

        // check deposit facility capacity
        IDepositFacility facility = depositFacility;
        if (address(facility) != address(0)) {
            (uint256 available,) = facility.available();

            if (available >= minDepositAmount) {
                return (true, abi.encodeWithSelector(TokenizedStrategy.report.selector));
            }

            if (available > assetBalance) {
                available = assetBalance;
            }
            assetBalance -= available;
        }

        ICurvePool pool = curvePool;
        if (flag == DepositFlag.ON && assetBalance > 0 && address(pool) != address(0)) {
            // check if the curve pool has enough liquidity
            uint256 swapAmountOut = curvePool.get_dy(WETH_INDEX, YETH_INDEX, assetBalance);

            if (swapAmountOut >= assetBalance) {
                return (true, abi.encodeWithSelector(TokenizedStrategy.report.selector));
            }
        }
        
        return (false, bytes("Liquidity"));
    }

    function _invest(uint256 _amount, bool _useCurve) internal {
        // use deposit facility first
        IDepositFacility facility = depositFacility;
        if (address(facility) != address(0)) {
            (uint256 deposit, ) = facility.available();
            if (deposit > _amount) {
                deposit = _amount;
            }
            if (deposit > 0) {
                facility.deposit(deposit, true);
                _amount -= deposit;
            }
        }

        // fall back to Curve pool if needed
        ICurvePool pool = curvePool;
        if (!_useCurve || _amount == 0 || address(pool) == address(0)) {
            return;
        }

        uint256 amountOut = pool.get_dy(WETH_INDEX, YETH_INDEX, _amount);
        if (amountOut < _amount) {
            // don't swap at below 1:1
            return;
        }

        amountOut = pool.exchange(WETH_INDEX, YETH_INDEX, _amount, _amount);
        styETH.deposit(amountOut);
    }

    /**
     * @notice Estimate the total value of all assets in the asset value.
     *
     * @return estimated total value in asset value
     */
    function estimatedTotalAssets() public view returns (uint256) {
        // amount of yETH in strategy
        uint256 yethAmount = styETH.maxWithdraw(address(this));

        if (address(depositFacility) != address(0)) {
            // estimate based on withdraw fee from facility
            (, uint256 fee) = depositFacility.fee_rates();
            return 
                yethAmount * (MAX_BPS - fee) / MAX_BPS + 
                asset.balanceOf(address(this));
        }

        // if deposit facility is not set, curve pool is guaranteed to be.
        // estimate based on max withdraw size
        uint256 swapAmountIn = maxSingleWithdraw;
        // in a bank run this will make estimateTotalAssets be very optimistic.
        uint256 swapAmountOut = curvePool.get_dy(
            YETH_INDEX,
            WETH_INDEX,
            swapAmountIn
        );
        return
            yethAmount * swapAmountOut / swapAmountIn + 
            asset.balanceOf(address(this));
    }

    /// @notice Sets the address of the curve pool
    /// @param _pool Address of new curve pool
    function setCurvePool(address _pool) external onlyManagement {
        address previous = address(curvePool);
        curvePool = ICurvePool(_pool);

        // revoke previous allowance
        if (previous != address(0)) {
            WETH.approve(previous, 0);
            yETH.approve(previous, 0);
        }

        // set new allowance
        if (_pool != address(0)) {
            WETH.approve(_pool, type(uint256).max);
            yETH.approve(_pool, type(uint256).max);
        }
        else {
            require(address(depositFacility) != address(0));
        }
        emit CurvePoolSet(_pool);
    }

    /// @notice Sets the address of the deposit and withdrawal facility
    /// @param _facility Address of new facility
    function setDepositFacility(address _facility) external onlyManagement {
        address previous = address(depositFacility);
        depositFacility = IDepositFacility(_facility);

        // revoke previous allowance
        if (previous != address(0)) {
            WETH.approve(previous, 0);
            yETH.approve(previous, 0);
        }

        // set new allowance
        if (_facility != address(0)) {
            WETH.approve(_facility, type(uint256).max);
            yETH.approve(_facility, type(uint256).max);
        }
        else {
            require(address(curvePool) != address(0));
        }
        emit DepositFacilitySet(_facility);
    }

    /// @notice Sets the maximum size of a single withdrawal
    /// @param _max Maximum withdrawal size
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

    /// @notice Sets the minDepositAmount amount, minimum amount to be considered for deposit
    /// @param _minDepositAmount minDepositAmount amount
    function setMinDepositAmount(
        uint256 _minDepositAmount
    ) external onlyManagement {
        minDepositAmount = _minDepositAmount;
    }

    /// @notice Sets the flag for configuring deposits during reports
    /// @param _flag Flag enum value
    function setDepositFlag(DepositFlag _flag) external onlyManagement {
        depositFlag = _flag;
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
        // LSTs should be sweeped and swapped back to WETH by governance
    }

    /// @notice Sweep token, only management can call it
    function sweep(address _token) external onlyEmergencyAuthorized {
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    function vote(address _target, uint256 _idx, uint256 _yea, uint256 _nay, uint256 _abstain) external onlyManagement {
        IGenericGovernance(_target).vote(_idx, _yea, _nay, _abstain);
    }

    function weightVote(address _target, uint256[] calldata _votes) external onlyManagement {
        IWeightGovernance(_target).vote(_votes);
    }

    /// @notice Set auction contract, only management can call it
    function setAuction(address _auction) external onlyManagement {
        auction = _auction;
    }

    function _auctionKicked(address _token) internal override returns (uint256) {
        require(
            _token != address(asset) && _token != address(yETH) && _token != address(styETH)
        );
        return super._auctionKicked(_token);
    }
}
