// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface, IDepositFacility, IBaseDepositFacility} from "./utils/Setup.sol";
import {IYEthPool} from "../interfaces/IYEthPool.sol";

contract OperationCurvePool is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_withdraw_facility() public {
        uint256 _amount = 10 ether;
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (, uint256 feeRate) = IDepositFacility(strategy.depositFacility()).fee_rates();

        uint256 balanceBefore = asset.balanceOf(user);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(
            asset.balanceOf(user),
            balanceBefore + _amount * (10_000 - feeRate) / 10_000,
            "!final balance"
        );
    }

    function test_withdraw_curve() public {
        uint256 _amount = 10 ether;
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (, uint256 feeRate) = IDepositFacility(strategy.depositFacility()).fee_rates();
        IBaseDepositFacility bdf = IDepositFacility(strategy.depositFacility()).facility();

        // Empty out deposit facility
        vm.prank(bdf.operator());
        bdf.to_pol(address(bdf).balance);
        
        uint256 balanceBefore = asset.balanceOf(user);
        uint256 cuveBalanceBefore = asset.balanceOf(address(curvePool));

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Check that we used Curve
        assertLt(asset.balanceOf(address(curvePool)), cuveBalanceBefore, "!curve balance");
        // We wouldve gotten more if deposit facility had capacity
        assertLt(
            asset.balanceOf(user),
            balanceBefore + _amount * (10_000 - feeRate) / 10_000,
            "!final balance"
        );
    }

    function test_withdraw_combination() public {
        uint256 _amount = 30 ether;
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (, uint256 feeRate) = IDepositFacility(strategy.depositFacility()).fee_rates();
        IBaseDepositFacility bdf = IDepositFacility(strategy.depositFacility()).facility();

        // Empty out deposit facility
        vm.prank(bdf.operator());
        bdf.to_pol(address(bdf).balance - 20 ether);
        
        uint256 balanceBefore = asset.balanceOf(user);
        uint256 cuveBalanceBefore = asset.balanceOf(address(curvePool));

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Check that we used both
        assertEq(address(bdf).balance, 0, "!facility balance");
        assertLt(asset.balanceOf(address(curvePool)), cuveBalanceBefore, "!curve balance");

        // We wouldve gotten more if deposit facility had more capacity
        assertLt(
            asset.balanceOf(user),
            balanceBefore + _amount * (10_000 - feeRate) / 10_000,
            "!final balance"
        );
    }

    function test_withdraw_aboveMax() public {
        // Deposit into strategy
        uint256 _amount = 50 ether;
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Report profit
        vm.prank(keeper);
        strategy.report();

        assertEq(asset.balanceOf(address(strategy)), 0, "!deposit");

        vm.prank(management);
        strategy.setMaxSingleWithdraw(1 ether);

        // Withdraw all funds
        vm.expectRevert(bytes("ERC4626: redeem more than max"));
        vm.prank(user);
        strategy.redeem(_amount, user, user);
    }
}
