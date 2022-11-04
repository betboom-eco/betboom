// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFactory {
    function feeRate() external view returns(uint256);
    function checkMid(address gameAddr, uint256 cupID, uint256 mID) external view returns(bool);
    function checkGame(address gameAddr, uint256 cupID, uint256 mID) external view returns(uint256);
    function upDateTotalID(address user, uint256 cupID, uint256 amount) external returns(uint256);
    function getInGame(address gameAddr) external view returns(bool);
    function rewardPool() external view returns(address);
    function rewardToken() external view returns(address);
    function getMatchTime(uint256 cupID) external view returns(uint256);
    function getWinType(uint256 cupID, uint256 mID) external view returns(uint8);
    function getChoiceRate(uint256 cupID, uint256 totalID) external view returns(int256, uint256, uint256);
    function getResult(uint256 cupID, uint256 mID) external view returns(uint256, uint256);
    function getIndex(uint256 cupID, uint256 totalID) external view returns(uint256);
    function getGType(uint256 cupID, uint256 totalID) external view returns(uint256, address);
    function getCancle(uint256 cupID, uint256 mID) external view returns(bool);
    function betToken() external view returns(address);
    function betFor(
        address user, 
        uint256 bAmount,
        uint256 lAmount,
        uint256 value,
        uint8 num
    ) external;
    function getEndInfo() external view returns(uint256, uint256);
}