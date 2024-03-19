// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {IYEthPool} from "../interfaces/IYEthPool.sol";

contract OperationWethMoreValuableTest is Setup {
    function setUp() public virtual override {
        super.setUp();
        // setYethMoreValuable(false);
    }

    function test_deposit_weth_more(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 maxLossTolerance = (strategy.swapSlippage() * _amount) /
            MAX_BPS;

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
        assertLt(loss, maxLossTolerance, "!loss");

        // all funds are deposited
        assertEq(asset.balanceOf(address(strategy)), 0, "!final balance");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0, "!totalAssets=0");

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount - maxLossTolerance,
            "!final balance"
        );
    }

    function test_profitableReport_weth(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        uint256 maxLossTolerance = (strategy.swapSlippage() * _amount) /
            MAX_BPS;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        earnInterest(100e18);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertLt(loss, maxLossTolerance, "!loss");

        skip(strategy.profitMaxUnlockTime());

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

    function test_profitableReport_withFees_weth(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        uint256 maxLossTolerance = (strategy.swapSlippage() * _amount) /
            MAX_BPS;

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        earnInterest(100e18);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertLt(loss, maxLossTolerance, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount - maxLossTolerance,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_deposit_wethMoreValue_withDepositFacility_fullAmount(
        uint256 _amount,
        uint8 _depositFacilityFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        vm.assume(_depositFacilityFactor > 0 && _depositFacilityFactor < 10);

        uint256 maxLossTolerance = (strategy.swapSlippage() * _amount) /
            MAX_BPS;

        // Airdrop yETH to deposit facility
        deal(
            address(strategy.yETH()),
            address(depositFacility),
            (_amount * _depositFacilityFactor) / 5
        );
        deal(
            address(strategy.asset()),
            address(depositFacility),
            (_amount * _depositFacilityFactor) / 5
        );

        vm.prank(management);
        strategy.setDepositFacility(address(depositFacility));

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
        assertLt(loss, maxLossTolerance, "!loss");

        // all funds are deposited
        assertEq(asset.balanceOf(address(strategy)), 0, "!final balance");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0, "!totalAssets=0");

        assertEq(
            ERC20(strategy.styETH()).balanceOf(address(strategy)),
            0,
            "!styETH balance"
        );
        assertEq(
            ERC20(strategy.yETH()).balanceOf(address(strategy)),
            0,
            "!yETH balance"
        );

        // shares are worth less because of esstimateTotalAssets uses pesimistic estimate
        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount - maxLossTolerance,
            "!final balance"
        );
    }

    function test_profitableReport_weth_withDepositFacility(
        uint256 _amount,
        uint16 _profitFactor,
        uint8 _depositFacilityFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        vm.assume(_depositFacilityFactor > 0 && _depositFacilityFactor < 10);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        uint256 maxLossTolerance = (strategy.swapSlippage() * _amount) /
            MAX_BPS;

        // Airdrop yETH to deposit facility
        deal(
            address(strategy.yETH()),
            address(depositFacility),
            (_amount * _depositFacilityFactor) / 5
        );
        deal(
            address(strategy.asset()),
            address(depositFacility),
            (_amount * _depositFacilityFactor) / 5
        );

        vm.prank(management);
        strategy.setDepositFacility(address(depositFacility));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        earnInterest(100e18);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertLt(loss, maxLossTolerance, "!loss");

        skip(strategy.profitMaxUnlockTime());

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

    function test_profitableReport_withFees_weth_withDepositFacility(
        uint256 _amount,
        uint16 _profitFactor,
        uint8 _depositFacilityFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        vm.assume(_depositFacilityFactor > 0 && _depositFacilityFactor < 10);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        uint256 maxLossTolerance = (strategy.swapSlippage() * _amount) /
            MAX_BPS;

        // Airdrop yETH to deposit facility
        deal(
            address(strategy.yETH()),
            address(depositFacility),
            (_amount * _depositFacilityFactor) / 5
        );
        deal(
            address(strategy.asset()),
            address(depositFacility),
            (_amount * _depositFacilityFactor) / 5
        );

        vm.prank(management);
        strategy.setDepositFacility(address(depositFacility));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        earnInterest(100e18);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertLt(loss, maxLossTolerance, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount - maxLossTolerance,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }
}
