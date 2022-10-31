// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IExp {
    function gainExperience(
        uint256 amount,
        uint256 tokenID,
        uint8 round
    ) external;

    function levelInfo(uint256 lid) external view returns(uint256, uint256, uint256, uint256);
    function mintInfo(uint256 lid) external view returns(uint256, uint256);
    function tokenIDExp(uint256 lid) external view returns(uint256, uint256, uint256);
    function getCap(uint256 lid) external view returns(uint256);
}