// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IToken {
    function mint(address recipient, uint256 amount) external;
}