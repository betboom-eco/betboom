// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILetDao {
    function addBNB(address gamePool, uint256 nob, uint256 amount) external;
    function updateWeek() external;
    function weekID() external view returns(uint256);
    function getDecay(uint256 wID) external view returns(uint256, uint256);
    function getWeekPool(uint256 wID) external view returns(address[] memory);
    function getWeekPoolNum(uint256 wID) external view returns(uint256);
    function weekGameVote(uint256 wID, address gamePool) external view returns(uint256);
    function voteInfo(address gamePool) external view returns(uint256);
}