// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IWTRX} from "./IWTRX.sol";
import {ISunSwapRouter} from "./ISunSwapRouter.sol";

contract Reward {
    address constant WTRX = 0x891cdb91d149f23B1a45D9c5Ca78a88d0cB44C18;
    // address constant USDT = 0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C;

    event Swap();
    event GlobalIndexUpdated();
    event BalanceIncreased(address indexed holder, uint256 amount);
    event BalanceDecreased(address indexed holder, uint256 amount);
    event RewardClaimed(address indexed holder, uint256 amount);

    struct Config {
        address hubContract;
        address rewardToken; // usdt
        address sunswapSmartRouter;
        address tokenContract;
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
        uint256 liveBalance = IERC20(config.rewardToken).balanceOf(address(this));
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
        IERC20(config.rewardToken).transfer(recipient, payoutAmount);

        emit RewardClaimed(msg.sender, payoutAmount);
    }

    constructor(address _hubContract, address _rewardToken, address _sunswapSmartRouter, address _tokenContract) {
        config.hubContract = _hubContract;
        config.rewardToken = _rewardToken;
        config.sunswapSmartRouter = _sunswapSmartRouter;
        config.tokenContract = _tokenContract;

        state.globalIndex = 0;
        state.totalBalance = 0;
        state.prevRewardBalance = 0;

        IERC20(WTRX).approve(address(config.sunswapSmartRouter), type(uint256).max);
    }

    // add max slippage calc
    function swapToRewardToken() payable external {
        require(msg.sender == config.hubContract, "");

        IWTRX(WTRX).deposit{value: address(this).balance}();
        address[] memory path = new address[](2);
        path[0] = WTRX;
        path[1] = config.rewardToken;
        string[] memory poolVersion = new string[](1);
        poolVersion[0] = "v3";
        uint256[] memory versionLen = new uint256[](1);
        versionLen[0] = 2;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500;
        fees[1] = 0;
        ISunSwapRouter.SwapData memory data = ISunSwapRouter.SwapData({
            amountIn: IERC20(WTRX).balanceOf(address(this)),
            amountOutMin: 0,
            to: address(this),
            deadline: type(uint256).max
        });
        ISunSwapRouter(config.sunswapSmartRouter).swapExactInput(path, poolVersion, versionLen, fees, data);

        emit Swap();
    }

    function updateGlobalIndex() external {
        require(msg.sender == config.hubContract, "");
        require(state.totalBalance > 0, "");

        accrueGlobalIndex();

        emit GlobalIndexUpdated();
    }

    function increaseBalance(address addr, uint256 amount) external {
        require(msg.sender == config.tokenContract, "");

        settleHolder(addr);
        holder[addr].balance += amount;
        state.totalBalance += amount;

        emit BalanceIncreased(addr, amount);
    }

    function decreaseBalance(address addr, uint256 amount) external {
        require(msg.sender == config.tokenContract, "");
        require(holder[addr].balance >= amount, "");

        settleHolder(addr);
        holder[addr].balance -= amount;
        state.totalBalance -= amount;

        emit BalanceDecreased(addr, amount);
    }

    function claimRewards(address recipient) external {
        settleAndPay(msg.sender, recipient);
    }

    receive() external payable {}
}