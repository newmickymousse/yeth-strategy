// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IYEthPool {
    function add_liquidity(uint256[] calldata _amounts, uint256 _min_lp_amount) external returns (uint256);
    function remove_liquidity(uint256 _lpAmount, uint256[] calldata _min_amounts) external returns (uint256);
}
