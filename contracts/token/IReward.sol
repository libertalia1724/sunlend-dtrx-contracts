// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IReward {
    function decreaseBalance(address addr, uint256 amount) external;
    function increaseBalance(address addr, uint256 amount) external;
}