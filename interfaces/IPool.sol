
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPool {
    function nob() external view returns(uint256);
    function getUserContains(uint256 num, address user) external view returns(bool);
    function getUserLength(uint256 num) external view returns(uint256);
    function getBetAmount(uint256 num, address user) external view returns(uint256);
    function playGame() external view returns(address);
    function setRank() external;
    function totalWeekAmount(uint256 wID) external view returns(uint256);
    function getWeekUserNum(uint256 wID) external view returns(uint256);
    function getWeekUserIn(uint256 wID, address user) external view returns(bool);
    function totalWeekUserAmount(uint256 wID, address user) external view returns(uint256);
}
