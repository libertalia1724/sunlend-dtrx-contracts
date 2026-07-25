// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IThirdPartyAirdrop {
    // it is a mock interface please check it out https://github.com/sunlend/sunlend-token-contracts
    function claim(uint8 stage, uint256 amount, bytes32[] calldata proof) external;
}