// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IYEthStaker {
    function deposit(uint256 _assets) external returns (uint256);
    function deposit(
        uint256 _assets,
        address _receiver
    ) external returns (uint256);
    function withdraw(uint256 _assets) external returns (uint256);
    function redeem(uint256 _shares) external returns (uint256);
    function balanceOf(address _user) external view returns (uint256);
    function convertToAssets(uint256 _shares) external view returns (uint256);
    function convertToShares(uint256 _assets) external view returns (uint256);
    function maxWithdraw(address _user) external view returns (uint256);
    function update_amounts() external;
}
