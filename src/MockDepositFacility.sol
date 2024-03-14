// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYEthStaker} from "./interfaces/IYEthStaker.sol";
import {IDepositFacility} from "./interfaces/IDepositFacility.sol";

contract MockDepositFacility is IDepositFacility {
    using SafeERC20 for ERC20;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant yETH =
        ERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IYEthStaker public constant styETH =
        IYEthStaker(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);

    constructor() {
        yETH.approve(address(styETH), type(uint256).max);
    }

    function available() external view returns (uint256 _deposit, uint256 _withdraw) {
        _deposit = yETH.balanceOf(address(this));
        _withdraw = WETH.balanceOf(address(this));
    }

    function deposit(uint256 _amount, bool _stake) external returns (uint256) {
        WETH.safeTransferFrom(msg.sender, address(this), _amount);
        if (_stake) {
            return styETH.deposit(_amount, msg.sender);
        }
        else {
            yETH.safeTransfer(msg.sender, _amount);
            return _amount;
        }
    }

    function withdraw(uint256 _amount) external {
        yETH.safeTransferFrom(msg.sender, address(this), _amount);
        WETH.safeTransfer(msg.sender, _amount);
    }
}
