// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBonus {
    function addBonusForm(
        address gamePool,
        uint256 amount
    ) external;
}