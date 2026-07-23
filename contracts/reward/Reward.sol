// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract Reward {
    struct Config {
        address hubContract;
        address RewardToken; // usdt
    }

    struct State {
        uint256 globalIndex; // decimal
        uint256 totalBalance;
        uint256 prevRewardBalance;
    }

    struct Holder {
        uint256 balance;
        uint256 index; // decimal
        uint256 pendingRewards; // decimal
    }

    mapping(address => Holder) public holder;
}