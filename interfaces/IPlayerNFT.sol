
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IPlayerNFT {
    function addAmount(uint256 tokenID, uint256 bAmount) external;
    function getNotClaim(uint256 tokenID) external view returns(uint256);
    function claimTokenIDRward(uint256 tokenID, uint256 amount) external;
}
