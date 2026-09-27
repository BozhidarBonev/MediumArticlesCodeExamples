// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MarginLedger} from "./MarginLedger.sol";
import {PriceOracle} from "./PriceOracle.sol";
import {IDealer} from "./IDealer.sol";

contract PerpEngine {
    MarginLedger public immutable ledger;
    PriceOracle public immutable oracle;
    uint256 public immutable priceBandRatioWad; // 0.10e18 == +/-10%
    uint256 public constant WAD = 1e18;

    event PositionOpened(
        address taker,
        address dealer,
        int256 baseDelta,
        int256 quoteDelta,
        uint256 tradePrice
    );

    constructor(
        MarginLedger _ledger,
        PriceOracle _oracle,
        uint256 _priceBandRatioWad
    ) {
        ledger = _ledger;
        oracle = _oracle;
        priceBandRatioWad = _priceBandRatioWad;
    }

    function openPosition(
        IDealer dealer,
        bool isBaseToQuote,
        uint256 amount
    ) external returns (int256 baseDelta, int256 quoteDelta) {
        uint256 oppositeAmount = dealer.fillOrder(isBaseToQuote, amount);

        if (isBaseToQuote) {
            baseDelta = -int256(amount);
            quoteDelta = int256(oppositeAmount);
        } else {
            baseDelta = int256(oppositeAmount);
            quoteDelta = -int256(amount);
        }

        uint256 tradePrice = (absolute(quoteDelta) * WAD) / absolute(baseDelta);
        _checkPriceBand(tradePrice);

        ledger.settleTrade(msg.sender, address(dealer), baseDelta, quoteDelta);

        require(
            ledger.getAccountValue(msg.sender, oracle.getPrice()) >= 0,
            "Insufficient margin"
        );

        emit PositionOpened(
            msg.sender,
            address(dealer),
            baseDelta,
            quoteDelta,
            tradePrice
        );
    }

    function _checkPriceBand(uint256 tradePrice) internal view {
        uint256 oraclePrice = oracle.getPrice();
        uint256 upper = (oraclePrice * (WAD + priceBandRatioWad)) / WAD;
        uint256 lower = (oraclePrice * (WAD - priceBandRatioWad)) / WAD;
        require(
            tradePrice <= upper && tradePrice >= lower,
            "Out of band"
        );
    }

    function absolute(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
