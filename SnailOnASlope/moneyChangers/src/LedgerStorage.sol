// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {MarketPool} from "./MarketPool.sol";

contract LedgerStorage {
    uint256 public constant TITHE_INITIAL_INDEX = 1e36;
    uint256 public constant COLLATERAL_FACTOR = 0.75e18;

    struct Loan {
        uint256 srcEid; // chain where the collateral lives / the borrow was started
        uint256 destEid; // chain where the funds were actually borrowed
        uint256 principal; // debt at the time of borrowIndex
        uint256 borrowIndex; // destination market borrow index
        address borrowedMarket; // the market the funds came from (destination chain)
        address srcToken; // the token on the source chain
    }

    struct BorrowMarketState {
        uint256 amount;
        uint256 borrowIndex;
    }

    uint256 public immutable currentEid;
    address public owner;

    // token <-> market
    mapping(address underlying => address market) public marketOf;
    mapping(address market => address underlying) public underlyingOf;
    mapping(address underlying => mapping(uint32 destEid => address destMarket))
        public destMarketOf;

    // collateral and same chain debt
    mapping(address user => mapping(address market => uint256))
        public totalInvestment;
    mapping(address user => mapping(address market => BorrowMarketState))
        public borrowBalance;

    // cross chain debt
    mapping(address user => mapping(address underlying => Loan[]))
        public outboundLoans;
    mapping(address user => mapping(address underlying => Loan[]))
        public foreignBackedLoans;

    // TITHE rewards
    mapping(address market => mapping(address user => uint256))
        public titheBorrowerIndex;
    mapping(address user => uint256) public titheAccrued;

    mapping(address => bool) public authorized;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "Caller not authorized");
        _;
    }

    constructor(uint32 _currentEid) {
        currentEid = _currentEid;
        owner = msg.sender;
    }

    // Admin funcs

    function setAuthorized(address who, bool value) external onlyOwner {
        authorized[who] = value;
    }

    function addMarket(address underlying, address market) external onlyOwner {
        marketOf[underlying] = market;
        underlyingOf[market] = underlying;
    }

    function setDestMarket(
        address underlying,
        uint32 destEid,
        address destMarket
    ) external onlyOwner {
        destMarketOf[underlying][destEid] = destMarket;
    }

    // Add/update/set/remove

    function updateTotalInvestment(
        address user,
        address market,
        uint256 amount
    ) external onlyAuthorized {
        totalInvestment[user][market] += amount;
    }

    function updateBorrowBalance(
        address user,
        address market,
        uint256 amount,
        uint256 index
    ) external onlyAuthorized {
        borrowBalance[user][market] = BorrowMarketState(amount, index);
    }

    function removeBorrowBalance(
        address user,
        address market
    ) external onlyAuthorized {
        delete borrowBalance[user][market];
    }

    function setTitheAccrued(
        address user,
        uint256 amount
    ) external onlyAuthorized {
        titheAccrued[user] = amount;
    }

    function addOutboundLoan(
        address user,
        address underlying,
        Loan memory b
    ) external onlyAuthorized {
        outboundLoans[user][underlying].push(b);
    }

    function updateOutboundLoan(
        address user,
        address underlying,
        uint256 i,
        Loan memory b
    ) external onlyAuthorized {
        outboundLoans[user][underlying][i] = b;
    }

    function removeOutboundLoan(
        address user,
        address underlying,
        uint256 i
    ) external onlyAuthorized {
        Loan[] storage list = outboundLoans[user][underlying];
        list[i] = list[list.length - 1];
        list.pop();
    }

    function addForeignBackedLoan(
        address user,
        address underlying,
        Loan memory b
    ) external onlyAuthorized {
        foreignBackedLoans[user][underlying].push(b);
    }

    function updateForeignBackedLoan(
        address user,
        address underlying,
        uint256 i,
        Loan memory b
    ) external onlyAuthorized {
        foreignBackedLoans[user][underlying][i] = b;
    }

    function removeForeignBackedLoan(
        address user,
        address underlying,
        uint256 i
    ) external onlyAuthorized {
        Loan[] storage list = foreignBackedLoans[user][underlying];
        list[i] = list[list.length - 1];
        list.pop();
    }

    // View funcs

    function getOutboundLoans(
        address user,
        address underlying
    ) external view returns (Loan[] memory) {
        return outboundLoans[user][underlying];
    }

    function getForeignBackedLoans(
        address user,
        address underlying
    ) external view returns (Loan[] memory) {
        return foreignBackedLoans[user][underlying];
    }

    function getBorrowBalance(
        address user,
        address market
    ) external view returns (BorrowMarketState memory) {
        return borrowBalance[user][market];
    }

    // External & public
    function sameChainDebt(
        address borrower,
        address market
    ) public view returns (uint256) {
        BorrowMarketState memory s = borrowBalance[borrower][market];
        if (s.borrowIndex == 0) return 0;
        return (s.amount * MarketPool(market).borrowIndex()) / s.borrowIndex;
    }

    function crossChainDebt(
        address borrower,
        address market
    ) public view virtual returns (uint256) {
        address token = underlyingOf[market];
        uint256 index = MarketPool(market).borrowIndex();
        uint256 borrowedAmount;

        Loan[] memory outbound = outboundLoans[borrower][token];
        Loan[] memory foreign = foreignBackedLoans[borrower][token];

        require(
            outbound.length == 0 || foreign.length == 0,
            "Invariant violated: both mappings populated"
        );

        if (outbound.length > 0) {
            for (uint256 i = 0; i < outbound.length; i++) {
                if (outbound[i].srcEid == currentEid) {
                    borrowedAmount +=
                        (outbound[i].principal * index) /
                        outbound[i].borrowIndex;
                }
            }
        } else {
            for (uint256 i = 0; i < foreign.length; i++) {
                if (
                    foreign[i].destEid == currentEid &&
                    foreign[i].srcEid == currentEid
                ) {
                    borrowedAmount +=
                        (foreign[i].principal * index) /
                        foreign[i].borrowIndex;
                }
            }
        }
        return borrowedAmount;
    }

    function accountPosition(
        address account,
        address market,
        uint256 borrowAmount
    ) public view returns (uint256 borrowed, uint256 collateral) {
        collateral =
            (totalInvestment[account][market] * COLLATERAL_FACTOR) /
            1e18;
        borrowed =
            sameChainDebt(account, market) +
            crossChainDebt(account, market) +
            borrowAmount;
    }

    function findOutboundLoan(
        address user,
        address underlying,
        uint256 srcEid,
        uint256 destEid,
        address borrowedMarket
    ) public view returns (bool, uint256) {
        Loan[] memory list = outboundLoans[user][underlying];
        for (uint256 i = 0; i < list.length; i++) {
            if (
                list[i].srcEid == srcEid &&
                list[i].destEid == destEid &&
                list[i].borrowedMarket == borrowedMarket
            ) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    // Rewards funcs

    function settleBorrowerTithe(
        address market,
        address borrower
    ) external onlyAuthorized {
        MarketPool m = MarketPool(market);
        m.updateBorrowRewardIndex();
        uint256 marketIndex = m.borrowRewardIndex();

        uint256 userIndex = titheBorrowerIndex[market][borrower];
        titheBorrowerIndex[market][borrower] = marketIndex;
        if (userIndex == 0) userIndex = TITHE_INITIAL_INDEX;

        uint256 deltaIndex = marketIndex - userIndex;
        uint256 borrowerAmount = (_rewardBearingDebt(borrower, market) * 1e18) /
            m.borrowIndex();

        titheAccrued[borrower] += (borrowerAmount * deltaIndex) / 1e36;
    }

    function _rewardBearingDebt(
        address borrower,
        address market
    ) internal view virtual returns (uint256) {
        return
            crossChainDebt(borrower, market) + sameChainDebt(borrower, market);
    }
}
