// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IReward {
    function swapToRewardToken() external;
    function updateGlobalIndex() external;
}