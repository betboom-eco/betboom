// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../types/ERC20.sol";
import "../../types/MinterOwned.sol";
import "../../libraries/SafeMath.sol";


contract LET is ERC20, MinterOwned {
    event SetCap(uint256 oldCap, uint256 newCap);
    
    using SafeMath for uint256;
    
    uint256 public cap;
    
    constructor(
        string memory name_, 
        string memory symbol_,
        uint256 cap_
    )ERC20(name_, symbol_) {
        cap = cap_;
    }
    
    function mint(address account_, uint256 amount_) external override onlyMinter() {
        require(totalSupply().add(amount_) <= cap, "out cap");
        _mint(account_, amount_);
    }


    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }


    function setCap(uint256 cap_) external onlyOwner() {
        require(cap_ >= totalSupply(), "new cap err");
        uint256 oldCap = cap;
        cap = cap_;
        emit SetCap(oldCap, cap);
    }
    
}