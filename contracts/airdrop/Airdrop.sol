// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IHub} from "./IHub.sol";

contract Airdrop {
    struct Config {
        address owner;
        address hubContract;
        address rewardContract;
        string[] airdropTokens;
    }

    struct AirdropInfo {
        address airdropTokenContract;
        address airdropContract;
        address airdropSwapContract;
        uint256 maxSlippage;
    }

    Config public config;

    mapping(string => AirdropInfo) public airdropInfo;

    event ConfigUpdated();
    event AirdropInfoAdded();
    event AirdropInfoUpdated();
    event AirdropRemoved();
    event ClaimFabricated();

    constructor(address _hubContract, address _rewardContract) {
        config.owner = msg.sender;
        config.hubContract = _hubContract;
        config.rewardContract = _rewardContract;
    }

    function updateConfig(address _owner, address _hubContract, address _rewardContract) external {
        require(msg.sender == config.owner, "");

        config.owner = _owner;
        config.hubContract = _hubContract;
        config.rewardContract = _rewardContract;

        emit ConfigUpdated();
    }

    function addAirdropInfo(string memory _airdropToken, address _airdropTokenContract, address _airdropContract,
    address _airdropSwapContract, uint256 _maxSlippage) external {
        require(msg.sender == config.owner, "");
        require(airdropInfo[_airdropToken].airdropTokenContract == address(0), "");

        config.airdropTokens.push(_airdropToken);
        airdropInfo[_airdropToken].airdropTokenContract = _airdropTokenContract;
        airdropInfo[_airdropToken].airdropContract = _airdropContract;
        airdropInfo[_airdropToken].airdropSwapContract = _airdropSwapContract;
        airdropInfo[_airdropToken].maxSlippage = _maxSlippage;

        emit AirdropInfoAdded();
    }

    function updateAirdropInfo(string memory _airdropToken, address _airdropTokenContract, address _airdropContract,
    address _airdropSwapContract, uint256 _maxSlippage) external {
        require(msg.sender == config.owner, "");
        require(airdropInfo[_airdropToken].airdropTokenContract != address(0), "");

        airdropInfo[_airdropToken].airdropTokenContract = _airdropTokenContract;
        airdropInfo[_airdropToken].airdropContract = _airdropContract;
        airdropInfo[_airdropToken].airdropSwapContract = _airdropSwapContract;
        airdropInfo[_airdropToken].maxSlippage = _maxSlippage;

        emit AirdropInfoUpdated();
    }

    // use index of airdrop token
    function removeAirdropInfo(uint256 _index) external {
        require(msg.sender == config.owner, "");
        string memory _token = config.airdropTokens[_index];
        require(airdropInfo[_token].airdropTokenContract != address(0), "");
        require(_index < config.airdropTokens.length, "");

        delete airdropInfo[_token];
        config.airdropTokens[_index] = config.airdropTokens[config.airdropTokens.length - 1];
        config.airdropTokens.pop();

        emit AirdropRemoved();
    }

    function fabricateClaim(string memory airdropToken, uint8 stage, uint256 amount, bytes32[] calldata proof) external {
        require(airdropInfo[airdropToken].airdropTokenContract != address(0), "");

        IHub(config.hubContract).claimAirdrop(airdropInfo[airdropToken].airdropTokenContract,
        airdropInfo[airdropToken].airdropContract,
        airdropInfo[airdropToken].airdropSwapContract,
        stage,
        amount,
        proof,
        airdropInfo[airdropToken].maxSlippage,
        config.rewardContract);

        emit ClaimFabricated();
    }
}