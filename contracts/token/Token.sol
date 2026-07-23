// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {IReward} from "./IReward.sol";

contract Token is ERC20Burnable {
    address public owner;
    address public minter;
    address public rewardContract;

    constructor() ERC20('dTRX', 'dTRX') {
        owner = msg.sender;
    }

    function mint(address recipient, uint256 amount) external {
        require(msg.sender == minter, "unauthorized access");
        _mint(recipient, amount);
    }

    // use hub contract address
    function setMinter(address newMinter) external {
        require(msg.sender == owner, "unauthorized access");
        minter = newMinter;
    }

    // use reward contract address
    function setRewardContract(address newRewardContract) external {
        require(msg.sender == owner, "unauthorized access");
        rewardContract = newRewardContract;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (from != address(0)) {
            IReward(rewardContract).decreaseBalance(from, value);
        }
        if (to != address(0)) {
            IReward(rewardContract).increaseBalance(to, value);
        }
    }
}