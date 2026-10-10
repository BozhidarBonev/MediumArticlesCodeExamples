// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";

import {DummyBVault} from "../src/DummyBVault.sol";
import {FeeLib} from "../src/FeeLib.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {MockOracle} from "../src/MockOracle.sol";

contract SplitMintTest is Test {
    MockERC20 usdc;
    MockERC20 usdt;
    MockERC20 pyusd;
    MockOracle oracle;

    address lp = makeAddr("lp");
    address whale = makeAddr("whale");
    address insurance = makeAddr("insuranceFund");

    uint256 constant SEED = 300_000e6; // per asset for balanced bucket
    uint256 constant WHALE_AMOUNT = 2_000_000e6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);
        pyusd = new MockERC20("PayPal USD", "PYUSD", 6);
        oracle = new MockOracle();
    }

    // Tests
    function test_splittingTheMintReducesTheFee() public {
        (uint256 feeOnce, uint256 outOnce) = _whaleMints(1, false);
        (uint256 feeSplit, uint256 outSplit) = _whaleMints(20, false);

        console2.log("mint 2M USDC");
        console2.log("one mint / fee in bUSD:", feeOnce / 1e18);
        console2.log("one mint / received:", outOnce / 1e18);
        console2.log("20 mints / fee in bUSD:", feeSplit / 1e18);
        console2.log("20 mints / received:", outSplit / 1e18);
        console2.log("saved fee in bUSD:", (feeOnce - feeSplit) / 1e18);
        console2.log(
            "fee saved in bps of fee:",
            ((feeOnce - feeSplit) * 10_000) / feeOnce
        );

        assertLt(feeSplit, feeOnce, "splitting is cheaper");
        assertGt(outSplit, outOnce, "attacker gets more bUSD");
    }

    // More split - less pay
    function test_feeShrinksAsSplitCountGrows() public {
        uint256[7] memory splits = [uint256(1), 2, 5, 10, 20, 50, 100];
        uint256 previousFee = type(uint256).max;

        console2.log("splits | total fee (bUSD)");
        for (uint256 i; i < splits.length; ++i) {
            (uint256 fee, ) = _whaleMints(splits[i], false);
            console2.log(splits[i], fee / 1e18);
            assertLe(fee, previousFee, "fee should go down");
            previousFee = fee;
        }
    }

    // Splitting never costs more than one big mint
    function testFuzz_splittingNeverCostsMore(
        uint256 totalAmount,
        uint256 n
    ) public {
        totalAmount = bound(totalAmount, 10_000e6, 5_000_000e6);
        n = bound(n, 2, 40);

        (uint256 feeOnce, ) = _whaleMintsAmount(totalAmount, 1, false);
        (uint256 feeSplit, ) = _whaleMintsAmount(totalAmount, n, false);

        assertLe(feeSplit, feeOnce);
    }

    // Proposed fix
    function test_averagingTheRateRemovesTheIncentive() public {
        (uint256 vulnOnce, ) = _whaleMints(1, false);
        (uint256 vulnSplit, ) = _whaleMints(100, false);
        (uint256 fixedOnce, ) = _whaleMints(1, true);
        (uint256 fixedSplit, ) = _whaleMints(100, true);

        uint256 vulnGap = vulnOnce - vulnSplit;
        uint256 fixedGap = fixedOnce > fixedSplit
            ? fixedOnce - fixedSplit
            : fixedSplit - fixedOnce;

        console2.log("1 mint vs 100 mints");
        console2.log("current  gap:", vulnGap / 1e18);
        console2.log("averaged gap:", fixedGap / 1e18);
        console2.log(
            "averaged gap in bps of fee:",
            (fixedGap * 10_000) / fixedOnce
        );

        assertLt(fixedGap * 20, vulnGap, "gap gets 20x smaller");
    }

    // Internal helpers
    function _whaleMints(
        uint256 n,
        bool averaged
    ) internal returns (uint256 totalFee, uint256 totalOut) {
        return _whaleMintsAmount(WHALE_AMOUNT, n, averaged);
    }

    // Need to refresh the vault so tests run at balanced bucket
    function _whaleMintsAmount(
        uint256 totalAmount,
        uint256 n,
        bool averaged
    ) internal returns (uint256 totalFee, uint256 totalOut) {
        DummyBVault vault = _deployAndSeedVault();

        usdc.mint(whale, totalAmount);
        vm.startPrank(whale);
        usdc.approve(address(vault), totalAmount);

        uint256 chunk = totalAmount / n;
        uint256 spent;
        for (uint256 i; i < n; ++i) {
            uint256 amountIn = i == n - 1 ? totalAmount - spent : chunk;
            spent += amountIn;

            (uint256 out, uint256 fee) = averaged
                ? vault.mintAveraged(address(usdc), amountIn, 0, whale)
                : vault.mint(address(usdc), amountIn, 0, whale);
            totalOut += out;
            totalFee += fee;
        }
        vm.stopPrank();
    }

    function _deployAndSeedVault() internal returns (DummyBVault vault) {
        address[] memory assets = new address[](3);
        assets[0] = address(usdc);
        assets[1] = address(usdt);
        assets[2] = address(pyusd);

        FeeLib.FeeData memory feeData = FeeLib.FeeData({
            minMintFee: 0.005e27, // 0.5%
            slope0: 0.01e27, // 1%
            slope1: 0.1e27, // 10%
            mintKinkRatio: 0.85e27, // 85%
            optimalRatio: 0.33e27 // 33%
        });

        vault = new DummyBVault(oracle, insurance, assets, feeData);

        // everything is $1
        oracle.setPrice(address(usdc), 1e8);
        oracle.setPrice(address(usdt), 1e8);
        oracle.setPrice(address(pyusd), 1e8);
        oracle.setPrice(address(vault), 1e8);

        // the LP whitelisted so no kink curve, just min fee
        vault.setWhitelist(lp, true);
        _seed(vault, usdc);
        _seed(vault, usdt);
        _seed(vault, pyusd);
    }

    function _seed(DummyBVault vault, MockERC20 token) internal {
        token.mint(lp, SEED);
        vm.startPrank(lp);
        token.approve(address(vault), SEED);
        vault.mint(address(token), SEED, 0, lp);
        vm.stopPrank();
    }
}
