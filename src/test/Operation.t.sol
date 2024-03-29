// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface, ICommonReportTrigger} from "./utils/Setup.sol";
import {IYEthPool} from "../interfaces/IYEthPool.sol";
import {IYEthStaker} from "../interfaces/IYEthStaker.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), tokenAddrs["WETH"]);
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.maxSingleWithdraw(), 1e20);
        assertEq(strategy.swapSlippage(), 50);
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        earnInterest(100e18);
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

        // Some funds are left because estimatedTotalAssets uses pesimistic estimate
        uint256 maxLossTolerance = (strategy.swapSlippage() * 2 * _amount) /
            MAX_BPS;
        assertLt(strategy.totalAssets(), maxLossTolerance, "!totalAssets=0");

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

    function test_RevertWhen_withdrawAboveMax() public {
        uint256 _amount = 50e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Report profit
        vm.prank(keeper);
        strategy.report();

        assertEq(asset.balanceOf(address(strategy)), 0, "!deposit");

        vm.prank(management);
        strategy.setMaxSingleWithdraw(1e18);

        // Withdraw all funds
        vm.expectRevert(bytes("ERC4626: redeem more than max"));
        vm.prank(user);
        strategy.redeem(_amount, user, user);
    }

    function test_RevertWhen_addingRewardTokenFromInvalid() public {
        address tradeFactory = address(
            0xd6a8ae62f4d593DAf72E2D7c9f7bDB89AB069F06
        );
        vm.prank(GOV);
        strategy.setTradeFactory(tradeFactory);

        vm.expectRevert(bytes("!from token"));
        vm.prank(management);
        strategy.addRewardTokenForSwapping(
            tokenAddrs["WETH"],
            tokenAddrs["wstETH"]
        );
    }

    function test_RevertWhen_addingRewardTokenToInvalid() public {
        address tradeFactory = address(
            0xd6a8ae62f4d593DAf72E2D7c9f7bDB89AB069F06
        );
        vm.prank(GOV);
        strategy.setTradeFactory(tradeFactory);

        vm.expectRevert(bytes("!to token"));
        vm.prank(management);
        strategy.addRewardTokenForSwapping(
            tokenAddrs["YFI"],
            tokenAddrs["wstETH"]
        );
    }

    function test_addRemoveRewardToken() public {
        address from = tokenAddrs["wstETH"];
        address to = tokenAddrs["WETH"];

        address tradeFactory = address(
            0xd6a8ae62f4d593DAf72E2D7c9f7bDB89AB069F06
        );
        vm.prank(GOV);
        strategy.setTradeFactory(tradeFactory);

        vm.prank(management);
        strategy.addRewardTokenForSwapping(from, to);
        address[] memory rewardTokens = strategy.rewardTokens();
        assertEq(rewardTokens.length, 1, "!rewardTokens");
        assertEq(rewardTokens[0], from, "!rewardTokens");

        vm.prank(management);
        strategy.removeRewardTokenForSwapping(from, to);
        assertEq(strategy.rewardTokens().length, 0, "!rewardTokens");
    }

    function test_setMinDepositAmount() public {
        uint256 minDepositAmount = 1e16;

        vm.expectRevert(bytes("!management"));
        strategy.setMinDepositAmount(minDepositAmount);

        vm.prank(management);
        strategy.setMinDepositAmount(minDepositAmount);
        assertEq(
            strategy.minDepositAmount(),
            minDepositAmount,
            "!minDepositAmount"
        );
    }
}
