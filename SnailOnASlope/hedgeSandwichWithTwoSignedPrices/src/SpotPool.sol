// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { MockERC20 } from "./MockERC20.sol";

// Dummmy constant-product AMM (x*y=k) mirroring an external DEX
contract SpotPool {
    MockERC20 public immutable base; // wETH
    MockERC20 public immutable quote; // USDC

    uint256 public reserveBase;
    uint256 public reserveQuote;

    uint256 public constant FEE_BPS = 30; // 0.3%
    uint256 public constant BPS = 10_000;

    constructor(MockERC20 _base, MockERC20 _quote) {
        base = _base;
        quote = _quote;
    }

    // Seeding function for simplicity
    function seed(uint256 baseAmount, uint256 quoteAmount) external {
        base.transferFrom(msg.sender, address(this), baseAmount);
        quote.transferFrom(msg.sender, address(this), quoteAmount);
        reserveBase += baseAmount;
        reserveQuote += quoteAmount;
    }

    // Current spot price
    function spotPrice() public view returns (uint256) {
        return (reserveQuote * 1e18) / reserveBase;
    }

    // Sell exact amountIn of wETH into the pool and receive USDC
    function swapExactBaseForQuote(uint256 amountIn) external returns (uint256 amountOut) {
        base.transferFrom(msg.sender, address(this), amountIn);
        uint256 amountInWithFee = (amountIn * (BPS - FEE_BPS)) / BPS;
        amountOut = (reserveQuote * amountInWithFee) / (reserveBase + amountInWithFee);
        reserveBase += amountIn;
        reserveQuote -= amountOut;
        quote.transfer(msg.sender, amountOut);
    }

    // Sell exact amountIn of USDC into the pool and receive wETH.
    function swapExactQuoteForBase(uint256 amountIn) external returns (uint256 amountOut) {
        quote.transferFrom(msg.sender, address(this), amountIn);
        uint256 amountInWithFee = (amountIn * (BPS - FEE_BPS)) / BPS;
        amountOut = (reserveBase * amountInWithFee) / (reserveQuote + amountInWithFee);
        reserveQuote += amountIn;
        reserveBase -= amountOut;
        base.transfer(msg.sender, amountOut);
    }
}
