// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {YEthStakerStrategy, ERC20} from "../../YEthStakerStrategy.sol";
import {IStrategyInterface, DepositFlag} from "../../interfaces/IStrategyInterface.sol";
import {ICurvePool} from "../../interfaces/ICurvePool.sol";
import {ICommonReportTrigger} from "../../interfaces/ICommonReportTrigger.sol";
import {IYEthStaker} from "../../interfaces/IYEthStaker.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

interface IDepositFacility {
    function management() external view returns (address);
    function set_strategy(address) external;
    function facility() external view returns (IBaseDepositFacility);
    function fee_rates() external view returns (uint256, uint256);
}

interface IBaseDepositFacility {
    function management() external view returns (address);
    function operator() external view returns (address);
    function debt() external view returns (uint256);
    function mint() external payable;
    function set_mint_whitelist(address, bool) external;
    function set_capacity(uint256) external;
    function to_pol(uint256) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 50e18; // don't go over max single withdraw
    uint256 public minFuzzAmount = 2e18; // min to deposit is WAD

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    address public constant yETHPool =
        0x2cced4ffA804ADbe1269cDFc22D7904471aBdE63;
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    uint256 public constant WAD = 1e18;

    ICurvePool public constant curvePool = ICurvePool(0x69ACcb968B19a53790f43e57558F5E443A91aF22);
    IDepositFacility public constant depositFacility = IDepositFacility(0x818a8e8240Ac57949E28577B81e9eB9ECD7fc5e1);

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["WETH"]);

        // Set decimals
        decimals = asset.decimals();

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(address(depositFacility), "depositFacility");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new YEthStakerStrategy(
                    GOV,
                    address(curvePool),
                    address(depositFacility)
                )
            )
        );

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);

        vm.prank(management);
        _strategy.acceptManagement();

        // all fee is acceptable
        vm.prank(address(0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7));
        ICommonReportTrigger(0xD98C652f02E7B987e0C258a43BCa9999DF5078cF)
            .setAcceptableBaseFee(1e18);

        // allow strategy to use deposit facility
        vm.prank(depositFacility.management());
        depositFacility.set_strategy(address(_strategy));

        // create some debt in the facility
        IBaseDepositFacility bdf = depositFacility.facility();
        vm.prank(bdf.management());
        bdf.set_mint_whitelist(address(this), true);
        bdf.mint{value: 100 ether}();

        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function setYethMoreValuable(bool _setYethMoreValuable) public {
        address tokenToSwap = _setYethMoreValuable
            ? tokenAddrs["WETH"]
            : tokenAddrs["yETH"];
        address swapper = address(555);
        uint256 amount = 500e18;
        deal(tokenToSwap, swapper, amount);
        vm.startPrank(swapper);
        ERC20(tokenToSwap).approve(strategy.curvePool(), amount);
        ICurvePool yethPool = ICurvePool(strategy.curvePool());
        int128 from = _setYethMoreValuable ? int128(0) : int128(1); // from weth to yeth
        int128 to = _setYethMoreValuable ? int128(1) : int128(0); // from yeth to weth
        yethPool.exchange(from, to, amount, 0);
        vm.stopPrank();
    }

    function earnInterest(uint256 _amount) public {
        IYEthStaker staker = IYEthStaker(strategy.styETH());
        uint256 preBal = ERC20(strategy.yETH()).balanceOf(address(staker));
        deal(strategy.yETH(), strategy.styETH(), preBal + _amount);
        staker.update_amounts();
        skip(2 weeks);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["yETH"] = 0x1BED97CBC3c24A4fb5C069C6E311a967386131f7;
        tokenAddrs["styETH"] = 0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4;
    }
}
