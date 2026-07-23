// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract StakeV2Test {
    event Staked(uint amount, uint resourceType);
    event Unstaked(uint amount, uint resourceType);
    event Withdrawn(uint amount);
    event Delegated(uint amount, uint resourceType, address to);
    event Undelegated(uint amount, uint resourceType, address to);

    constructor() payable {}
    receive() external payable {}

    function stake(uint amount, uint resourceType) external {
        freezebalancev2(amount, resourceType);
        emit Staked(amount, resourceType);
    }

    function unstake(uint amount, uint resourceType) external {
        unfreezebalancev2(amount, resourceType);
        emit Unstaked(amount, resourceType);
    }

    function withdraw() external returns (uint amount) {
        amount = withdrawexpireunfreeze();
        emit Withdrawn(amount);
    }

    function delegate(address payable to, uint amount, uint resourceType) external {
        to.delegateResource(amount, resourceType);
        emit Delegated(amount, resourceType, to);
    }

    function undelegate(address payable to, uint amount, uint resourceType) external {
        to.unDelegateResource(amount, resourceType);
        emit Undelegated(amount, resourceType, to);
    }

    function myTotalResource(uint resourceType) external view returns (uint) {
        return address(this).totalResource(resourceType);
    }

    function myUnfreezableBalance(uint resourceType) external view returns (uint) {
        return address(this).unfreezableBalanceV2(resourceType);
    }

    function chainInfo() external view returns (uint, uint, uint, uint, uint) {
        return (
            chain.totalNetLimit,
            chain.totalNetWeight,
            chain.totalEnergyCurrentLimit,
            chain.totalEnergyWeight,
            chain.unfreezeDelayDays
        );
    }
}