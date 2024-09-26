// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

enum DepositFlag { OFF, FORCE_ONCE, FACILITY_ONLY, ON }

interface IStrategyInterface is IStrategy {
    function curvePool() external view returns (address);
    function depositFacility() external view returns (address);
    function yETH() external view returns (address);
    function styETH() external view returns (address);
    function swapSlippage() external view returns (uint256);
    function maxSingleWithdraw() external view returns (uint256);
    function sweep(address _token) external;
    function reportTrigger(address _strategy) external view returns (bool, bytes memory);
    function minDepositAmount() external view returns (uint256);
    function setCurvePool(address) external;
    function setDepositFacility(address) external;
    function setMaxSingleWithdraw(uint256 _maxSingleWithdraw) external;
    function setMinDepositAmount(uint256 _minDepositAmount) external;
    function setDepositFlag(DepositFlag _flag) external;
    function estimatedTotalAssets() external view returns (uint256);
}
