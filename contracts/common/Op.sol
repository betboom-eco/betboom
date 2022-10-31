// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../types/Ownable.sol";

contract Op is Ownable {
    address public operator;
    uint256 constant baseRate = 10000;
    
    modifier onlyOperator {
        require(msg.sender == owner() || msg.sender == operator, "no permission");
        _;
    }

    function setOperator(address operator_) external onlyOwner {
        operator = operator_;
    }


    function getCurrTime() external view returns(uint256) {
        return block.timestamp;
    }
    
    function getBlockNum() external view returns(uint256) {
        return block.number;
    }

}