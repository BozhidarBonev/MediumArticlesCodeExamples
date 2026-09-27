// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";
import {PriceOracle} from "./PriceOracle.sol";

contract MarginLedger {
    MockERC20 public immutable collateral;
    PriceOracle public immutable oracle;
    address public engine;

    mapping(address => int256) public margin; // settled cash
    mapping(address => int256) public positionSize; // base amount
    mapping(address => int256) public openNotional; // trade accounting

    modifier onlyEngine() {
        require(msg.sender == engine, "Not engine");
        _;
    }

    constructor(MockERC20 _collateral, PriceOracle _oracle) {
        collateral = _collateral;
        oracle = _oracle;
    }

    // In reality this would be access-controlled
    function setEngine(address _engine) external {
        require(engine == address(0), "Already exists");
        engine = _engine;
    }

    function deposit(address trader, uint256 amount) external {
        collateral.transferFrom(msg.sender, address(this), amount);
        margin[trader] += int256(amount);
    }

    // Fill to both sides of the trade
    function settleTrade(
        address taker,
        address maker,
        int256 takerBaseDelta,
        int256 takerQuoteDelta
    ) external onlyEngine {
        positionSize[taker] += takerBaseDelta;
        openNotional[taker] += takerQuoteDelta;

        positionSize[maker] -= takerBaseDelta;
        openNotional[maker] -= takerQuoteDelta;
    }

    function creditMargin(address trader, int256 amount) external onlyEngine {
        margin[trader] += amount;
    }

    // Withdraw cash margin
    function withdraw(uint256 amount) external {
        uint256 price = oracle.getPrice();
        int256 newMargin = margin[msg.sender] - int256(amount);
        int256 unrealizedPnl = (positionSize[msg.sender] * int256(price)) /
            1e18 +
            openNotional[msg.sender];
        require(newMargin + unrealizedPnl >= 0, "Insufficient free collateral");
        margin[msg.sender] = newMargin;
        collateral.transfer(msg.sender, amount);
    }

    // Cash margin + unrealized PnL
    function getAccountValue(
        address trader,
        uint256 price
    ) public view returns (int256) {
        int256 unrealizedPnl = (positionSize[trader] * int256(price)) /
            1e18 +
            openNotional[trader];
        return margin[trader] + unrealizedPnl;
    }
}
