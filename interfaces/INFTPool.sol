// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INFTPool {
    function updatePool(uint256 tokenID) external;
    function userToTokenID(address user) external view returns(uint256);
    function tokenIdToUser(uint256 tokenID) external view returns(address);
    function increaseMint(
        address user, 
        uint256 bAmount, 
        uint256 lAmount
    ) external;
    function gainExperience(
        address user, 
        uint256 amount,
        uint8 round
    ) external;
    function castNFT() external returns(uint256);
    function claimNFT(address user, uint256 tokenID) external;
    function userInfo(address user) external view returns(uint256, uint256);
    function mintLET(uint256 amount) external;
    function updateUser(uint256 tokenID) external;
}