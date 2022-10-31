// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "../libraries/EnumerableSet.sol";

contract MinterOwned is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet minter;


    event AddOrRemoveMinter(address account, bool isAdd);
    function addOrRemoveMinter(address account, bool isAdd) external  onlyOwner() {
        if(isAdd) {
            require(!minter.contains(account), "has add");
            minter.add(account);
        } else {
            require(minter.contains(account), "has remove");
            minter.remove(account);
        }
        emit AddOrRemoveMinter(account, isAdd);
    }

    modifier onlyMinter() {
        require(minter.contains(msg.sender), "not minter");
        _;
    }

    function getMinterNum() public view returns(uint256) {
        return minter.length();
    }

    function getMinterAddress(uint256 index) public view returns(address) {
        return minter.at(index);
    }

    function getMinterContains(address account) public view returns(bool) {
        return minter.contains(account);
    }  

}
