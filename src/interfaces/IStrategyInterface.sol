// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    //TODO: Add your specific implementation interface in here.
    function curvepool() external view returns (address);
    function yETH() external view returns (address);
    function styETH() external view returns (address);
    function swapSlippage() external view returns (uint256);
    function maxSingleWithdraw() external view returns (uint256);
    function sweep(address _token) external;
    function reportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);
    function setDepositFacility(address _depositFacility) external;
    function setMaxSingleWithdraw(uint256 _maxSingleWithdraw) external;
    function addRewardTokenForSwapping(address _from, address _to) external;
    function removeRewardTokenForSwapping(address _from, address _to) external;
    function rewardTokens() external view returns (address[] memory);
    function setTradeFactory(address _tradeFactory) external;
    function setMinDepositAmount(uint256 _minDepositAmount) external;
    function minDepositAmount() external view returns (uint256);
}
