// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ICurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) external returns (uint256);
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
}
