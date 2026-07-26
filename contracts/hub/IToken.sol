// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IToken {
    function mint(address recipient, uint256 amount) external;
}