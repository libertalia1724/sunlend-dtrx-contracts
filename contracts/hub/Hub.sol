// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {IToken} from "./IToken.sol";

contract Hub {
    Config public config;
    Parameters public parameters;
    State public state;
    CurrentBatch public currentBatch;

    event ValidatorRegistered(address indexed validator);
    event Bonded(uint256 amount);
    event Minted(address indexed from, uint256 bonded, uint256 minted);
    event Burned(address indexed from, uint256 burntAmount, uint256 unbondedAmount);
    event FinishBurn(address indexed from, uint256 amount);

    struct Config {
        address owner;
        address rewardContract;
        address tokenContract;
    }

    constructor(uint256 _epochPeriod, uint256 _unbondingPeriod, uint256 _pegRecoveryFee, uint256 _erThreshold,
    address _rewardToken, address validator) payable {
        require(msg.value > 0, "");

        config.owner = msg.sender;
        state.exchangeRate = 1e18;
        state.totalBondAmount = msg.value;
        state.lastIndexModification = block.timestamp;
        state.lastUnbondedTime = block.timestamp;
        state.lastProcessedBatch = 0;
        state.actualUnbondedAmount = 0;

        parameters.epochPeriod = _epochPeriod;
        parameters.unbondingPeriod = _unbondingPeriod;
        parameters.pegRecoveryFee = _pegRecoveryFee;
        parameters.erThreshold = _erThreshold;
        parameters.rewardToken = _rewardToken;

        currentBatch.id = 1;
        currentBatch.requestedWithFee = 0;

        // registerValidator(validator);
        freezebalancev2(msg.value, 1);
        address[] memory srList = new address[](1);
        srList[0] = validator;
        uint256[] memory tpList = new uint256[](1);
        tpList[0] = msg.value;
        vote(srList, tpList);

        emit ValidatorRegistered(validator);
        emit Bonded(msg.value);
    }

    function bond(address validator) payable external {
        require(validatorWhitelist[validator] == true, "");
        require(msg.value > 0, "");

        uint256 totalIssued;
        if (config.tokenContract != address(0)) {
            totalIssued = IERC20(config.tokenContract).totalSupply();
        } else {
            totalIssued = 0;
        }

        uint256 mintAmount = Math.mulDiv(msg.value, 1e18, state.exchangeRate);
        int256 deficit = int256(totalIssued + mintAmount + currentBatch.requestedWithFee) -
        int256(state.totalBondAmount + msg.value);
        uint256 fee = pegRecoveryFee(mintAmount, deficit);
        uint256 mintAmountWithFee = mintAmount - fee;
        totalIssued += mintAmountWithFee;
        state.totalBondAmount += msg.value;
        recomputeExchangeRate(totalIssued, currentBatch.requestedWithFee);

        freezebalancev2(msg.value, 1);
        address[] memory srList = new address[](1);
        srList[0] = validator;
        uint256[] memory tpList = new uint256[](1);
        tpList[0] = msg.value;
        vote(srList, tpList);

        IToken(config.tokenContract).mint(msg.sender, mintAmountWithFee);
        
        emit Minted(msg.sender, msg.value, mintAmountWithFee);
    }

    function executeUnbond(uint256 amount, address onBehalfOf) internal {
        require(amount > 0, "");

        uint256 totalIssued = IERC20(config.tokenContract).totalSupply();
        int256 deficit = int256(totalIssued + currentBatch.requestedWithFee) - int256(state.totalBondAmount);
        uint256 fee = pegRecoveryFee(amount, deficit);
        uint256 amountWithFee = amount - fee;
        currentBatch.requestedWithFee += amountWithFee;
        _recordUnbondEntry(onBehalfOf, currentBatch.id, amountWithFee);
        totalIssued -= amount;
        recomputeExchangeRate(totalIssued, currentBatch.requestedWithFee);

        if ((block.timestamp - state.lastUnbondedTime) > parameters.epochPeriod) {
            uint256 unbondAmount = Math.mulDiv(currentBatch.requestedWithFee, state.exchangeRate, 1e18);
            state.totalBondAmount -= unbondAmount;
            unbondHistory[currentBatch.id].batchId = currentBatch.id;
            unbondHistory[currentBatch.id].time = block.timestamp;
            unbondHistory[currentBatch.id].amount = currentBatch.requestedWithFee;
            unbondHistory[currentBatch.id].appliedExchangeRate = state.exchangeRate;
            unbondHistory[currentBatch.id].withdrawRate = state.exchangeRate;
            unbondHistory[currentBatch.id].released = false;

            currentBatch.id += 1;
            currentBatch.requestedWithFee = 0;
            state.lastUnbondedTime = block.timestamp;

            unfreezebalancev2(unbondAmount, 1);
        }
        ERC20Burnable(config.tokenContract).burnFrom(onBehalfOf, amount);

        emit Burned(onBehalfOf, amount, amountWithFee);
    }

    function unbond(uint256 amount) external {
        executeUnbond(amount, msg.sender);
    }

    function withdrawUnbonded() external {
        uint256 hubBalance = address(this).balance;
        processWithdrawRate(block.timestamp - parameters.unbondingPeriod, hubBalance);
        uint256 payout = withdrawableAmount(msg.sender, block.timestamp - parameters.unbondingPeriod);
        require(payout > 0);
        _clearReleasedEntries(msg.sender);
        state.prevHubBalance = hubBalance - payout;

        (bool success, ) = (msg.sender).call{value: payout}("");
        require(success, "trx transfer reverted");

        emit FinishBurn(address(this), payout);
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

    function pegRecoveryFee(uint256 requestedAmount, int256 deficit) internal view returns(uint256) {
        if (state.exchangeRate >= parameters.erThreshold) {
            return 0;
        }
        if (deficit <= 0) {
            return 0;
        }

        uint256 maxFee = Math.mulDiv(requestedAmount, parameters.pegRecoveryFee, 1e18);
        uint256 actualFee = Math.min(maxFee, uint256(deficit));
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

    function _clearReleasedEntries(address user) internal {
        uint64[] storage batchIds = userBatchIds[user];
        uint256 i = 0;

        while (i < batchIds.length) {
            uint64 batchId = batchIds[i];

            if (unbondHistory[batchId].released) {
                unbondWaitList[user][batchId] = 0;
                batchIds[i] = batchIds[batchIds.length - 1];
                batchIds.pop();
            } else {
                i++;
            }
        }
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