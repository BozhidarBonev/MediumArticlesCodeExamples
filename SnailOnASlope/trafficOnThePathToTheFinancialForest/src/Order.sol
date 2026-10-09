// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

library Order {
    enum OrderType {
        MarketIncrease,
        MarketDecrease
    }

    struct Props {
        address account;
        address callbackContract;
        bool isLong;
        OrderType orderType;
        uint256 collateralAmount;
        uint256 sizeDeltaUsd;
        uint256 acceptablePrice;
        uint256 callbackGasLimit;
        uint256 swapHops;
        uint256 executionFee;
        uint256 createdAtBlock;
    }
}
