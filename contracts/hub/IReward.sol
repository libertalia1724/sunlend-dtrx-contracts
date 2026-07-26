// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IReward {
    function swapToRewardToken() external;
    function updateGlobalIndex() external;
}