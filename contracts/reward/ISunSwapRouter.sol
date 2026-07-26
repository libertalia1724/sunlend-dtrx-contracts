// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ISunSwapRouter {
    function swapExactInput(address[] calldata path,
        string[] calldata poolVersion,
        uint256[] calldata versionLen,
        uint24[] calldata fees,
        SwapData calldata data) external;

    struct SwapData{
        uint256 amountIn;
        uint256 amountOutMin;
        address to;
        uint256 deadline;
    }
}