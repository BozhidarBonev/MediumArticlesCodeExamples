// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { MockERC20 } from "./MockERC20.sol";
import { SpotPool } from "./SpotPool.sol";
import { MarginLedger } from "./MarginLedger.sol";
import { IDealer } from "./IDealer.sol";

contract HedgingDealer is IDealer {
    MockERC20 public immutable base;
    MockERC20 public immutable quote;
    SpotPool public immutable pool;
    MarginLedger public immutable ledger;
    address public immutable engine;

    constructor(MockERC20 _base, MockERC20 _quote, SpotPool _pool, MarginLedger _ledger, address _engine) {
        base = _base;
        quote = _quote;
        pool = _pool;
        ledger = _ledger;
        engine = _engine;
        base.approve(address(_pool), type(uint256).max);
        quote.approve(address(_pool), type(uint256).max);
        quote.approve(address(_ledger), type(uint256).max);
    }

    modifier onlyEngine() {
        require(msg.sender == engine, "Not engine");
        _;
    }

    // LPs fund the dealer to hedge shorts
    function lpDeposit(uint256 amount) external {
        base.transferFrom(msg.sender, address(this), amount);
    }

    function fillOrder(bool isBaseToQuote, uint256 amount) external onlyEngine returns (uint256 oppositeAmount) {
        if (isBaseToQuote) {
            // Taker sells base so dealer inherits a synthetic long position and hedges by selling amount into the spot pool
            oppositeAmount = pool.swapExactBaseForQuote(amount);
            ledger.deposit(address(this), oppositeAmount);
        } else {
            // Taker buys base so dealer inherits a synthetic short position and hedges by buying from the spot pool
            ledger.withdraw(amount);
            oppositeAmount = pool.swapExactQuoteForBase(amount);
        }
    }
}
