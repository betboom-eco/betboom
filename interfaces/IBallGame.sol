// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBallGame {
    function bet(
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) external returns(uint256, uint256);

    function getTake(
        uint256 cupID, 
        uint256 mID, 
        uint256 cType
    ) external view returns(uint256 max, uint256 cTake);
    
    function gameType() external view returns(uint256);
    function caculateMatch(
        uint256 cupID,
        uint256 mID
    ) external;

    function checkClaim(
        uint256 cupID, 
        uint256 mID, 
        uint256 totalID
    ) external view returns(uint256);
}