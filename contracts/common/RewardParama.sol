// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Op.sol";

contract RewardParama is Op {
    struct BombInfo {
        uint256 totalAmount;
        uint256 userReward;
        uint256 betLp;
        uint256 letLp;
        uint256 letUserAmount;
        uint256 proAmount;
        uint256 luckyAmount;
    }
    
    uint256 public initRate = 2500;
    uint256 public betLpRate = 2000;
    uint256 public letLpRate = 2000;
    uint256 public letUserRate = 2000;
    uint256 public pragmaRate = 1000;
    uint256 public luckyRate = 500;
    uint256 public explosionAmount = 1000e6;
    uint256 public addAmount = 1000e6;
    uint256 public upAmount = 50000e6;
        
    mapping(uint256 => BombInfo) public bombInfo;

    function getBlockHash(uint256 blockNum) public view returns(bytes32) {
        return blockhash(blockNum);
    }

    function setAddAmount(uint256 amount) external onlyOperator  {
        require(amount > 0, "amount err");
        addAmount = amount;
    }

}