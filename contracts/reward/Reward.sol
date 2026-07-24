// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

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

    Config public config;
    State public state;

    function accrueGlobalIndex() internal {
        uint256 liveBalance = IERC20(config.RewardToken).balanceOf(address(this));
        uint256 claimed = liveBalance - state.prevRewardBalance;
        state.prevRewardBalance = liveBalance;
        require(state.totalBalance != 0, "");
        state.globalIndex += Math.mulDiv(claimed, 1e18, state.totalBalance);
    }

    // return value is decimal
    function settleHolder(address account) internal returns(uint256) {
        Holder storage h = holder[account];
        uint256 accrued = (state.globalIndex - h.index) * h.balance;
        h.pendingRewards += accrued;
        h.index = state.globalIndex;
        return accrued;
    }

    function settleAndPay(address account, address recipient) internal {
        settleHolder(account);
        Holder storage h = holder[account];
        uint256 payoutAmount = h.pendingRewards / 1e18;
        uint256 remainder = h.pendingRewards - (payoutAmount * 1e18);
        require(payoutAmount > 0, "require payoutAmount > 0");
        state.prevRewardBalance -= payoutAmount;
        h.pendingRewards = remainder;
        IERC20(config.RewardToken).transfer(recipient, payoutAmount);
    }
}