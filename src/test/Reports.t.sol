// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface, ICommonReportTrigger, DepositFlag, IBaseDepositFacility} from "./utils/Setup.sol";
import {IYEthPool} from "../interfaces/IYEthPool.sol";
import {IYEthStaker} from "../interfaces/IYEthStaker.sol";

contract ReportsTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_trigger_maxUnluck(uint256 _amount) public {
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

    function test_trigger_skipHighGas() public {
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
        assertEq(message, bytes("BaseFee"));
    }

    function test_trigger_treshold() public {
        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.ON);

        // temporarily remove deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(0));

        (bool trigger, bytes memory message) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, 1 ether);

        // doesnt trigger a report
        (trigger, message) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);
        assertEq(message, bytes("Dust"));

        // reach the threshold
        mintAndDepositIntoStrategy(strategy, user, 10 ether);

        // restore deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(depositFacility));

        // cant trigger when deposit flag is off
        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.OFF);
        (trigger, message) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);
        assertEq(message, bytes("Off"));

        // when deposit is facility only it requires capacity
        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.FACILITY_ONLY);
        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(trigger);

        IBaseDepositFacility bdf = depositFacility.facility();
        vm.prank(bdf.management());
        bdf.set_capacity(0);
        (trigger, message) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);
        assertEq(message, bytes("Liquidity"));

        // can trigger if deposit is on
        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.ON);
        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(trigger);
    }

    function test_trigger_forceOnce() public {
        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.ON);

        // temporarily remove deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(0));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, 5 ether);

        // doesnt trigger a report
        (bool trigger, bytes memory message) = strategy.reportTrigger(address(strategy));
        assertTrue(!trigger);
        assertEq(message, bytes("Dust"));

        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.FORCE_ONCE);

        (trigger, ) = strategy.reportTrigger(address(strategy));
        assertTrue(trigger);
    }

    function test_trigger_skipShutdown() public {
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

    function test_report_treshold() public {
        ERC20 WETH = ERC20(tokenAddrs["WETH"]);
        ERC20 styETH = ERC20(tokenAddrs["styETH"]);

        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.ON);

        // temporarily remove deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(0));

        // small deposit doesnt trigger a report
        mintAndDepositIntoStrategy(strategy, user, 1 ether);

        vm.prank(keeper);
        strategy.report();
        assertEq(WETH.balanceOf(address(strategy)), 1 ether);
        assertEq(styETH.balanceOf(address(strategy)), 0);

        // reach the threshold
        mintAndDepositIntoStrategy(strategy, user, 10 ether);

        // restore deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(depositFacility));

        // report is triggered
        vm.prank(keeper);
        strategy.report();
        assertEq(WETH.balanceOf(address(strategy)), 0);
        assertGt(styETH.balanceOf(address(strategy)), 0);
    }

    function test_report_force() public {
        ERC20 WETH = ERC20(tokenAddrs["WETH"]);
        ERC20 styETH = ERC20(tokenAddrs["styETH"]);

        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.OFF);

        // temporarily remove deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(0));

        // small deposit doesnt trigger a report
        mintAndDepositIntoStrategy(strategy, user, 1 ether);

        vm.prank(keeper);
        strategy.report();
        assertEq(WETH.balanceOf(address(strategy)), 1 ether);
        assertEq(styETH.balanceOf(address(strategy)), 0);

        // restore deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(depositFacility));

        // force report
        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.FORCE_ONCE);

        // report is triggered
        vm.prank(keeper);
        strategy.report();
        assertEq(WETH.balanceOf(address(strategy)), 0);
        assertGt(styETH.balanceOf(address(strategy)), 0);
    }

    function test_report_curve() public {
        ERC20 WETH = ERC20(tokenAddrs["WETH"]);
        ERC20 styETH = ERC20(tokenAddrs["styETH"]);

        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.FACILITY_ONLY);

        // remove deposit facility
        vm.prank(GOV);
        strategy.setDepositFacility(address(0));

        // deposit
        mintAndDepositIntoStrategy(strategy, user, 10 ether);

        // facility is not set so nothing happens
        vm.prank(keeper);
        strategy.report();
        assertEq(WETH.balanceOf(address(strategy)), 10 ether);
        assertEq(styETH.balanceOf(address(strategy)), 0);

        // set flag to enable curve deposit
        vm.prank(management);
        strategy.setDepositFlag(DepositFlag.ON);

        // report is now triggered
        vm.prank(keeper);
        strategy.report();
        assertEq(WETH.balanceOf(address(strategy)), 0);
        assertGt(styETH.balanceOf(address(strategy)), 0);
    }
}
