// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardPool {
    function getPoolAamount() external view returns(uint256, uint256);
    function updateAmount(uint256 amount, uint256 beforeTake, uint256 afterTake, uint256 fee) external;
    function updateValue(uint256 maxTake, uint256 take) external;
    function cliam(address user, uint256 amount) external;
    function rewardToken() external view returns(address);
    function nob() external view returns(uint256);
    function weekNum() external view returns(uint256);
    function getTokenAmount(
        uint256 amount, 
        uint256 rate, 
        uint256 divisor, 
        uint256 num
    ) external view returns(uint256 bAmount, uint256 lAmount);
}