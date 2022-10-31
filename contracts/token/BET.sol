// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../types/ERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../types/MinterOwned.sol";

contract BET is ERC20, MinterOwned {    
    using SafeMath for uint256;
    uint256 public burnID;
    uint256 public totalBurnAmount;
    mapping(address => uint256) public userBurnAmount;
    mapping(uint256 => address) public idToUser;
    
    
    constructor(
        string memory name_, 
        string memory symbol_
    ) ERC20(name_, symbol_) {

    }

    function mint(address account_, uint256 amount_) external override onlyMinter() {
        _mint(account_, amount_);
    }

    function burn(uint256 amount) external override  {
        if(userBurnAmount[msg.sender] == 0) {
            ++burnID;
            idToUser[burnID] = msg.sender;
        }
        totalBurnAmount = totalBurnAmount.add(amount);
        userBurnAmount[msg.sender] = userBurnAmount[msg.sender].add(amount);
        _burn(msg.sender, amount);
    }

}