// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {MockERC20} from "./MockERC20.sol";
import {MarketPool} from "./MarketPool.sol";
import {LedgerStorage} from "./LedgerStorage.sol";

contract HomeRouter {
    LedgerStorage public immutable ledger;
    MockERC20 public immutable tithe; // the TITHE reward token

    address public owner;
    address public bridgeRouter;

    event SupplySuccess(address supplier, address market, uint256 amount);
    event BorrowSuccess(address borrower, address market, uint256 amount);
    event RepaySuccess(address borrower, address market, uint256 amount);

    modifier onlyBridgeRouter() {
        require(msg.sender == bridgeRouter, "Not bridge router");
        _;
    }

    constructor(LedgerStorage _ledger, MockERC20 _tithe) {
        ledger = _ledger;
        tithe = _tithe;
        owner = msg.sender;
    }

    function setBridgeRouter(address _bridgeRouter) external {
        require(msg.sender == owner, "Not owner");
        bridgeRouter = _bridgeRouter;
    }

    // External funcs for users

    function supply(uint256 amount, address token) external {
        address market = ledger.marketOf(token);
        require(market != address(0), "Token not supported");
        require(amount > 0, "0 amount");

        MockERC20(token).transferFrom(msg.sender, market, amount);
        ledger.updateTotalInvestment(msg.sender, market, amount);

        emit SupplySuccess(msg.sender, market, amount);
    }

    function borrow(uint256 amount, address token) external {
        require(amount != 0, "0 amount");
        address market = ledger.marketOf(token);
        require(market != address(0), "Token not supported");

        (uint256 borrowed, uint256 collateral) = ledger.accountPosition(
            msg.sender,
            market,
            amount
        );
        require(collateral >= borrowed, "Not enough collateral");

        // rewards are settled against the OLD debt, before it changes
        ledger.settleBorrowerTithe(market, msg.sender);

        uint256 index = MarketPool(market).borrowIndex();
        uint256 current = ledger.sameChainDebt(msg.sender, market);

        MarketPool(market).release(amount);
        MockERC20(token).transfer(msg.sender, amount);

        ledger.updateBorrowBalance(msg.sender, market, current + amount, index);

        emit BorrowSuccess(msg.sender, market, amount);
    }

    function repayBorrow(uint256 amount, address market) external {
        _settleRepayment(msg.sender, msg.sender, amount, market, true);
    }

    function payOutRemoteBorrow(
        address borrower,
        uint256 amount,
        address market
    ) external onlyBridgeRouter {
        MarketPool(market).release(amount);
        MockERC20(ledger.underlyingOf(market)).transfer(borrower, amount);
    }

    function takeRemoteRepayment(
        address borrower,
        address payer,
        uint256 amount,
        address market
    ) external onlyBridgeRouter {
        _settleRepayment(borrower, payer, amount, market, false);
    }

    // Reward funcs

    function claimTithe(address[] calldata holders, address market) external {
        for (uint256 i = 0; i < holders.length; i++) {
            ledger.settleBorrowerTithe(market, holders[i]);

            uint256 accrued = ledger.titheAccrued(holders[i]);
            // pay only if the router actually holds enough TITHE, otherwise leave it accrued
            if (accrued > 0 && accrued <= tithe.balanceOf(address(this))) {
                tithe.transfer(holders[i], accrued);
                ledger.setTitheAccrued(holders[i], 0);
            }
        }
    }

    // Internal funcs

    function _settleRepayment(
        address borrower,
        address payer,
        uint256 amount,
        address market,
        bool isSameChain
    ) internal {
        address token = ledger.underlyingOf(market);

        uint256 borrowedAmount = _debtToRepay(borrower, market, isSameChain);
        require(borrowedAmount > 0, "Borrowed amount is 0");

        uint256 repayFinal = amount == type(uint256).max
            ? borrowedAmount
            : amount;
        require(repayFinal <= borrowedAmount, "Repay exceeds borrow");

        ledger.settleBorrowerTithe(market, borrower);

        MockERC20(token).transferFrom(payer, market, repayFinal);
        MarketPool(market).onRepay(repayFinal);

        if (isSameChain) {
            if (repayFinal == borrowedAmount) {
                ledger.removeBorrowBalance(borrower, market);
            } else {
                ledger.updateBorrowBalance(
                    borrower,
                    market,
                    borrowedAmount - repayFinal,
                    MarketPool(market).borrowIndex()
                );
            }
        }

        emit RepaySuccess(borrower, market, repayFinal);
    }

    function _debtToRepay(
        address borrower,
        address market,
        bool isSameChain
    ) internal view virtual returns (uint256) {
        return
            isSameChain
                ? ledger.sameChainDebt(borrower, market)
                : ledger.crossChainDebt(borrower, market);
    }
}
