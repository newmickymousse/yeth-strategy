// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface, ICommonReportTrigger} from "./utils/Setup.sol";
import {IYEthPool} from "../interfaces/IYEthPool.sol";
import {IYEthStaker} from "../interfaces/IYEthStaker.sol";

contract ReportsTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_RevertWhen_withdrawAboveMax() public {
        uint256 _amount = 110e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Withdraw all funds
        vm.expectRevert(bytes("ERC4626: redeem more than max"));
        vm.prank(user);
        strategy.redeem(_amount, user, user);
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

    function test_reportTriggerSkipHighGas() public {
        uint256 _amount = 11e18;

        // all fee is expensive
        vm.prank(address(0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7));
        ICommonReportTrigger(0xD98C652f02E7B987e0C258a43BCa9999DF5078cF)
            .setAcceptableBaseFee(1);

        (bool trigger, bytes memory message) = strategy.reportTrigger(
            address(strategy)
        );
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

        // won't report after maxUnlockTime because gas is expensive
        (trigger, message) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);
        assertEq(message, bytes("Base fee is too high"));
    }

    function test_reportTiggerSkipBelowWad() public {
        uint256 _amount = 1e17;

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
    }

    function test_reportTriggerSkipShutdown() public {
        uint256 _amount = 11e18;

        (bool trigger, bytes memory message) = strategy.reportTrigger(
            address(strategy)
        );
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        skip(strategy.profitMaxUnlockTime() + 100);

        // won't report after shutdown
        (trigger, message) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);
        assertEq(message, bytes("Shutdown"));
    }
}
