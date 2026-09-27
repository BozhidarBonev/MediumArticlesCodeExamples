// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IDealer {
    function fillOrder(bool isBaseToQuote, uint256 amount) external returns (uint256 oppositeAmount);
}
