// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IGenericGovernance {
    function vote(uint256 _idx, uint256 _yea, uint256 _nay, uint256 _abstain) external;
}

interface IWeightGovernance {
    function vote(uint256[] calldata _votes) external;
}
