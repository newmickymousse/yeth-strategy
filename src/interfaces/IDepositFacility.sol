// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IDepositFacility {
    function available() external view returns (uint256 _deposit, uint256 _withdraw);
    function deposit(uint256 _amount, bool _stake) external returns (uint256);
    function withdraw(uint256 _amount) external;
}
