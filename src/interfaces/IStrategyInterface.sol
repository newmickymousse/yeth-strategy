// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    //TODO: Add your specific implementation interface in here.
    function curvepool() external view returns (address);
    function yETH() external view returns (address);
    function styETH() external view returns (address);
    function GOV() external view returns (address);
    function sweep(address _token) external;
}
