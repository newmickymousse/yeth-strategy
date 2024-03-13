pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {IYEthPool} from "../interfaces/IYEthPool.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_emergencyWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        vm.prank(management);
        strategy.emergencyWithdraw(0);

        // assert strategy has no assets
        assertEq(strategy.totalAssets(), 0, "!totalAssets");

        // assert strategy has mutiple LSTs
        IYEthPool pool = IYEthPool(yETHPool);
        uint256 numberOfLsts = pool.num_assets();
        for (uint256 i; i < numberOfLsts; i++) {
            address lst = pool.assets(i);
            assertGt(
                ERC20(lst).balanceOf(address(strategy)),
                0,
                "!lst balance"
            );
        }

        // gov can sweep all LSTs
        vm.startPrank(GOV);
        for (uint256 i; i < numberOfLsts; i++) {
            address lst = pool.assets(i);
            strategy.sweep(lst);
            assertEq(ERC20(lst).balanceOf(address(strategy)), 0, "!sweep");
        }
        vm.stopPrank();

        // all assets are withdrawn
        assertEq(strategy.totalAssets(), 0, "!totalAssets");

        // user still has strategy shares
        assertGt(strategy.balanceOf(user), 0, "!balanceOf");
    }
}
