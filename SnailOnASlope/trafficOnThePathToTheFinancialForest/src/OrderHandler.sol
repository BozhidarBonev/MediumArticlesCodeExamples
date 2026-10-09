// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Order.sol";
import "./OrderVault.sol";
import "./MockERC20.sol";
import "./IOrderCallbackReceiver.sol";

contract OrderHandler {
    using Order for Order.Props;

    MockERC20 public immutable token;
    OrderVault public immutable vault;

    mapping(bytes32 => Order.Props) public orders;
    mapping(address => Position) public positions;

    uint256 private swapSink;
    uint256 public nonce;
    address public keeper;

    struct Position {
        bool open;
        bool isLong;
        uint256 collateralAmount;
        uint256 sizeInTokens;
        uint256 entryPrice;
    }

    event OrderCreated(bytes32 key, address account);
    event OrderExecuted(bytes32 key, address account, uint256 execPrice);
    event OrderCancelled(bytes32 key, address account);
    event PositionClosed(
        address account,
        uint256 exitPrice,
        int256 pnl,
        uint256 payout
    );

    error EmptyOrder();
    error NotSelf();
    error OrderNotFound();
    error PriceOutsideAcceptableRange();

    modifier onlyKeeper() {
        require(msg.sender == keeper, "Not keeper");
        _;
    }

    constructor(MockERC20 _token, OrderVault _vault, address _keeper) {
        token = _token;
        vault = _vault;
        keeper = _keeper;
    }

    function createIncreaseOrder(
        uint256 collateralAmount,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        bool isLong,
        address callbackContract,
        uint256 callbackGasLimit,
        uint256 swapHops,
        uint256 executionFee
    ) external returns (bytes32 key) {
        if (collateralAmount == 0 || sizeDeltaUsd == 0) revert EmptyOrder();

        token.transferFrom(
            msg.sender,
            address(vault),
            collateralAmount + executionFee
        );

        Order.Props memory order = Order.Props({
            account: msg.sender,
            callbackContract: callbackContract,
            isLong: isLong,
            orderType: Order.OrderType.MarketIncrease,
            collateralAmount: collateralAmount,
            sizeDeltaUsd: sizeDeltaUsd,
            acceptablePrice: acceptablePrice,
            callbackGasLimit: callbackGasLimit,
            swapHops: swapHops,
            executionFee: executionFee,
            createdAtBlock: block.number
        });

        key = keccak256(abi.encode(address(this), msg.sender, nonce++));
        orders[key] = order;

        emit OrderCreated(key, msg.sender);
    }

    function executeOrder(bytes32 key, uint256 execPrice) external onlyKeeper {
        try this._executeOrder(key, execPrice) {
            emit OrderExecuted(key, orders[key].account, execPrice);
        } catch {
            _cancelOrder(key);
        }
    }

    function _executeOrder(bytes32 key, uint256 execPrice) external {
        if (msg.sender != address(this)) revert NotSelf();

        Order.Props memory order = orders[key];
        if (order.account == address(0)) revert OrderNotFound();
        if (execPrice > order.acceptablePrice)
            revert PriceOutsideAcceptableRange();

        // Swap simulation for simplicity
        _simulateSwapPath(order.swapHops);

        uint256 sizeInTokens = order.sizeDeltaUsd / execPrice;
        positions[order.account] = Position({
            open: true,
            isLong: order.isLong,
            collateralAmount: order.collateralAmount,
            sizeInTokens: sizeInTokens,
            entryPrice: execPrice
        });

        delete orders[key];

        // Attacker callback
        if (order.callbackContract != address(0)) {
            try
                IOrderCallbackReceiver(order.callbackContract)
                    .afterOrderExecution{gas: order.callbackGasLimit}(key)
            {} catch {}
        }

        // Keeper payment
        if (order.executionFee > 0) {
            vault.transferOut(keeper, order.executionFee);
        }
    }

    function _cancelOrder(bytes32 key) internal {
        Order.Props memory order = orders[key];
        if (order.account == address(0)) return;

        vault.transferOut(order.account, order.collateralAmount);
        delete orders[key];

        // Attacker callback
        if (order.callbackContract != address(0)) {
            try
                IOrderCallbackReceiver(order.callbackContract)
                    .afterOrderCancellation{gas: order.callbackGasLimit}(key)
            {} catch {}
        }

        // Keeper payment
        if (order.executionFee > 0) {
            vault.transferOut(keeper, order.executionFee);
        }

        emit OrderCancelled(key, order.account);
    }

    function _simulateSwapPath(uint256 hops) internal {
        uint256 acc = swapSink;
        for (uint256 i = 0; i < hops; i++) {
            acc = uint256(keccak256(abi.encode(acc, i, block.number)));
            swapSink = acc;
        }
    }

    function closePosition(
        address account,
        uint256 exitPrice
    ) external returns (uint256 payout) {
        Position memory pos = positions[account];
        require(pos.open, "No open position");

        int256 pnl;
        if (pos.isLong) {
            pnl =
                int256(pos.sizeInTokens) *
                (int256(exitPrice) - int256(pos.entryPrice));
        } else {
            pnl =
                int256(pos.sizeInTokens) *
                (int256(pos.entryPrice) - int256(exitPrice));
        }

        int256 payoutSigned = int256(pos.collateralAmount) + pnl;
        payout = payoutSigned > 0 ? uint256(payoutSigned) : 0;

        delete positions[account];
        vault.transferOut(account, payout);

        emit PositionClosed(account, exitPrice, pnl, payout);
    }

    function orderExists(bytes32 key) external view returns (bool) {
        return orders[key].account != address(0);
    }
}
