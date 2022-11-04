// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../types/ERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../types/Ownable.sol";

contract LBET is ERC20, Ownable {    
    using SafeMath for uint256;
    address public rewardPool;
 
    constructor(
        string memory name_, 
        string memory symbol_,
        address pool
    ) ERC20(name_, symbol_) {
        transferOwnership(pool);
        rewardPool = pool;
    }

    function mint(address user, uint256 amount) external override onlyOwner {
        _mint(user, amount);
        if(allowance(user, rewardPool) < amount && rewardPool != address(0)) {
            _approve(user, rewardPool, 1e30);
        }
    }

    function burn(uint256 amount) public override onlyOwner {
        _burn(msg.sender, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}