// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../types/Ownable.sol";
import "../../libraries/EnumerableSet.sol";

contract Operator is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet contractAuth;
    address public operator;
    uint256 constant baseRate = 10000;
    
    modifier onlyOperator {
        require(msg.sender == owner() || msg.sender == operator, "no permission");
        _;
    }

    function setOperator(address operator_) external onlyOwner {
        operator = operator_;
    }

    function addContractAuth(address account) external onlyOperator {
        require(!contractAuth.contains(account), "has set");
        contractAuth.add(account);
    }

    function removeContractAuth(address account) external onlyOperator {
        require(contractAuth.contains(account), "has remove");
        contractAuth.remove(account);
    } 

    modifier onlyContractAuth() {
        require(contractAuth.contains(msg.sender), "not auth");
        _;
    }

    function getCAuthLength() public view returns(uint256) {
        return contractAuth.length();
    }

    function getCAuthAddress(uint256 index) public view returns(address) {
        return contractAuth.at(index);
    }

    function getCAuthContanins(address account) public view returns(bool) {
        return contractAuth.contains(account);
    }

    function getCurrTime() external view returns(uint256) {
        return block.timestamp;
    }
    
    function getBlockNum() external view returns(uint256) {
        return block.number;
    }
}