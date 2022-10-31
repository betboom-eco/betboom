// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGame {
    function getTokenAmount(uint256 amount, uint8 round) external view returns(uint256, uint256);
}