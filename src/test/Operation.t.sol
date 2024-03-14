// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {IYEthPool} from "../interfaces/IYEthPool.sol";
import {IYEthStaker} from "../interfaces/IYEthStaker.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        IYEthStaker staker = IYEthStaker(strategy.styETH());
        uint256 sharesValue = staker.convertToAssets(1e18);
        uint256 assetsValue = staker.convertToAssets(
            staker.balanceOf(address(strategy))
        );
        uint256 strategyBalance = staker.balanceOf(address(strategy));

        // Earn Interest
        uint256 preBal = ERC20(strategy.yETH()).balanceOf(address(staker));
        deal(strategy.yETH(), strategy.styETH(), preBal + 1000e18);
        staker.update_amounts();
        skip(2 weeks);

        uint256 sharesValue2 = staker.convertToAssets(1e18);
        assertGt(
            sharesValue2,
            sharesValue,
            "!yETH earned profit, shares value more"
        );

        uint256 assetsValue2 = staker.convertToAssets(
            staker.balanceOf(address(strategy))
        );
        assertGt(
            assetsValue2,
            assetsValue,
            "!yETH earned profit, assets value more"
        );

        assertEq(
            staker.balanceOf(address(strategy)),
            strategyBalance,
            "!strategy balance"
        );

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0, "!totalAssets=0");

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }
    
    function test_deposit_skip_below_wad() public {
        uint256 _amount = 1e17;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // all funds are in asset, not deposited
        assertEq(asset.balanceOf(address(strategy)), _amount, "!final balance");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0, "!totalAssets=0");

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_reportTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime() + 100);

        // should report after maxUnlockTime
        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(trigger);

        vm.prank(keeper);
        strategy.report();

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);
    }
}
