// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILetDaoSwap {
    function depositSigleToken(
        address lpToken_,
        address[] calldata path_,
        uint256 amount_,
        uint256 amount0Min_,
        uint256 amount1Min_,
        uint256 deadline_
    ) external;
}
