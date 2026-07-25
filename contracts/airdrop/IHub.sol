// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IHub {
    // it is a mock interface please check it out https://github.com/sunlend/sunlend-token-contracts
    // and hub contract's claimAirdrop & swapHook functions
    function claimAirdrop(address airdropTokenContract, address airdropContract,
    address airdropSwapContract, uint8 stage, uint256 amount, bytes32[] calldata proof,
    uint256 maxSlippage, address to) external;
}