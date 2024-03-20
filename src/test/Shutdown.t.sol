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

        uint256 maxLossTolerance = (strategy.swapSlippage() * _amount) /
            MAX_BPS;

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
            balanceBefore + _amount - maxLossTolerance,
            "!final balance"
        );
    }

    function test_emergencyWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Airdrop yETH to deposit facility
        deal(address(strategy.yETH()), address(depositFacility), _amount);

        vm.prank(management);
        strategy.setDepositFacility(address(depositFacility));

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

        // report new state after emergencyWithdraw
        vm.prank(keeper);
        strategy.report();

        // assert strategy has no assets
        assertEq(strategy.totalAssets(), 0, "!totalAssets");

        // assert strategy has all LSTs from yETHpool
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

        vm.prank(keeper);
        strategy.report();

        // all assets are withdrawn
        assertEq(strategy.totalAssets(), 0, "!totalAssets");

        // user still has strategy shares
        assertGt(strategy.balanceOf(user), 0, "!balanceOf");
    }

    function test_RevertWhen_sweepNotGov() public {
        // Withdraw all funds
        vm.expectRevert(bytes("!GOV"));
        vm.prank(user);
        strategy.sweep(tokenAddrs["wstETH"]);
    }

    function test_RevertWhen_sweepAsset() public {
        // Withdraw all funds
        vm.expectRevert(bytes("!asset"));
        vm.prank(GOV);
        strategy.sweep(address(asset));
    }
}
