// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface, ICommonReportTrigger, IBaseDepositFacility} from "./utils/Setup.sol";
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
        assertEq(strategy.maxSingleWithdraw(), 50e18);
        assertEq(strategy.swapSlippage(), 80);
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        earnInterest(100e18);
        assertGt(strategy.estimatedTotalAssets(), _amount);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw funds
        vm.prank(user);
        strategy.redeem(minFuzzAmount, user, user);

        assertGt(
            asset.balanceOf(user),
            balanceBefore + minFuzzAmount,
            "!final balance"
        );
    }

    function test_deposit_noCapacity() public {
        // If deposit facility is full, assets will stay in strategy
        IBaseDepositFacility facility = depositFacility.facility();
        vm.prank(facility.management());
        facility.set_capacity(0);

        uint256 _amount = 1e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(asset.balanceOf(address(strategy)), _amount, "!final balance");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0, "!totalAssets=0");

        assertEq(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_deposit_partialCapacity() public {
        // If deposit facility is almost full, some assets will stay in strategy
        IBaseDepositFacility facility = depositFacility.facility();
        uint256 debt = facility.debt();
        uint256 available = 1 ether;
        vm.prank(facility.management());
        facility.set_capacity(debt + available);

        uint256 _amount = 3 ether;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(asset.balanceOf(address(strategy)), _amount - available, "!final balance");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw free funds
        vm.prank(user);
        strategy.redeem(_amount - available, user, user);

        assertEq(strategy.totalAssets(), available, "!totalAssets");

        assertEq(
            asset.balanceOf(user),
            balanceBefore + _amount - available,
            "!final balance"
        );
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

    function test_setCurvePool() public {
        // Setting new curve pool moves allowances
        address oldPool = strategy.curvePool();
        address newPool = address(1);

        vm.expectRevert(bytes("!GOV"));
        strategy.setCurvePool(newPool);

        ERC20 WETH = ERC20(tokenAddrs["WETH"]);
        ERC20 yETH = ERC20(tokenAddrs["yETH"]);

        assertGt(WETH.allowance(address(strategy), oldPool), 0);
        assertGt(yETH.allowance(address(strategy), oldPool), 0);
        assertEq(WETH.allowance(address(strategy), newPool), 0);
        assertEq(yETH.allowance(address(strategy), newPool), 0);
        
        vm.prank(GOV);
        strategy.setCurvePool(newPool);

        assertEq(WETH.allowance(address(strategy), oldPool), 0);
        assertEq(yETH.allowance(address(strategy), oldPool), 0);
        assertGt(WETH.allowance(address(strategy), newPool), 0);
        assertGt(yETH.allowance(address(strategy), newPool), 0);
    }

    function test_unsetCurvePool() public {
        address oldPool = strategy.curvePool();
        vm.prank(GOV);
        strategy.setCurvePool(address(0));

        assertEq(ERC20(tokenAddrs["WETH"]).allowance(address(strategy), oldPool), 0);
        assertEq(ERC20(tokenAddrs["yETH"]).allowance(address(strategy), oldPool), 0);

        vm.prank(GOV);
        vm.expectRevert();
        strategy.setDepositFacility(address(0));
    }

    function test_setDepositFacility() public {
        // Setting new deposit facility moves allowances
        address oldFacility = strategy.depositFacility();
        address newFacility = address(1);

        vm.expectRevert(bytes("!GOV"));
        strategy.setDepositFacility(newFacility);

        ERC20 WETH = ERC20(tokenAddrs["WETH"]);
        ERC20 yETH = ERC20(tokenAddrs["yETH"]);

        assertGt(WETH.allowance(address(strategy), oldFacility), 0);
        assertGt(yETH.allowance(address(strategy), oldFacility), 0);
        assertEq(WETH.allowance(address(strategy), newFacility), 0);
        assertEq(yETH.allowance(address(strategy), newFacility), 0);
        
        vm.prank(GOV);
        strategy.setDepositFacility(newFacility);

        assertEq(WETH.allowance(address(strategy), oldFacility), 0);
        assertEq(yETH.allowance(address(strategy), oldFacility), 0);
        assertGt(WETH.allowance(address(strategy), newFacility), 0);
        assertGt(yETH.allowance(address(strategy), newFacility), 0);
    }

    function test_unsetDepositFacility() public {
        address oldFacility = strategy.depositFacility();

        vm.prank(GOV);
        strategy.setDepositFacility(address(0));

        assertEq(ERC20(tokenAddrs["WETH"]).allowance(address(strategy), oldFacility), 0);
        assertEq(ERC20(tokenAddrs["yETH"]).allowance(address(strategy), oldFacility), 0);

        vm.prank(GOV);
        vm.expectRevert();
        strategy.setCurvePool(address(0));
    }
}
