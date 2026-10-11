// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {MarketPool} from "./MarketPool.sol";
import {LedgerStorage} from "./LedgerStorage.sol";
import {HomeRouter} from "./HomeRouter.sol";
import {IEndpoint} from "./MockEndpoint.sol";

contract BridgeRouter {
    LedgerStorage public immutable ledger;
    HomeRouter public immutable homeRouter;
    address public immutable endpoint;
    uint32 public immutable currentEid;

    enum MessageType {
        OpenRemoteBorrow,
        BorrowConfirmed,
        RepayNotice
    }

    struct Payload {
        uint256 amount;
        uint256 borrowIndex;
        uint256 collateral;
        address sender;
        address destMarket; // the market on the DESTINATION chain
        address srcToken; // the token on the SOURCE chain
        uint8 messageType;
    }

    event RemoteBorrowStarted(address borrower, uint32 destEid, uint256 amount);
    event BorrowSuccess(address borrower, address token, uint256 amount);
    event RepaySuccess(address borrower, address market, uint256 amount);

    constructor(
        LedgerStorage _ledger,
        HomeRouter _homeRouter,
        address _endpoint,
        uint32 _currentEid
    ) {
        ledger = _ledger;
        homeRouter = _homeRouter;
        endpoint = _endpoint;
        currentEid = _currentEid;
    }

    function startRemoteBorrow(
        uint256 amount,
        address token,
        uint32 destEid
    ) external {
        require(amount != 0, "0 amount");

        address market = ledger.marketOf(token);
        require(market != address(0), "Unsupported source token");
        address destMarket = ledger.destMarketOf(token, destEid);
        require(destMarket != address(0), "Unsupported destination token");

        (uint256 borrowed, uint256 collateral) = ledger.accountPosition(
            msg.sender,
            market,
            0
        );
        require(collateral > borrowed, "No free collateral");

        _send(
            destEid,
            Payload({
                amount: amount,
                borrowIndex: 0,
                collateral: collateral - borrowed,
                sender: msg.sender,
                destMarket: destMarket,
                srcToken: token,
                messageType: uint8(MessageType.OpenRemoteBorrow)
            })
        );
        emit RemoteBorrowStarted(msg.sender, destEid, amount);
    }

    function _onBorrowConfirmed(Payload memory p, uint32 destEid) private {
        address market = ledger.marketOf(p.srcToken);

        ledger.settleBorrowerTithe(market, p.sender);

        (bool found, uint256 i) = ledger.findOutboundLoan(
            p.sender,
            p.srcToken,
            currentEid,
            destEid,
            p.destMarket
        );

        if (found) {
            LedgerStorage.Loan memory b = ledger.getOutboundLoans(
                p.sender,
                p.srcToken
            )[i];
            b.principal =
                (b.principal * p.borrowIndex) /
                b.borrowIndex +
                p.amount;
            b.borrowIndex = p.borrowIndex;
            ledger.updateOutboundLoan(p.sender, p.srcToken, i, b);
        } else {
            ledger.addOutboundLoan(
                p.sender,
                p.srcToken,
                LedgerStorage.Loan({
                    srcEid: currentEid,
                    destEid: destEid,
                    principal: p.amount,
                    borrowIndex: p.borrowIndex,
                    borrowedMarket: p.destMarket,
                    srcToken: p.srcToken
                })
            );
        }
        emit BorrowSuccess(p.sender, p.srcToken, p.amount);
    }

    function _onRepayNotice(Payload memory p, uint32 destEid) private {
        address market = ledger.marketOf(p.srcToken);

        (bool found, uint256 i) = ledger.findOutboundLoan(
            p.sender,
            p.srcToken,
            currentEid,
            destEid,
            p.destMarket
        );
        require(found, "No borrow found");

        LedgerStorage.Loan memory b = ledger.getOutboundLoans(
            p.sender,
            p.srcToken
        )[i];
        uint256 current = (b.principal * p.borrowIndex) / b.borrowIndex;

        ledger.settleBorrowerTithe(market, p.sender);

        if (p.amount >= current) {
            ledger.removeOutboundLoan(p.sender, p.srcToken, i);
        } else {
            b.principal = current - p.amount;
            b.borrowIndex = p.borrowIndex;
            ledger.updateOutboundLoan(p.sender, p.srcToken, i, b);
        }
    }

    function _onOpenRemoteBorrow(Payload memory p, uint32 srcEid) private {
        address market = p.destMarket;
        address underlying = ledger.underlyingOf(market);
        require(underlying != address(0), "Unknown market");
        uint256 index = MarketPool(market).borrowIndex();

        // the collateral chain A vouched for must cover everything borrowed here
        (uint256 totalBorrowed, ) = ledger.accountPosition(
            p.sender,
            market,
            p.amount
        );
        require(p.collateral >= totalBorrowed, "Insufficient collateral");

        ledger.settleBorrowerTithe(market, p.sender);
        homeRouter.payOutRemoteBorrow(p.sender, p.amount, market);

        (bool found, uint256 i) = _findCollateral(
            p.sender,
            underlying,
            srcEid,
            p.srcToken
        );
        if (found) {
            LedgerStorage.Loan memory b = ledger.getForeignBackedLoans(
                p.sender,
                underlying
            )[i];
            b.principal = (b.principal * index) / b.borrowIndex + p.amount;
            b.borrowIndex = index;
            ledger.updateForeignBackedLoan(p.sender, underlying, i, b);
        } else {
            ledger.addForeignBackedLoan(
                p.sender,
                underlying,
                LedgerStorage.Loan({
                    srcEid: srcEid,
                    destEid: currentEid,
                    principal: p.amount,
                    borrowIndex: index,
                    borrowedMarket: market,
                    srcToken: p.srcToken
                })
            );
        }

        _send(
            srcEid,
            Payload({
                amount: p.amount,
                borrowIndex: index,
                collateral: p.collateral,
                sender: p.sender,
                destMarket: market,
                srcToken: p.srcToken,
                messageType: uint8(MessageType.BorrowConfirmed)
            })
        );
    }

    function repayRemoteBorrow(
        address borrower,
        uint256 amount,
        address market,
        uint32 srcEid //the chain where the collateral lives
    ) external {
        require(amount > 0, "0 amount");
        address underlying = ledger.underlyingOf(market);
        require(underlying != address(0), "Invalid market");

        (
            uint256 borrowedAmount,
            uint256 index,
            LedgerStorage.Loan memory position
        ) = remoteBorrowDetails(borrower, underlying, market, srcEid);

        uint256 repayFinal = amount == type(uint256).max
            ? borrowedAmount
            : amount;
        require(
            repayFinal <= borrowedAmount,
            "Repay must be less than or equal to borrow"
        );

        homeRouter.takeRemoteRepayment(
            borrower,
            msg.sender,
            repayFinal,
            market
        );

        uint256 currentIndex = MarketPool(market).borrowIndex();
        if (repayFinal == borrowedAmount) {
            ledger.removeForeignBackedLoan(borrower, underlying, index);
        } else {
            position.principal = borrowedAmount - repayFinal;
            position.borrowIndex = currentIndex;
            ledger.updateForeignBackedLoan(
                borrower,
                underlying,
                index,
                position
            );
        }

        _send(
            srcEid,
            Payload({
                amount: repayFinal,
                borrowIndex: currentIndex,
                collateral: 0,
                sender: borrower,
                destMarket: market,
                srcToken: position.srcToken,
                messageType: uint8(MessageType.RepayNotice)
            })
        );
        emit RepaySuccess(borrower, market, repayFinal);
    }

    function remoteBorrowDetails(
        address borrower,
        address underlying,
        address market,
        uint32 srcEid
    )
        public
        view
        returns (
            uint256 borrowedAmount,
            uint256 index,
            LedgerStorage.Loan memory position
        )
    {
        LedgerStorage.Loan[] memory list = ledger.getForeignBackedLoans(
            borrower,
            underlying
        );
        bool found;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].srcEid == srcEid) {
                position = list[i];
                index = i;
                found = true;
                borrowedAmount =
                    (list[i].principal * MarketPool(market).borrowIndex()) /
                    list[i].borrowIndex;
                break;
            }
        }
        require(found, "No borrow position found");
    }

    function _findCollateral(
        address user,
        address underlying,
        uint32 srcEid,
        address srcToken
    ) private view returns (bool, uint256) {
        LedgerStorage.Loan[] memory list = ledger.getForeignBackedLoans(
            user,
            underlying
        );
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].srcEid == srcEid && list[i].srcToken == srcToken)
                return (true, i);
        }
        return (false, 0);
    }

    // Message funcs

    function receiveMessage(uint32 srcEid, bytes calldata data) external {
        require(msg.sender == endpoint, "Not endpoint");
        Payload memory p = abi.decode(data, (Payload));
        MessageType t = MessageType(p.messageType);

        if (t == MessageType.OpenRemoteBorrow) {
            _onOpenRemoteBorrow(p, srcEid);
        } else if (t == MessageType.BorrowConfirmed) {
            _onBorrowConfirmed(p, srcEid);
        } else {
            _onRepayNotice(p, srcEid);
        }
    }

    function _send(uint32 dstEid, Payload memory p) private {
        IEndpoint(endpoint).send(dstEid, abi.encode(p));
    }
}
