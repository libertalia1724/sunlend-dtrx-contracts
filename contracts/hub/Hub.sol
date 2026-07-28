// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {IToken} from "./IToken.sol";
import {IReward} from "./IReward.sol";
import {IThirdPartyAirdrop} from "./IThirdPartyAirdrop.sol";
import {ISwapContract} from "./ISwapContract.sol";

contract Hub {
    Config public config;
    Parameters public parameters;
    State public state;
    CurrentBatch public currentBatch;

    event ValidatorRegistered(address indexed validator);
    event Frozen(uint256 amount);
    event Minted(address indexed from, uint256 frozen, uint256 minted);
    event Burned(address indexed from, uint256 burntAmount, uint256 frozenAmount);
    event FinishBurn(address indexed from, uint256 amount);
    event GlobalIndexUpdated();
    event ValidatorDeregistered(address indexed validator);
    event ParamsUpdated();
    event ConfigUpdated();
    event AirdropTokenSwapped();

    struct Config {
        address owner;
        address rewardContract;
        address tokenContract;
        address airdropContract;
    }

    address private pool;

    address[] public srList;
    uint256[] public tpList;

    constructor(uint256 _epochPeriod, uint256 _unfreezingPeriod, uint256 __pegRecoveryFee, uint256 _erThreshold,
    address _rewardToken, address validator) payable {
        require(msg.value > 0, "");

        config.owner = msg.sender;
        state.exchangeRate = 1e18;
        state.totalFreezeAmount = msg.value;
        state.lastIndexModification = block.timestamp;
        state.lastUnfrozenTime = block.timestamp;
        state.lastProcessedBatch = 0;
        state.actualUnfrozenAmount = 0;

        parameters.epochPeriod = _epochPeriod;
        parameters.unfrozenPeriod = _unfreezingPeriod;
        parameters.pegRecoveryFee = __pegRecoveryFee;
        parameters.erThreshold = _erThreshold;
        parameters.rewardToken = _rewardToken;

        currentBatch.id = 1;
        currentBatch.requestedWithFee = 0;

        validatorWhitelist[validator] = true;
        whiteListCount = 1;
        freezebalancev2(msg.value, 1);
        address[] memory _srList = new address[](1);
        _srList[0] = validator;
        uint256[] memory _tpList = new uint256[](1);
        _tpList[0] = msg.value;
        vote(_srList, _tpList);
        srList = _srList;
        tpList = _tpList;

        emit ValidatorRegistered(validator);
        emit Frozen(msg.value);
    }

    function freeze_(uint256 validatorIndex, address expectedValidator) payable external {
        address validator = srList[validatorIndex];
        require(srList[validatorIndex] == expectedValidator, "");
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
        int256(state.totalFreezeAmount + msg.value);
        uint256 fee = _pegRecoveryFee(mintAmount, deficit);
        uint256 mintAmountWithFee = mintAmount - fee;
        totalIssued += mintAmountWithFee;
        state.totalFreezeAmount += msg.value;
        _recomputeExchangeRate(totalIssued, currentBatch.requestedWithFee);

        freezebalancev2(msg.value, 1);
        tpList[validatorIndex] += msg.value;
        vote(srList, tpList);

        IToken(config.tokenContract).mint(msg.sender, mintAmountWithFee);
        
        emit Minted(msg.sender, msg.value, mintAmountWithFee);
    }

    function _executeUnfreeze(uint256 amount, address onBehalfOf) internal {
        require(amount > 0, "");

        uint256 totalIssued = IERC20(config.tokenContract).totalSupply();
        int256 deficit = int256(totalIssued + currentBatch.requestedWithFee) - int256(state.totalFreezeAmount);
        uint256 fee = _pegRecoveryFee(amount, deficit);
        uint256 amountWithFee = amount - fee;
        currentBatch.requestedWithFee += amountWithFee;
        _recordUnfreezeEntry(onBehalfOf, currentBatch.id, amountWithFee);
        totalIssued -= amount;
        _recomputeExchangeRate(totalIssued, currentBatch.requestedWithFee);

        if ((block.timestamp - state.lastUnfrozenTime) > parameters.epochPeriod) {
            uint256 unfreezeAmount = Math.mulDiv(currentBatch.requestedWithFee, state.exchangeRate, 1e18);
            state.totalFreezeAmount -= unfreezeAmount;
            unfreezeHistory[currentBatch.id].batchId = currentBatch.id;
            unfreezeHistory[currentBatch.id].time = block.timestamp;
            unfreezeHistory[currentBatch.id].amount = currentBatch.requestedWithFee;
            unfreezeHistory[currentBatch.id].appliedExchangeRate = state.exchangeRate;
            unfreezeHistory[currentBatch.id].withdrawRate = state.exchangeRate;
            unfreezeHistory[currentBatch.id].released = false;

            currentBatch.id += 1;
            currentBatch.requestedWithFee = 0;
            state.lastUnfrozenTime = block.timestamp;

            unfreezebalancev2(unfreezeAmount, 1);

            uint256 len = srList.length;
            for (uint256 i = 0; i < len; i++) {
                tpList[i] = voteCount(address(this), srList[i]);
            }
        }
        ERC20Burnable(config.tokenContract).burnFrom(onBehalfOf, amount);

        emit Burned(onBehalfOf, amount, amountWithFee);
    }

    function unfreeze_(uint256 amount) external {
        _executeUnfreeze(amount, msg.sender);
    }

    function withdrawUnfrozen() external {
        withdrawexpireunfreeze();
        uint256 hubBalance = address(this).balance;
        _processWithdrawRate(block.timestamp - parameters.unfrozenPeriod, hubBalance);
        uint256 payout = withdrawableAmount(msg.sender, block.timestamp - parameters.unfrozenPeriod);
        require(payout > 0);
        _clearReleasedEntries(msg.sender);
        state.prevHubBalance = hubBalance - payout;

        (bool success, ) = (msg.sender).call{value: payout}("");
        require(success, "trx transfer reverted");

        emit FinishBurn(address(this), payout);
    }

    function updateGlobalIndex() public {
        require(config.rewardContract != address(0), "");

        state.lastIndexModification = block.timestamp;

        uint256 reward = withdrawreward();
        (bool success, ) = (config.rewardContract).call{value: reward}("");
        require(success, "trx transfer reverted");
        IReward(config.rewardContract).swapToRewardToken();
        IReward(config.rewardContract).updateGlobalIndex();

        emit GlobalIndexUpdated();
    }

    function registerValidator(address validator) external {
        require(msg.sender == config.owner, "");
        require(!validatorWhitelist[validator], "");
        require(isSrCandidate(validator), "");
        require(srList.length < 30, "");

        validatorWhitelist[validator] = true;
        whiteListCount += 1;
        srList.push(validator);
        tpList.push(0);

        emit ValidatorRegistered(validator);
    }

    function deregisterValidator(uint256 validatorIndex) external {
        address validator = srList[validatorIndex];
        require(msg.sender == config.owner, "");
        require(validatorWhitelist[validator] == true, "");
        require(whiteListCount > 1, "");

        validatorWhitelist[validator] = false;
        whiteListCount -= 1;

        uint256 validatorTp = tpList[validatorIndex];
        srList[validatorIndex] = srList[srList.length - 1];
        srList.pop();
        tpList[validatorIndex] = tpList[tpList.length - 1];
        tpList.pop();

        uint256 remainingTotal = 0;
        for (uint256 i = 0; i < tpList.length; i++) {
            remainingTotal += tpList[i];
        }
        require(remainingTotal > 0, "");

        uint256 distributed = 0;
        for (uint256 i = 0; i < tpList.length - 1; i++) {
            uint256 share = Math.mulDiv(validatorTp, tpList[i], remainingTotal);
            tpList[i] += share;
            distributed += share;
        }
        tpList[tpList.length - 1] += (validatorTp - distributed);

        vote(srList, tpList);

        emit ValidatorDeregistered(validator);
    }

    function updateParams(uint256 _epochPeriod, uint256 _unfreezingPeriod, uint256 __pegRecoveryFee,
    uint256 _erThreshold) external {
        require(msg.sender == config.owner, "");

        parameters.epochPeriod = _epochPeriod;
        parameters.unfrozenPeriod = _unfreezingPeriod;
        parameters.pegRecoveryFee = __pegRecoveryFee;
        parameters.erThreshold = _erThreshold;

        emit ParamsUpdated();
    }

    function updateConfig(address _owner, address _rewardContract, address _tokenContract,
    address _airdropContract) external {
        require(msg.sender == config.owner, "");

        config.owner = _owner;
        config.rewardContract = _rewardContract;
        config.tokenContract = _tokenContract;
        config.airdropContract = _airdropContract;

        emit ConfigUpdated();
    }

    struct Parameters {
        uint256 epochPeriod; // recommended 2 days
        uint256 unfrozenPeriod; // 14 days
        uint256 pegRecoveryFee; // decimal
        uint256 erThreshold; // decimal
        address rewardToken; // usdt
    }

    struct State {
        uint256 exchangeRate; // decimal
        uint256 totalFreezeAmount;
        uint256 lastIndexModification;
        uint256 prevHubBalance;
        int256 actualUnfrozenAmount;
        uint256 lastUnfrozenTime;
        uint64 lastProcessedBatch;
    }

    struct CurrentBatch {
        uint64 id;
        uint256 requestedWithFee;
    }

    mapping(address => bool) public validatorWhitelist;
    uint256 public whiteListCount;

    mapping(address => mapping(uint64 => uint256)) public unfreezeWaitList;

    struct UnfreezeHistory {
        uint64 batchId;
        uint256 time;
        uint256 amount;
        uint256 appliedExchangeRate; // decimal
        uint256 withdrawRate; // decimal
        bool released;
    }

    mapping(uint64 => UnfreezeHistory) public unfreezeHistory;

    function _recomputeExchangeRate(uint256 newTotalIssued, uint256 requestedWithFee) internal {
        uint256 actualSupply = newTotalIssued + requestedWithFee;

        if (state.totalFreezeAmount == 0 || actualSupply == 0) {
            state.exchangeRate = 1e18;
        } else {
            state.exchangeRate = (state.totalFreezeAmount * 1e18) / actualSupply;
        }
    }

    function _pegRecoveryFee(uint256 requestedAmount, int256 deficit) internal view returns(uint256) {
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

    function _processWithdrawRate(uint256 historicalTime, uint256 hubBalance) internal {
        int256 balanceDelta = int256(hubBalance) - int256(state.prevHubBalance);
        state.actualUnfrozenAmount += balanceDelta;

        uint256 totalExpected = 0;
        uint256 batchCount = 0;
        uint64 i = state.lastProcessedBatch + 1;

        while (true) {
            UnfreezeHistory storage h = unfreezeHistory[i];
            if (h.time == 0) break;
            if (h.time > historicalTime) break;
            if (h.released) break;

            totalExpected += Math.mulDiv(h.amount, h.withdrawRate, 1e18);
            batchCount += 1;
            i += 1;
        }

        if (batchCount >= 1) {
            require(totalExpected > 0, "unexpected zero totalExpected");

            int256 shortfall = int256(totalExpected) - state.actualUnfrozenAmount;

            uint64 j = state.lastProcessedBatch + 1;
            while (true) {
                UnfreezeHistory storage h = unfreezeHistory[j];
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

        state.actualUnfrozenAmount = 0;
    }

    mapping(address => uint64[]) public userBatchIds;

    function _recordUnfreezeEntry(address user, uint64 batchId, uint256 amount) internal {
        if (unfreezeWaitList[user][batchId] == 0) {
            userBatchIds[user].push(batchId);
        }
        unfreezeWaitList[user][batchId] += amount;
    }

    function _clearReleasedEntries(address user) internal {
        uint64[] storage batchIds = userBatchIds[user];
        uint256 i = 0;

        while (i < batchIds.length) {
            uint64 batchId = batchIds[i];

            if (unfreezeHistory[batchId].released) {
                unfreezeWaitList[user][batchId] = 0;
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
            uint256 amt = unfreezeWaitList[user][batchId];
            if (amt == 0) continue;

            UnfreezeHistory storage h = unfreezeHistory[batchId];

            if (h.released || h.time < asOf) {
                total += Math.mulDiv(amt, h.withdrawRate, 1e18);
            }
        }
        return total;
    }

    function claimAirdrop(address airdropTokenContract, address airdropContract, address airdropSwapContract,
    uint8 stage, uint256 amount, bytes32[] calldata proof, uint256 minAmountOut, address to) external {
        require(msg.sender == config.airdropContract, "");

        IThirdPartyAirdrop(airdropContract).claim(stage, amount, proof);
        _swapHook(airdropTokenContract, airdropSwapContract, minAmountOut, to);
    }

    function _swapHook(address airdropTokenContract, address airdropSwapContract, uint256 minAmountOut, address to) internal {
        require(IERC20(airdropTokenContract).balanceOf(address(this)) > 0, "");

        pool = airdropSwapContract;
        bool zeroForOne = (airdropTokenContract == ISwapContract(pool).token0());

        (int256 amount0, int256 amount1) = ISwapContract(pool).swap(
            address(this),
            zeroForOne,
            int256(IERC20(airdropTokenContract).balanceOf(address(this))),
            zeroForOne
                ? 4295128740
                : 1461446703485210103287273052203988822378723970341,
            abi.encode(airdropTokenContract)
        );

        uint256 amountOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);

        require(amountOut >= minAmountOut, "slippage too high");

        if (zeroForOne) {
            IERC20(ISwapContract(pool).token1()).transfer(to, amountOut);
        } else {
            IERC20(ISwapContract(pool).token0()).transfer(to, amountOut);
        }

        emit AirdropTokenSwapped();
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        require(msg.sender == pool, "");
        address tokenIn = abi.decode(data, (address));
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        IERC20(tokenIn).transfer(msg.sender, amountToPay);
    }

    receive() external payable {}
}