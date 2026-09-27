// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Dummy for the external pull price feed adapter
contract PriceOracle {
    uint256 public price;
    uint256 public publishTime;

    constructor(uint256 _price, uint256 _publishTime) {
        price = _price;
        publishTime = _publishTime;
    }

    // Push a mock signed price update
    // Reverts if it's older than the update
    // Signature checking skipped
    function setPrice(uint256 _price, uint256 _publishTime) external {
        require(_publishTime >= publishTime, "Stale update");
        price = _price;
        publishTime = _publishTime;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }
}
