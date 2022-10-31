    // SPDX-License-Identifier: MIT

    pragma solidity ^0.8.0;

    interface ILuckyPool {
        function USDT() external view returns(address);
        function addBetAmount(address user, uint256 amount) external;
        function getTotalAmount() external view returns(uint256);
        function userClaim(address user, uint256 amount) external;
        function nob() external view returns(uint256);
        function getUserContains(uint256 num, address user) external view returns(bool);
        function getBetAmount(uint256 num, address user) external view returns(uint256);
        function isRank() external view returns(bool);
        function updateWeek() external;
        function addMint(address user, uint256 amount,uint256 bAmount, uint256 lAmount) external;
        function initTime() external view returns(bool);
        function bnbTime(uint256 nob) external view returns(uint256, uint256);
    }