// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILuckyGame {
    function userTotalBet(uint256 nob, address user) external view returns(uint256);

}