// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract Parama {

    struct PoolInfo {
        uint256 totalAmount;
        uint256 totalAddAmount;
        uint256 earnAmount;
        uint256 loseAmount;
    }

    struct BombInfo {
        uint256 totalAmount;
        uint256 nextInit;
        uint256 betLp;
        uint256 letLp;
        uint256 letUserAmount;
        uint256 proAmount;
        uint256 luckyAmount;
    }
    
    PoolInfo public poolInfo;
    uint256 constant public initAmount  = 1000e6;
    uint256 public initRate = 2500;
    uint256 public betLpRate = 2000;
    uint256 public letLpRate = 2000;
    uint256 public letUserRate = 2000;
    uint256 public pragmaRate = 1000;
    uint256 public luckyRate = 500;
    uint256 public nob = 1;
    uint256 public explosionAmount = 2000e6;
    uint256 public upAmount = 50000e6;
    uint256 public addAmount = 1000e6;
    uint256 public limitAmount = 5000e6;
    uint256 public perAmount = 5000e6;
    bool public isInit;
        
    mapping(uint256 => BombInfo) public bombInfo;

    modifier onlyInit {
        require(isInit, "not init");
        _;
    }

    function getBlockHash(uint256 blockNum) public view returns(bytes32) {
        return blockhash(blockNum);
    }
}