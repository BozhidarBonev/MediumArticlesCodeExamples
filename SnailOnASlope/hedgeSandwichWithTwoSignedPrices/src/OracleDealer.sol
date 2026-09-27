// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { MockERC20 } from "./MockERC20.sol";
import { MarginLedger } from "./MarginLedger.sol";
import { PriceOracle } from "./PriceOracle.sol";
import { IDealer } from "./IDealer.sol";

contract OracleDealer is IDealer {
    MockERC20 public immutable quote;
    MarginLedger public immutable ledger;
    PriceOracle public immutable oracle;
    address public immutable engine;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    uint256 internal constant WAD = 1e18;

    event Deposited(address lp, uint256 amount, uint256 shares);
    event Withdrawn(address lp, uint256 shares, uint256 amount);

    modifier onlyEngine() {
        require(msg.sender == engine, "Not engine");
        _;
    }

    constructor(MockERC20 _quote, MarginLedger _ledger, PriceOracle _oracle, address _engine) {
        quote = _quote;
        ledger = _ledger;
        oracle = _oracle;
        engine = _engine;
        quote.approve(address(_ledger), type(uint256).max);
    }

    function deposit(uint256 amount) external returns (uint256 shares) {
        uint256 vaultValueBefore = totalShares == 0 ? 0 : _vaultValue();

        quote.transferFrom(msg.sender, address(this), amount);
        ledger.deposit(address(this), amount);

        if (totalShares == 0) {
            shares = amount;
        } else {
            shares = (amount * totalShares) / vaultValueBefore;
        }
        totalShares += shares;
        sharesOf[msg.sender] += shares;

        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external returns (uint256 amount) {
        require(sharesOf[msg.sender] >= shares, "Insufficient shares");

        uint256 vaultValue = _vaultValue();
        amount = (shares * vaultValue) / totalShares;

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;

        ledger.withdraw(amount);
        quote.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, shares, amount);
    }

    function fillOrder(bool isBaseToQuote, uint256 amount) external view onlyEngine returns (uint256 oppositeAmount) {
        uint256 price = oracle.getPrice();
        if (isBaseToQuote) {
            oppositeAmount = (amount * price) / WAD;
        } else {
            oppositeAmount = (amount * WAD) / price;
        }
    }

    function _vaultValue() internal view returns (uint256) {
        int256 value = ledger.getAccountValue(address(this), oracle.getPrice());
        require(value > 0, "Negative vault value");
        return uint256(value);
    }
}
