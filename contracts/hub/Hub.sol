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
        uint256 actualUnbondedAmount;
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
            state.exchangeRate = 1;
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
}