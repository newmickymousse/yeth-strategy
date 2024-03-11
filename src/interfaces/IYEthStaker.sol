// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IYEthStaker {
    function deposit(uint256 _assets) external returns (uint256);
    function withdraw(uint256 _assets) external returns (uint256);
}