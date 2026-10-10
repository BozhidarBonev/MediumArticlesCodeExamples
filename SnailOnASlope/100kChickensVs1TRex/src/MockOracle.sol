// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Dumb price feed with 8 decimals
contract MockOracle {
    mapping(address => uint256) public price;

    function setPrice(address asset, uint256 newPrice) external {
        price[asset] = newPrice;
    }
}
