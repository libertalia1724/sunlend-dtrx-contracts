// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Hub {
    Config public config;
    Parameters public parameters;
    State public state;
    CurrentBatch public currentBatch;

    bool public initialized;

    struct Config {
        address owner;
        address rewardContract;
        address tokenContract;
    }

    constructor() {
        config.owner = msg.sender;
    }

    function initialize(address _rewardContract, address _tokenContract) public {
        require(initialized == false, "contract already initialized");
        require(config.owner == msg.sender, "unauthorized access");
        initialized = true;

        config.rewardContract = _rewardContract;
        config.tokenContract = _tokenContract;
    }

    struct Parameters {
        uint256 epochPeriod; // recommended 2 days
        uint256 unbondingPeriod; // 14 days
        uint256 pegRecoveryFee; // decimal
        uint256 erThreshold; // decimal
        address rewardToken; // usdt
    }

    struct State {
        uint256 exchangeRate; // decimal
        uint256 totalBondAmount;
        uint256 lastIndexModification;
        uint256 prevHubBalance;
        int256 actualUnbondedAmount;
        uint256 lastUnbondedTime;
        uint64 lastProcessedBatch;
    }

    struct CurrentBatch {
        uint64 id;
        uint256 requestedWithFee;
    }

    mapping(address => bool) public validatorWhitelist;

    mapping(address => mapping(uint64 => uint256)) public unbondWaitList;

    struct UnbondHistory {
        uint64 batchId;
        uint256 time;
        uint256 amount;
        uint256 appliedExchangeRate; // decimal
        uint256 withdrawRate; // decimal
        bool released;
    }

    mapping(uint64 => UnbondHistory) public unbondHistory;

    function recomputeExchangeRate(uint256 newTotalIssued, uint256 requestedWithFee) internal {
        uint256 actualSupply = newTotalIssued + requestedWithFee;

        if (state.totalBondAmount == 0 || actualSupply == 0) {
            state.exchangeRate = 1e18;
        } else {
            state.exchangeRate = (state.totalBondAmount * 1e18) / actualSupply;
        }
    }

    function pegRecoveryFee(uint256 requestedAmount, uint256 deficit) internal view returns(uint256) {
        if (state.exchangeRate >= parameters.erThreshold) {
            return 0;
        }

        uint256 maxFee = Math.mulDiv(requestedAmount, parameters.pegRecoveryFee, 1e18);
        uint256 actualFee = Math.min(maxFee, deficit);
        return actualFee;
    }

    function processWithdrawRate(uint256 historicalTime, uint256 hubBalance) internal {
        int256 balanceDelta = int256(hubBalance) - int256(state.prevHubBalance);
        state.actualUnbondedAmount += balanceDelta;

        uint256 totalExpected = 0;
        uint256 batchCount = 0;
        uint64 i = state.lastProcessedBatch + 1;

        while (true) {
            UnbondHistory storage h = unbondHistory[i];
            if (h.time == 0) break;
            if (h.time > historicalTime) break;
            if (h.released) break;

            totalExpected += Math.mulDiv(h.amount, h.withdrawRate, 1e18);
            batchCount += 1;
            i += 1;
        }

        if (batchCount >= 1) {
            require(totalExpected > 0, "unexpected zero totalExpected");

            int256 shortfall = int256(totalExpected) - state.actualUnbondedAmount;

            uint64 j = state.lastProcessedBatch + 1;
            while (true) {
                UnbondHistory storage h = unbondHistory[j];
                if (h.time == 0) break;
                if (h.time > historicalTime) break;
                if (h.released) break;

                uint256 expected = Math.mulDiv(h.amount, h.withdrawRate, 1e18);
                uint256 weight = Math.mulDiv(expected, 1e18, totalExpected);

                int256 shortfallI = (shortfall * int256(weight)) / int256(1e18);
                int256 actualI = int256(expected) - shortfallI;
                require(actualI >= 0, "negative payout computed");

                h.withdrawRate = Math.mulDiv(uint256(actualI), 1e18, h.amount);
                h.released = true;
                state.lastProcessedBatch = j;
                j += 1;
            }
        }

        state.actualUnbondedAmount = 0;
    }

    mapping(address => uint64[]) public userBatchIds;

    function _recordUnbondEntry(address user, uint64 batchId, uint256 amount) internal {
        if (unbondWaitList[user][batchId] == 0) {
            userBatchIds[user].push(batchId);
        }
        unbondWaitList[user][batchId] += amount;
    }

    function withdrawableAmount(address user, uint256 asOf) public view returns(uint256) {
        uint256 total = 0;
        uint64[] storage batchIds = userBatchIds[user];

        for (uint256 i = 0; i < batchIds.length; i++) {
            uint64 batchId = batchIds[i];
            uint256 amt = unbondWaitList[user][batchId];
            if (amt == 0) continue;

            UnbondHistory storage h = unbondHistory[batchId];

            if (h.released || h.time < asOf) {
                total += Math.mulDiv(amt, h.withdrawRate, 1e18);
            }
        }
        return total;
    }
}