// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Kink fee curve
library FeeLib {
    uint256 internal constant RAY = 1e27;

    struct FeeData {
        uint256 minMintFee; // minimum fee everyone pays
        uint256 slope0; // extra fee at the kink
        uint256 slope1; // extra fee after the kink
        uint256 mintKinkRatio; // the kink
        uint256 optimalRatio; // below this only the minMintFee is paid
    }

    function mintRate(
        FeeData memory f,
        uint256 ratio
    ) internal pure returns (uint256 rate) {
        rate = f.minMintFee;
        if (ratio > f.optimalRatio) {
            if (ratio > f.mintKinkRatio) {
                uint256 excessRatio = ratio - f.mintKinkRatio;
                rate +=
                    f.slope0 +
                    ((f.slope1 * excessRatio) / (RAY - f.mintKinkRatio));
            } else {
                rate +=
                    (f.slope0 * (ratio - f.optimalRatio)) /
                    (f.mintKinkRatio - f.optimalRatio);
            }
        }
        if (rate > RAY) rate = RAY;
    }
}
