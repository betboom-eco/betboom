// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Parama.sol";
import "./Op.sol";

contract Auth is Parama, Op {
    modifier notZero(uint256 amount) {
        require(amount > 0, "amount err");
        _;
    }

    function setUpAmount(uint256 amount) external onlyOperator notZero(amount) {
        require(amount >= poolInfo.totalAmount, "new up amount err");
        upAmount = amount;
    }

    function setAddAmount(uint256 amount) external onlyOperator notZero(amount) {
        addAmount = amount;
    }

    function setLimitAmount(uint256 amount) external onlyOperator notZero(amount) {
        limitAmount = amount;
    }

    function setPerAmount(uint256 amount) external onlyOperator notZero(amount)  {
        perAmount = amount;
    }
}